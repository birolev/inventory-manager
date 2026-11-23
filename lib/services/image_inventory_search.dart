import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inventory_search.dart';

class ImageInventorySearchResult {
  const ImageInventorySearchResult({
    required this.aiCriteria,
    required this.criteria,
    required this.matches,
    required this.usedFallback,
  });

  final Map<String, dynamic>? aiCriteria;
  final InventorySearchCriteria criteria;
  final List<Map<String, dynamic>> matches;
  final bool usedFallback;
}

class ImageEmbeddingBackfillResult {
  const ImageEmbeddingBackfillResult({
    required this.attempted,
    required this.updated,
    required this.failed,
    required this.errors,
  });

  final int attempted;
  final int updated;
  final int failed;
  final List<String> errors;
}

enum ImageSearchMode { embedded, gemini, automatic }

/// Image embedding and inventory matching for image based search flows.
class ImageInventorySearch {
  ImageInventorySearch._();

  static Future<ImageInventorySearchResult> searchByImage({
    required Uint8List imageBytes,
    required String mimeType,
    required InventorySearchCriteria criteria,
    ImageSearchMode mode = ImageSearchMode.automatic,
  }) async {
    if (mode == ImageSearchMode.gemini) {
      return _searchWithGemini(imageBytes, mimeType, criteria);
    }
    try {
      final embedding = await _createEmbedding(imageBytes, mimeType);
      final rows = await Supabase.instance.client.rpc(
        'search_inventory_by_embedding',
        params: {
          'p_embedding': embedding,
          'p_location': _optional(criteria.location),
          'p_only_unsold': criteria.onlyUnsold,
          'p_limit': criteria.maxResults ?? 50,
          'p_category': _optional(criteria.category),
          'p_gender': _optional(criteria.gender),
          'p_size': _optional(criteria.size),
          'p_brand': _optional(criteria.brand),
          'p_color': _optional(criteria.color),
          'p_pattern': _optional(criteria.pattern),
          'p_name': _optional(criteria.name),
          'p_condition': _optional(criteria.condition),
        },
      );
      final matches = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (matches.isNotEmpty) {
        return ImageInventorySearchResult(
          aiCriteria: null,
          criteria: criteria,
          matches: matches,
          usedFallback: false,
        );
      }
      if (mode == ImageSearchMode.embedded) {
        return ImageInventorySearchResult(
          aiCriteria: null,
          criteria: criteria,
          matches: const [],
          usedFallback: false,
        );
      }
    } catch (error) {
      if (mode == ImageSearchMode.embedded) rethrow;
      // Keep image search usable while vector generation or the RPC is being
      // deployed, and when a provider temporarily fails.
      debugPrint('Vector image search unavailable; using Gemini: $error');
    }

    return _searchWithGemini(imageBytes, mimeType, criteria);
  }

  static Future<ImageInventorySearchResult> _searchWithGemini(
    Uint8List imageBytes,
    String mimeType,
    InventorySearchCriteria criteria,
  ) async {
    final aiCriteria = await _analyzeWithGemini(imageBytes, mimeType);
    final fallbackCriteria = InventorySearchCriteria(
      category: _preferred(criteria.category, aiCriteria['category']),
      gender: _preferred(criteria.gender, aiCriteria['gender']),
      location: criteria.location,
      size: _preferred(criteria.size, aiCriteria['size']),
      brand: _preferred(criteria.brand, aiCriteria['brand']),
      color: _preferred(criteria.color, aiCriteria['color']),
      pattern: _preferred(criteria.pattern, aiCriteria['pattern']),
      name: criteria.name,
      condition: criteria.condition,
      onlyUnsold: criteria.onlyUnsold,
      sortColumn: criteria.sortColumn,
      ascending: criteria.ascending,
      pageSize: criteria.pageSize,
      maxResults: criteria.maxResults,
    );
    final result = await search(fallbackCriteria);
    return ImageInventorySearchResult(
      aiCriteria: aiCriteria,
      criteria: result.criteria,
      matches: result.matches,
      usedFallback: true,
    );
  }

  static String? _preferred(String? selected, dynamic detected) {
    final current = _optional(selected);
    if (current != null) return current;
    final aiValue = detected?.toString().trim();
    return aiValue == null || aiValue.isEmpty ? null : aiValue;
  }

  static Future<Map<String, dynamic>> _analyzeWithGemini(
    Uint8List imageBytes,
    String mimeType,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'gemini-vision',
      body: {
        'task': 'search',
        'imageBase64': base64Encode(imageBytes),
        'mimeType': mimeType,
      },
    );
    if (response.status != 200) {
      throw Exception('Image analysis failed: ${response.data}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final result = data['result'];
    return result is Map ? Map<String, dynamic>.from(result) : data;
  }

  /// Embeds the next small batch of legacy rows without touching item data.
  /// Only rows whose embedding is still null are updated.
  static Future<ImageEmbeddingBackfillResult> backfillMissing({
    int limit = 3,
  }) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('inventory')
        .select('id,image_url')
        .isFilter('embedding', null)
        .not('image_url', 'is', null)
        .order('created_at')
        .limit(limit.clamp(1, 3));

    var updated = 0;
    var failed = 0;
    final errors = <String>[];
    for (final rawRow in rows as List) {
      try {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final url = row['image_url']?.toString();
        if (url == null || url.isEmpty) {
          failed++;
          errors.add('Inventory item ${row['id']} has no image URL.');
          continue;
        }
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 ||
            response.bodyBytes.isEmpty ||
            response.bodyBytes.length > 6_000_000) {
          failed++;
          errors.add(
            'Could not download image for item ${row['id']} '
            '(HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes).',
          );
          continue;
        }
        var mimeType = (response.headers['content-type'] ?? '')
            .split(';')
            .first
            .trim()
            .toLowerCase();
        if (mimeType == 'image/jpg') mimeType = 'image/jpeg';
        if (mimeType != 'image/jpeg' && mimeType != 'image/png') {
          failed++;
          errors.add(
            'Item ${row['id']} uses unsupported image type "$mimeType"; JPEG or PNG is required.',
          );
          continue;
        }
        final embedding = await _createEmbedding(response.bodyBytes, mimeType);
        final updatedRows = await client
            .from('inventory')
            .update({'embedding': embedding})
            .eq('id', row['id'])
            .isFilter('embedding', null)
            .select('id');
        updated += (updatedRows as List).length;
      } catch (error) {
        failed++;
        errors.add('Item ${rawRow['id']}: $error');
      }
    }
    return ImageEmbeddingBackfillResult(
      attempted: (rows as List).length,
      updated: updated,
      failed: failed,
      errors: errors,
    );
  }

  static Future<List<num>> _createEmbedding(
    Uint8List imageBytes,
    String mimeType,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'image-embedding',
      body: {'imageBase64': base64Encode(imageBytes), 'mimeType': mimeType},
    );
    if (response.status != 200) {
      throw Exception('Image embedding failed: ${response.data}');
    }
    final payload = Map<String, dynamic>.from(response.data as Map);
    return (payload['embedding'] as List).cast<num>();
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null ||
            normalized.isEmpty ||
            normalized == 'Minden' ||
            normalized == 'All locations'
        ? null
        : normalized;
  }

  static Future<ImageInventorySearchResult> search(
    InventorySearchCriteria criteria,
  ) async {
    var matches = await InventorySearch.search(criteria);
    if (matches.isNotEmpty) {
      return ImageInventorySearchResult(
        aiCriteria: null,
        criteria: criteria,
        matches: matches,
        usedFallback: false,
      );
    }

    final fallbackCriteria = InventorySearchCriteria(
      category: criteria.category,
      location: criteria.location,
      brand: criteria.brand,
      onlyUnsold: criteria.onlyUnsold,
      fallback: true,
      sortColumn: criteria.sortColumn,
      ascending: criteria.ascending,
      pageSize: criteria.pageSize,
      maxResults: criteria.maxResults,
    );
    matches = await InventorySearch.search(fallbackCriteria);
    return ImageInventorySearchResult(
      aiCriteria: null,
      criteria: fallbackCriteria,
      matches: matches,
      usedFallback: true,
    );
  }
}
