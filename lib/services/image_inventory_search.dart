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
    this.embedding,
    this.resolvedMode,
  });

  final Map<String, dynamic>? aiCriteria;
  final InventorySearchCriteria criteria;
  final List<Map<String, dynamic>> matches;
  final bool usedFallback;
  final List<num>? embedding;
  final ImageSearchMode? resolvedMode;
}

class ImageEmbeddingBackfillResult {
  const ImageEmbeddingBackfillResult({
    required this.total,
    required this.attempted,
    required this.updated,
    required this.failed,
    required this.errors,
    required this.stoppedEarly,
  });

  final int total;
  final int attempted;
  final int updated;
  final int failed;
  final List<String> errors;
  final bool stoppedEarly;
}

enum ImageSearchMode { embedded, gemini, automatic }

/// Abstraction over Supabase search & image analysis calls so controllers and
/// screens can be tested cleanly without live network calls.
abstract class InventorySearchGateway {
  Future<ImageInventorySearchResult> searchByImage({
    required Uint8List imageBytes,
    required String mimeType,
    required InventorySearchCriteria criteria,
    required ImageSearchMode mode,
    required InventorySortOption sortOption,
  });

  Future<ImageInventorySearchResult> searchByExistingEmbedding({
    required List<num> embedding,
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
  });

  Future<ImageInventorySearchResult> searchByCriteria({
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
    bool allowFallback = true,
  });
}

class SupabaseInventorySearchGateway implements InventorySearchGateway {
  const SupabaseInventorySearchGateway();

  @override
  Future<ImageInventorySearchResult> searchByImage({
    required Uint8List imageBytes,
    required String mimeType,
    required InventorySearchCriteria criteria,
    required ImageSearchMode mode,
    required InventorySortOption sortOption,
  }) {
    return ImageInventorySearch.searchByImage(
      imageBytes: imageBytes,
      mimeType: mimeType,
      criteria: criteria,
      mode: mode,
      sortOption: sortOption,
    );
  }

  @override
  Future<ImageInventorySearchResult> searchByExistingEmbedding({
    required List<num> embedding,
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
  }) {
    return ImageInventorySearch.searchByExistingEmbedding(
      embedding: embedding,
      criteria: criteria,
      sortOption: sortOption,
    );
  }

  @override
  Future<ImageInventorySearchResult> searchByCriteria({
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
    bool allowFallback = true,
  }) {
    return ImageInventorySearch.search(
      criteria,
      sortOption: sortOption,
      allowFallback: allowFallback,
    );
  }
}

/// Image embedding and inventory matching for image based search flows.
class ImageInventorySearch {
  ImageInventorySearch._();

  static Future<ImageInventorySearchResult> searchByImage({
    required Uint8List imageBytes,
    required String mimeType,
    required InventorySearchCriteria criteria,
    ImageSearchMode mode = ImageSearchMode.automatic,
    InventorySortOption? sortOption,
  }) async {
    final effectiveSort =
        sortOption ??
        (mode == ImageSearchMode.gemini
            ? InventorySortOption.fromColumnAndDirection(
                sortColumn: criteria.sortColumn,
                ascending: criteria.ascending,
              )
            : InventorySortOption.relevance);

    if (mode == ImageSearchMode.gemini) {
      return _searchWithGemini(
        imageBytes,
        mimeType,
        criteria,
        sortOption: effectiveSort == InventorySortOption.relevance
            ? InventorySortOption.newest
            : effectiveSort,
      );
    }
    try {
      final embedding = await _createEmbedding(imageBytes, mimeType);
      final result = await searchByExistingEmbedding(
        embedding: embedding,
        criteria: criteria,
        sortOption: effectiveSort,
      );
      if (result.matches.isNotEmpty || mode == ImageSearchMode.embedded) {
        return result;
      }
    } catch (error) {
      if (mode == ImageSearchMode.embedded) rethrow;
      // Keep image search usable while vector generation or the RPC is being
      // deployed, and when a provider temporarily fails.
      debugPrint('Vector image search unavailable; using Gemini: $error');
    }

    return _searchWithGemini(
      imageBytes,
      mimeType,
      criteria,
      sortOption: effectiveSort == InventorySortOption.relevance
          ? InventorySortOption.newest
          : effectiveSort,
    );
  }

  /// Queries inventory matches using an already-generated embedding vector
  /// (avoiding redundant embedding API calls when filters change).
  static Future<ImageInventorySearchResult> searchByExistingEmbedding({
    required List<num> embedding,
    required InventorySearchCriteria criteria,
    InventorySortOption sortOption = InventorySortOption.relevance,
  }) async {
    final saleStatus = criteria.effectiveSaleStatus;
    final rows = await Supabase.instance.client.rpc(
      'search_inventory_by_embedding',
      params: {
        'p_embedding': embedding,
        'p_location': _optional(criteria.location),
        'p_only_unsold': saleStatus == InventorySaleStatusFilter.available,
        'p_limit': criteria.maxResults ?? 100,
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
    var rawMatches = (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (saleStatus == InventorySaleStatusFilter.sold) {
      rawMatches = rawMatches
          .where((item) => item['is_sold'] == true)
          .toList();
    }
    final sortedMatches = InventorySearch.sortResults(
      rawMatches,
      sortOption: sortOption,
      preferredCategory: criteria.category,
    );
    return ImageInventorySearchResult(
      aiCriteria: null,
      criteria: criteria,
      matches: sortedMatches,
      usedFallback: false,
      embedding: embedding,
      resolvedMode: ImageSearchMode.embedded,
    );
  }

  static Future<ImageInventorySearchResult> _searchWithGemini(
    Uint8List imageBytes,
    String mimeType,
    InventorySearchCriteria criteria, {
    required InventorySortOption sortOption,
  }) async {
    final aiCriteria = await _analyzeWithGemini(imageBytes, mimeType);
    final resolvedCategory = _preferredCategory(
      criteria.category,
      aiCriteria['category'],
    );
    final resolvedGender = _preferredGender(
      criteria.gender,
      aiCriteria['gender'],
    );
    final queryCriteria = InventorySearchCriteria(
      category: resolvedCategory,
      gender: resolvedGender,
      location: criteria.location,
      size: _preferred(criteria.size, aiCriteria['size']),
      brand: _preferred(criteria.brand, aiCriteria['brand']),
      color: _preferred(criteria.color, aiCriteria['color']),
      pattern: _preferred(criteria.pattern, aiCriteria['pattern']),
      name: criteria.name,
      condition: criteria.condition,
      onlyUnsold: criteria.onlyUnsold,
      saleStatus: criteria.effectiveSaleStatus,
      sortColumn: sortOption.sortColumn,
      ascending: sortOption.ascending,
      pageSize: criteria.pageSize,
      maxResults: criteria.maxResults,
    );
    final result = await search(
      queryCriteria,
      sortOption: sortOption,
      allowFallback: true,
    );
    return ImageInventorySearchResult(
      aiCriteria: aiCriteria,
      criteria: result.criteria,
      matches: result.matches,
      usedFallback: result.usedFallback,
      resolvedMode: ImageSearchMode.gemini,
    );
  }

  static String? _preferredCategory(String? selected, dynamic detected) {
    final current = _optional(selected);
    if (current != null) return InventorySearch.normalizeCategory(current);
    final normalized = InventorySearch.normalizeCategory(detected);
    return normalized == 'Minden' ? null : normalized;
  }

  static String? _preferredGender(String? selected, dynamic detected) {
    final current = _optional(selected);
    if (current != null) return InventorySearch.normalizeGender(current);
    final normalized = InventorySearch.normalizeGender(detected);
    return normalized == 'Minden' ? null : normalized;
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
    void Function(int completed, int total)? onProgress,
  }) async {
    final client = Supabase.instance.client;
    const pageSize = 200;
    final rows = <dynamic>[];
    var offset = 0;
    while (true) {
      final page = await client
          .from('inventory')
          .select('id,image_url')
          .isFilter('embedding', null)
          .not('image_url', 'is', null)
          .order('id')
          .range(offset, offset + pageSize - 1);
      rows.addAll(page as List);
      if ((page as List).length < pageSize) break;
      offset += pageSize;
    }

    var updated = 0;
    var failed = 0;
    final errors = <String>[];
    var completed = 0;
    var consecutiveExceptions = 0;
    var stoppedEarly = false;
    for (final rawRow in rows) {
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
        consecutiveExceptions = 0;
      } catch (error) {
        failed++;
        errors.add('Item ${rawRow['id']}: $error');
        consecutiveExceptions++;
      } finally {
        completed++;
        onProgress?.call(completed, rows.length);
      }
      if (consecutiveExceptions >= 3) {
        stoppedEarly = true;
        break;
      }
    }
    return ImageEmbeddingBackfillResult(
      total: rows.length,
      attempted: completed,
      updated: updated,
      failed: failed,
      errors: errors,
      stoppedEarly: stoppedEarly,
    );
  }

  static Future<bool> hasMissingEmbeddings() async {
    final rows = await Supabase.instance.client
        .from('inventory')
        .select('id')
        .isFilter('embedding', null)
        .not('image_url', 'is', null)
        .limit(1);
    return (rows as List).isNotEmpty;
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
    InventorySearchCriteria criteria, {
    InventorySortOption? sortOption,
    bool allowFallback = true,
  }) async {
    final effectiveSort =
        sortOption ??
        InventorySortOption.fromColumnAndDirection(
          sortColumn: criteria.sortColumn,
          ascending: criteria.ascending,
        );
    final alignedCriteria = criteria.copyWith(
      sortColumn: effectiveSort.sortColumn,
      ascending: effectiveSort.ascending,
    );
    var matches = await InventorySearch.search(alignedCriteria);
    matches = InventorySearch.sortResults(
      matches,
      sortOption: effectiveSort,
      preferredCategory: alignedCriteria.category,
    );
    if (matches.isNotEmpty || !allowFallback) {
      return ImageInventorySearchResult(
        aiCriteria: null,
        criteria: alignedCriteria,
        matches: matches,
        usedFallback: false,
      );
    }

    final fallbackCriteria = InventorySearchCriteria(
      category: alignedCriteria.category,
      location: alignedCriteria.location,
      brand: alignedCriteria.brand,
      onlyUnsold: alignedCriteria.onlyUnsold,
      saleStatus: alignedCriteria.effectiveSaleStatus,
      fallback: true,
      sortColumn: alignedCriteria.sortColumn,
      ascending: alignedCriteria.ascending,
      pageSize: alignedCriteria.pageSize,
      maxResults: alignedCriteria.maxResults,
    );
    matches = await InventorySearch.search(fallbackCriteria);
    matches = InventorySearch.sortResults(
      matches,
      sortOption: effectiveSort,
      preferredCategory: fallbackCriteria.category,
    );
    return ImageInventorySearchResult(
      aiCriteria: null,
      criteria: fallbackCriteria,
      matches: matches,
      usedFallback: true,
    );
  }
}
