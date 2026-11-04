import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared criteria for every screen that searches inventory.
class InventorySearchCriteria {
  const InventorySearchCriteria({
    this.category,
    this.gender,
    this.location,
    this.size,
    this.brand,
    this.color,
    this.pattern,
    this.name,
    this.condition,
    this.text,
    this.onlyUnsold = false,
    this.fallback = false,
    this.sortColumn = 'created_at',
    this.ascending = false,
    this.pageSize = 1000,
    this.maxResults,
  });

  final String? category;
  final String? gender;
  final String? location;
  final String? size;
  final String? brand;
  final String? color;
  final String? pattern;
  final String? name;
  final String? condition;
  final String? text;
  final bool onlyUnsold;
  final bool fallback;
  final String sortColumn;
  final bool ascending;
  final int pageSize;
  final int? maxResults;
}

/// Builds and pages the inventory query so filters behave the same everywhere.
class InventorySearch {
  InventorySearch._();

  static const columns =
      'id, name, brand, price_est, category, gender, location, size, color, pattern, condition, image_url, is_sold, created_at';

  static const sortableColumns = {'created_at', 'price_est'};

  static String seekFilter({
    required String sortColumn,
    required bool ascending,
    required String? sortValue,
    required String id,
  }) {
    if (!sortableColumns.contains(sortColumn)) {
      throw ArgumentError.value(sortColumn, 'sortColumn', 'Unsupported sort column');
    }
    if (sortValue == null) return 'and($sortColumn.is.null,id.gt.$id)';
    final operator = ascending ? 'gt' : 'lt';
    return '$sortColumn.$operator.$sortValue,'
        'and($sortColumn.eq.$sortValue,id.gt.$id),$sortColumn.is.null';
  }

  static const _colorFamilies = <List<String>>[
    ['kék', 'kek', 'blue', 'navy', 'tengerészkék', 'azúr', 'türkiz', 'cyan'],
    ['pink', 'rózsaszín', 'rozsaszin', 'magenta', 'magneta', 'fukszia', 'fuchsia', 'ciklámen', 'ciklamen'],
    ['piros', 'vörös', 'voros', 'red', 'bordó', 'bordo', 'burgundy'],
    ['zöld', 'zold', 'green', 'olíva', 'oliva', 'khaki'],
    ['sárga', 'sarga', 'yellow', 'mustár', 'mustard'],
    ['narancs', 'orange', 'barack', 'peach'],
    ['lila', 'purple', 'ibolya', 'violet', 'levendula', 'lavender'],
    ['barna', 'brown', 'csoki', 'chocolate', 'bézs', 'beige'],
    ['szürke', 'szurke', 'grey', 'gray', 'ezüst', 'silver'],
    ['fehér', 'feher', 'white', 'krém', 'krem', 'ivory'],
    ['fekete', 'black'],
  ];

  static List<String> _colorTerms(String input) {
    final normalized = input.trim().toLowerCase();
    for (final family in _colorFamilies) {
      if (family.any(normalized.contains)) return family;
    }
    return [input.trim()];
  }

  static Future<List<Map<String, dynamic>>> search(
    InventorySearchCriteria criteria,
  ) async {
    if (criteria.maxResults != null && criteria.maxResults! <= 0) return [];
    final results = <Map<String, dynamic>>[];
    if (!sortableColumns.contains(criteria.sortColumn)) {
      throw ArgumentError.value(criteria.sortColumn, 'sortColumn', 'Unsupported sort column');
    }
    final pageSize = criteria.pageSize.clamp(1, 1000).toInt();
    String? cursorSortValue;
    String? cursorId;

    while (true) {
      dynamic query = Supabase.instance.client.from('inventory').select(columns);
      if (criteria.onlyUnsold) query = query.eq('is_sold', false);

      final category = criteria.category?.trim() ?? '';
      if (category.isNotEmpty && category != 'Minden') {
        query = query.eq('category', category);
      }
      final gender = criteria.gender?.trim() ?? '';
      if (!criteria.fallback && gender.isNotEmpty && gender != 'Minden') {
        query = query.eq('gender', gender);
      }
      final location = criteria.location?.trim() ?? '';
      if (location.isNotEmpty && location != 'All locations') {
        query = query.eq('location', location);
      }

      final brand = criteria.brand?.trim() ?? '';
      if (brand.isNotEmpty) query = query.ilike('brand', '%$brand%');
      final text = criteria.text?.trim() ?? '';
      if (text.isNotEmpty) {
        final safeText = text.replaceAll(',', '');
        query = query.or('name.ilike.%$safeText%,brand.ilike.%$safeText%');
      }

      if (!criteria.fallback) {
        final size = criteria.size?.trim() ?? '';
        if (size.isNotEmpty) query = query.ilike('size', size);
        final color = criteria.color?.trim() ?? '';
        if (color.isNotEmpty) {
          query = query.or(
            _colorTerms(color).map((term) => 'color.ilike.%$term%').join(','),
          );
        }
        final pattern = criteria.pattern?.trim() ?? '';
        if (pattern.isNotEmpty) query = query.ilike('pattern', '%$pattern%');
        final name = criteria.name?.trim() ?? '';
        if (name.isNotEmpty) query = query.ilike('name', '%$name%');
        final condition = criteria.condition?.trim() ?? '';
        if (condition.isNotEmpty) {
          query = query.ilike('condition', '%$condition%');
        }
      }

      if (cursorId != null) {
        query = query.or(
          seekFilter(
            sortColumn: criteria.sortColumn,
            ascending: criteria.ascending,
            sortValue: cursorSortValue,
            id: cursorId,
          ),
        );
      }

      final currentPageSize = criteria.maxResults == null
          ? pageSize
          : (criteria.maxResults! - results.length)
                .clamp(1, pageSize)
                .toInt();
      final page = await query
          .order(
            criteria.sortColumn,
            ascending: criteria.ascending,
            nullsFirst: false,
          )
          .order('id')
          .limit(currentPageSize);
      results.addAll(
        (page as List).map((row) => Map<String, dynamic>.from(row as Map)),
      );
      if (page.length < currentPageSize ||
          (criteria.maxResults != null &&
              results.length >= criteria.maxResults!)) {
        break;
      }
      final lastRow = Map<String, dynamic>.from(page.last as Map);
      cursorSortValue = lastRow[criteria.sortColumn]?.toString();
      cursorId = lastRow['id']?.toString();
      if (cursorId == null) break;
    }
    return results;
  }
}
