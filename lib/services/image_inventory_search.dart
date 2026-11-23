import 'dart:convert';
import 'dart:typed_data';

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

/// Shared image analysis and inventory matching for image based search flows.
class ImageInventorySearch {
  ImageInventorySearch._();

  static Future<ImageInventorySearchResult> analyzeAndSearch({
    required Uint8List imageBytes,
    required String mimeType,
    required InventorySearchCriteria Function(Map<String, dynamic> aiCriteria)
    criteriaFor,
  }) async {
    final aiCriteria = await analyze(
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
    final result = await search(criteriaFor(aiCriteria));
    return ImageInventorySearchResult(
      aiCriteria: aiCriteria,
      criteria: result.criteria,
      matches: result.matches,
      usedFallback: result.usedFallback,
    );
  }

  static Future<Map<String, dynamic>> analyze({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
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
    final responseData = Map<String, dynamic>.from(response.data as Map);
    final result = responseData['result'];
    return result is Map ? Map<String, dynamic>.from(result) : responseData;
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
