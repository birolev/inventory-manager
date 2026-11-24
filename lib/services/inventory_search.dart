import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';

/// Canonical sort options supported across all inventory search screens.
enum InventorySortOption {
  relevance,
  newest,
  oldest,
  priceAsc,
  priceDesc;

  String get label => switch (this) {
    InventorySortOption.relevance => 'Legjobb találat',
    InventorySortOption.newest => 'Legújabb elöl',
    InventorySortOption.oldest => 'Legrégebbi elöl',
    InventorySortOption.priceAsc => 'Ár: növekvő',
    InventorySortOption.priceDesc => 'Ár: csökkenő',
  };

  String get shortDescription => switch (this) {
    InventorySortOption.relevance => 'legjobb találat',
    InventorySortOption.newest => 'legújabb',
    InventorySortOption.oldest => 'legrégebbi',
    InventorySortOption.priceAsc => 'ár növekvő',
    InventorySortOption.priceDesc => 'ár csökkenő',
  };

  String get sortColumn => switch (this) {
    InventorySortOption.priceAsc || InventorySortOption.priceDesc => 'price_est',
    InventorySortOption.relevance ||
    InventorySortOption.newest ||
    InventorySortOption.oldest => 'created_at',
  };

  bool get ascending => switch (this) {
    InventorySortOption.oldest || InventorySortOption.priceAsc => true,
    InventorySortOption.relevance ||
    InventorySortOption.newest ||
    InventorySortOption.priceDesc => false,
  };

  static InventorySortOption fromColumnAndDirection({
    required String sortColumn,
    required bool ascending,
  }) {
    if (sortColumn == 'price_est') {
      return ascending
          ? InventorySortOption.priceAsc
          : InventorySortOption.priceDesc;
    }
    return ascending ? InventorySortOption.oldest : InventorySortOption.newest;
  }
}

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

  InventorySearchCriteria copyWith({
    String? category,
    String? gender,
    String? location,
    String? size,
    String? brand,
    String? color,
    String? pattern,
    String? name,
    String? condition,
    String? text,
    bool? onlyUnsold,
    bool? fallback,
    String? sortColumn,
    bool? ascending,
    int? pageSize,
    int? maxResults,
    bool clearMaxResults = false,
  }) {
    return InventorySearchCriteria(
      category: category ?? this.category,
      gender: gender ?? this.gender,
      location: location ?? this.location,
      size: size ?? this.size,
      brand: brand ?? this.brand,
      color: color ?? this.color,
      pattern: pattern ?? this.pattern,
      name: name ?? this.name,
      condition: condition ?? this.condition,
      text: text ?? this.text,
      onlyUnsold: onlyUnsold ?? this.onlyUnsold,
      fallback: fallback ?? this.fallback,
      sortColumn: sortColumn ?? this.sortColumn,
      ascending: ascending ?? this.ascending,
      pageSize: pageSize ?? this.pageSize,
      maxResults: clearMaxResults ? null : (maxResults ?? this.maxResults),
    );
  }
}

/// Builds and pages the inventory query so filters and sorting behave the same everywhere.
class InventorySearch {
  InventorySearch._();

  static const columns =
      'id, name, brand, price_est, category, gender, location, size, color, pattern, condition, image_url, is_sold, created_at';

  static const sortableColumns = {'created_at', 'price_est'};

  static const storeLocations = ['Csengery', 'Astoria'];
  static const locationFilterOptions = ['All locations', ...storeLocations];
  static const genderFilterOptions = ['Minden', ...genderOptions];

  static const _categoryAliases = <String, String>{
    'poló': 'Póló',
    'polo': 'Póló',
    'melegítő nadrág': 'melegítő',
    'melegito nadrag': 'melegítő',
    'nyakkendő': 'other',
    'nyakkendo': 'other',
  };

  /// Normalizes a category label (e.g. from Gemini output) onto a known
  /// dropdown option so category filters never carry invalid or crashing values.
  static String normalizeCategory(dynamic raw) {
    final trimmed = raw?.toString().trim() ?? '';
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'minden') {
      return 'Minden';
    }
    if (filterCategories.contains(trimmed)) return trimmed;

    final lower = trimmed.toLowerCase();
    final alias = _categoryAliases[lower];
    if (alias != null && filterCategories.contains(alias)) {
      return alias;
    }

    final folded = _foldAccents(lower);
    for (final candidate in filterCategories) {
      if (_foldAccents(candidate.toLowerCase()) == folded) {
        return candidate;
      }
    }
    final foldedAlias = _categoryAliases[folded];
    if (foldedAlias != null && filterCategories.contains(foldedAlias)) {
      return foldedAlias;
    }
    return 'Minden';
  }

  /// Normalizes a gender label onto a known dropdown option.
  static String normalizeGender(dynamic raw) {
    final trimmed = raw?.toString().trim() ?? '';
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'minden') {
      return 'Minden';
    }
    if (genderFilterOptions.contains(trimmed)) return trimmed;

    final folded = _foldAccents(trimmed.toLowerCase());
    for (final candidate in genderFilterOptions) {
      if (_foldAccents(candidate.toLowerCase()) == folded) {
        return candidate;
      }
    }
    return 'Minden';
  }

  /// Normalizes a location label onto a known dropdown option.
  static String normalizeLocation(dynamic raw) {
    final trimmed = raw?.toString().trim() ?? '';
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'all locations') {
      return 'All locations';
    }
    for (final candidate in locationFilterOptions) {
      if (candidate.toLowerCase() == trimmed.toLowerCase()) {
        return candidate;
      }
    }
    return 'All locations';
  }

  static String _foldAccents(String input) {
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ö': 'o',
      'ő': 'o',
      'ú': 'u',
      'ü': 'u',
      'ű': 'u',
    };
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
  }

  /// Parses numeric, formatted string, or null/missing prices consistently as a
  /// finite [double]. Returns `null` when missing or unparseable.
  static double? parsePrice(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final asDouble = value.toDouble();
      return asDouble.isFinite ? asDouble : null;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    // Strip common currency labels and whitespace/non-breaking spaces.
    var cleaned = raw
        .replaceAll(RegExp(r'\b(huf|ft)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s\u00A0\u202F]+'), '');
    if (cleaned.isEmpty) return null;

    // Handle sign and keep only digits, dots, commas, and leading minus.
    final negative = cleaned.startsWith('-');
    if (negative || cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return null;

    final hasDot = cleaned.contains('.');
    final hasComma = cleaned.contains(',');

    String normalized;
    if (hasDot && hasComma) {
      // Whichever separator appears last is the decimal separator.
      final lastDot = cleaned.lastIndexOf('.');
      final lastComma = cleaned.lastIndexOf(',');
      if (lastComma > lastDot) {
        normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = cleaned.replaceAll(',', '');
      }
    } else if (hasComma) {
      final parts = cleaned.split(',');
      final isThousandsGrouping =
          parts.length > 2 ||
          (parts.length == 2 &&
              parts[0].isNotEmpty &&
              parts[0].length <= 3 &&
              parts[1].length == 3);
      normalized = isThousandsGrouping
          ? cleaned.replaceAll(',', '')
          : cleaned.replaceAll(',', '.');
    } else if (hasDot) {
      final parts = cleaned.split('.');
      final isThousandsGrouping =
          parts.length > 2 ||
          (parts.length == 2 &&
              parts[0].isNotEmpty &&
              parts[0].length <= 3 &&
              parts[1].length == 3);
      normalized = isThousandsGrouping ? cleaned.replaceAll('.', '') : cleaned;
    } else {
      normalized = cleaned;
    }

    final parsed = double.tryParse(negative ? '-$normalized' : normalized);
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }

  /// Parses ISO-8601 strings or [DateTime] values into UTC timestamps.
  static DateTime? parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// Parses a similarity score (from vector search) as a finite [double].
  static double? parseSimilarity(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final asDouble = value.toDouble();
      return asDouble.isFinite ? asDouble : null;
    }
    final parsed = double.tryParse(value.toString().trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }

  /// Deduplicates items by non-null `id` (preserving the first occurrence) and
  /// returns a new list strictly sorted according to [sortOption].
  ///
  /// Null/missing sort values are always placed last. Category priority is used
  /// only as a deterministic tie-breaker when primary sort values are equal, so
  /// category grouping can never break price or date ordering.
  static List<Map<String, dynamic>> sortResults(
    Iterable<Map<String, dynamic>> items, {
    required InventorySortOption sortOption,
    String? preferredCategory,
  }) {
    final seenIds = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final item in items) {
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) {
        if (!seenIds.add(id)) continue;
      }
      deduped.add(Map<String, dynamic>.from(item));
    }

    final category = preferredCategory?.trim() ?? '';
    final useCategoryTieBreaker = category.isNotEmpty && category != 'Minden';

    int compareCategoryTieBreaker(
      Map<String, dynamic> a,
      Map<String, dynamic> b,
    ) {
      if (!useCategoryTieBreaker) return 0;
      final aMain = a['category']?.toString() == category ? 0 : 1;
      final bMain = b['category']?.toString() == category ? 0 : 1;
      return aMain.compareTo(bMain);
    }

    int compareNullableDouble(double? a, double? b, {required bool ascending}) {
      if (a == null && b == null) return 0;
      if (a == null) return 1; // nulls last
      if (b == null) return -1;
      return ascending ? a.compareTo(b) : b.compareTo(a);
    }

    int compareNullableDate(
      DateTime? a,
      DateTime? b, {
      required bool ascending,
    }) {
      if (a == null && b == null) return 0;
      if (a == null) return 1; // nulls last
      if (b == null) return -1;
      return ascending ? a.compareTo(b) : b.compareTo(a);
    }

    int compareId(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      return aId.compareTo(bId);
    }

    deduped.sort((a, b) {
      int primary;
      switch (sortOption) {
        case InventorySortOption.priceAsc:
          primary = compareNullableDouble(
            parsePrice(a['price_est']),
            parsePrice(b['price_est']),
            ascending: true,
          );
          if (primary != 0) return primary;
          final cat = compareCategoryTieBreaker(a, b);
          if (cat != 0) return cat;
          final date = compareNullableDate(
            parseTimestamp(a['created_at']),
            parseTimestamp(b['created_at']),
            ascending: false,
          );
          if (date != 0) return date;
          return compareId(a, b);

        case InventorySortOption.priceDesc:
          primary = compareNullableDouble(
            parsePrice(a['price_est']),
            parsePrice(b['price_est']),
            ascending: false,
          );
          if (primary != 0) return primary;
          final cat = compareCategoryTieBreaker(a, b);
          if (cat != 0) return cat;
          final date = compareNullableDate(
            parseTimestamp(a['created_at']),
            parseTimestamp(b['created_at']),
            ascending: false,
          );
          if (date != 0) return date;
          return compareId(a, b);

        case InventorySortOption.newest:
          primary = compareNullableDate(
            parseTimestamp(a['created_at']),
            parseTimestamp(b['created_at']),
            ascending: false,
          );
          if (primary != 0) return primary;
          final cat = compareCategoryTieBreaker(a, b);
          if (cat != 0) return cat;
          return compareId(a, b);

        case InventorySortOption.oldest:
          primary = compareNullableDate(
            parseTimestamp(a['created_at']),
            parseTimestamp(b['created_at']),
            ascending: true,
          );
          if (primary != 0) return primary;
          final cat = compareCategoryTieBreaker(a, b);
          if (cat != 0) return cat;
          return compareId(a, b);

        case InventorySortOption.relevance:
          primary = compareNullableDouble(
            parseSimilarity(a['similarity']),
            parseSimilarity(b['similarity']),
            ascending: false,
          );
          if (primary != 0) return primary;
          final cat = compareCategoryTieBreaker(a, b);
          if (cat != 0) return cat;
          final date = compareNullableDate(
            parseTimestamp(a['created_at']),
            parseTimestamp(b['created_at']),
            ascending: false,
          );
          if (date != 0) return date;
          return compareId(a, b);
      }
    });

    return deduped;
  }

  static String seekFilter({
    required String sortColumn,
    required bool ascending,
    required String? sortValue,
    required String id,
  }) {
    if (!sortableColumns.contains(sortColumn)) {
      throw ArgumentError.value(
        sortColumn,
        'sortColumn',
        'Unsupported sort column',
      );
    }
    if (sortValue == null) return 'and($sortColumn.is.null,id.gt.$id)';
    final operator = ascending ? 'gt' : 'lt';
    return '$sortColumn.$operator.$sortValue,'
        'and($sortColumn.eq.$sortValue,id.gt.$id),$sortColumn.is.null';
  }

  static const _colorFamilies = <List<String>>[
    ['kék', 'kek', 'blue', 'navy', 'tengerészkék', 'azúr', 'türkiz', 'cyan'],
    [
      'pink',
      'rózsaszín',
      'rozsaszin',
      'magenta',
      'magneta',
      'fukszia',
      'fuchsia',
      'ciklámen',
      'ciklamen',
    ],
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
      throw ArgumentError.value(
        criteria.sortColumn,
        'sortColumn',
        'Unsupported sort column',
      );
    }
    final pageSize = criteria.pageSize.clamp(1, 1000).toInt();
    String? cursorSortValue;
    String? cursorId;

    while (true) {
      dynamic query = Supabase.instance.client
          .from('inventory')
          .select(columns);
      if (criteria.onlyUnsold) query = query.eq('is_sold', false);

      final category = criteria.category?.trim() ?? '';
      if (category.isNotEmpty && category != 'Minden') {
        query = query.or(
          'category.eq.$category,secondary_categories.cs.{$category}',
        );
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
          : (criteria.maxResults! - results.length).clamp(1, pageSize).toInt();
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

    // Apply canonical final sort across the entire merged/paginated result set.
    final sortOption = InventorySortOption.fromColumnAndDirection(
      sortColumn: criteria.sortColumn,
      ascending: criteria.ascending,
    );
    return sortResults(
      results,
      sortOption: sortOption,
      preferredCategory: criteria.category,
    );
  }
}
