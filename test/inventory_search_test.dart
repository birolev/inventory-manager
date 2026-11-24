import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/services/inventory_search.dart';

void main() {
  group('InventorySearch.seekFilter', () {
    test(
      'advances timestamp pages in ascending order with an ID tie-breaker',
      () {
        expect(
          InventorySearch.seekFilter(
            sortColumn: 'created_at',
            ascending: true,
            sortValue: '2026-11-04T12:30:00.000Z',
            id: '00000000-0000-0000-0000-000000000001',
          ),
          'created_at.gt.2026-11-04T12:30:00.000Z,'
          'and(created_at.eq.2026-11-04T12:30:00.000Z,id.gt.00000000-0000-0000-0000-000000000001),'
          'created_at.is.null',
        );
      },
    );

    test('advances price pages in descending order and handles nulls', () {
      expect(
        InventorySearch.seekFilter(
          sortColumn: 'price_est',
          ascending: false,
          sortValue: '1250.0',
          id: '42',
        ),
        'price_est.lt.1250.0,and(price_est.eq.1250.0,id.gt.42),price_est.is.null',
      );
      expect(
        InventorySearch.seekFilter(
          sortColumn: 'price_est',
          ascending: true,
          sortValue: null,
          id: '42',
        ),
        'and(price_est.is.null,id.gt.42)',
      );
    });

    test('rejects unsupported sort columns', () {
      expect(
        () => InventorySearch.seekFilter(
          sortColumn: 'name);delete from inventory;--',
          ascending: true,
          sortValue: 'x',
          id: '1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('InventorySearch.parsePrice', () {
    test('parses numeric, formatted string, and missing prices', () {
      expect(InventorySearch.parsePrice(3000), 3000.0);
      expect(InventorySearch.parsePrice(30000.5), 30000.5);
      expect(InventorySearch.parsePrice('3000'), 3000.0);
      expect(InventorySearch.parsePrice('30 000 Ft'), 30000.0);
      expect(InventorySearch.parsePrice('30,000 HUF'), 30000.0);
      expect(InventorySearch.parsePrice('30.000'), 30000.0);
      expect(InventorySearch.parsePrice('1250.50'), 1250.5);
      expect(InventorySearch.parsePrice('1250,50'), 1250.5);
      expect(InventorySearch.parsePrice('1,250.50'), 1250.5);
      expect(InventorySearch.parsePrice('1.250,50'), 1250.5);
      expect(InventorySearch.parsePrice(null), isNull);
      expect(InventorySearch.parsePrice(''), isNull);
      expect(InventorySearch.parsePrice('unknown'), isNull);
      expect(InventorySearch.parsePrice(double.nan), isNull);
      expect(InventorySearch.parsePrice(double.infinity), isNull);
    });
  });

  group('InventorySearch.sortResults', () {
    test('sorts mixed numeric, string, and null prices strictly ascending', () {
      final items = <Map<String, dynamic>>[
        {'id': 'a', 'price_est': '30 000 Ft', 'category': 'hoodie'},
        {'id': 'b', 'price_est': '3000', 'category': 'hoodie'},
        {'id': 'c', 'price_est': null, 'category': 'hoodie'},
        {'id': 'd', 'price_est': 2500, 'category': 'zipup'},
        {'id': 'e', 'price_est': '10,000', 'category': 'hoodie'},
        {'id': 'f', 'price_est': '3,500 HUF', 'category': 'zipup'},
        {'id': 'g', 'price_est': '', 'category': 'hoodie'},
        {'id': 'h', 'price_est': 900, 'category': 'hoodie'},
      ];

      final sorted = InventorySearch.sortResults(
        items,
        sortOption: InventorySortOption.priceAsc,
        preferredCategory: 'hoodie',
      );

      expect(sorted.map((item) => item['id']).toList(), [
        'h', // 900
        'd', // 2500 (secondary category MUST NOT be pushed after 30,000!)
        'b', // 3000
        'f', // 3500
        'e', // 10000
        'a', // 30000
        'c', // null -> last
        'g', // empty -> last
      ]);
    });

    test('sorts mixed prices strictly descending with nulls last', () {
      final items = <Map<String, dynamic>>[
        {'id': 'a', 'price_est': '3000'},
        {'id': 'b', 'price_est': '30,000 Ft'},
        {'id': 'c', 'price_est': null},
        {'id': 'd', 'price_est': 9000},
        {'id': 'e', 'price_est': '500'},
        {'id': 'f', 'price_est': 12500.5},
      ];

      final sorted = InventorySearch.sortResults(
        items,
        sortOption: InventorySortOption.priceDesc,
      );

      expect(sorted.map((item) => item['id']).toList(), [
        'b', // 30000
        'f', // 12500.5
        'd', // 9000
        'a', // 3000
        'e', // 500
        'c', // null last
      ]);
    });

    test(
      'keeps strict numeric price ordering across large (>100) mixed-category sets',
      () {
        final random = Random(42);
        final items = List.generate(150, (index) {
          final isPrimary = index % 3 != 0;
          final price = index % 17 == 0
              ? null
              : index % 5 == 0
              ? '${(random.nextInt(40) + 1) * 1000} Ft'
              : (random.nextInt(40) + 1) * 1000;
          return <String, dynamic>{
            'id': 'item-${index.toString().padLeft(3, '0')}',
            'category': isPrimary ? 'hoodie' : 'zipup',
            'price_est': price,
            'created_at': DateTime.utc(2026, 1, 1)
                .add(Duration(minutes: index))
                .toIso8601String(),
          };
        });

        final asc = InventorySearch.sortResults(
          items,
          sortOption: InventorySortOption.priceAsc,
          preferredCategory: 'hoodie',
        );
        expect(asc.length, 150);
        double? prevAsc;
        var seenNull = false;
        for (final item in asc) {
          final price = InventorySearch.parsePrice(item['price_est']);
          if (price == null) {
            seenNull = true;
          } else {
            expect(seenNull, isFalse, reason: 'Null prices must be last');
            if (prevAsc != null) {
              expect(price, greaterThanOrEqualTo(prevAsc));
            }
            prevAsc = price;
          }
        }

        final desc = InventorySearch.sortResults(
          items,
          sortOption: InventorySortOption.priceDesc,
          preferredCategory: 'hoodie',
        );
        expect(desc.length, 150);
        double? prevDesc;
        seenNull = false;
        for (final item in desc) {
          final price = InventorySearch.parsePrice(item['price_est']);
          if (price == null) {
            seenNull = true;
          } else {
            expect(seenNull, isFalse, reason: 'Null prices must be last');
            if (prevDesc != null) {
              expect(price, lessThanOrEqualTo(prevDesc));
            }
            prevDesc = price;
          }
        }
      },
    );

    test('deduplicates merged items by id before sorting', () {
      final merged = <Map<String, dynamic>>[
        {'id': '1', 'price_est': 5000},
        {'id': '2', 'price_est': 2000},
        {'id': '1', 'price_est': 5000},
      ];

      final sorted = InventorySearch.sortResults(
        merged,
        sortOption: InventorySortOption.priceAsc,
      );
      expect(sorted.length, 2);
      expect(sorted.map((e) => e['id']).toList(), ['2', '1']);
    });

    test('sorts by newest, oldest, and similarity relevance cleanly', () {
      final items = <Map<String, dynamic>>[
        {
          'id': 'old',
          'created_at': '2026-01-01T10:00:00Z',
          'similarity': 0.72,
        },
        {
          'id': 'mid',
          'created_at': '2026-06-01T10:00:00Z',
          'similarity': 0.95,
        },
        {
          'id': 'new',
          'created_at': '2026-11-01T10:00:00Z',
          'similarity': 0.81,
        },
        {'id': 'nodate', 'created_at': null, 'similarity': null},
      ];

      expect(
        InventorySearch.sortResults(
          items,
          sortOption: InventorySortOption.newest,
        ).map((e) => e['id']).toList(),
        ['new', 'mid', 'old', 'nodate'],
      );
      expect(
        InventorySearch.sortResults(
          items,
          sortOption: InventorySortOption.oldest,
        ).map((e) => e['id']).toList(),
        ['old', 'mid', 'new', 'nodate'],
      );
      expect(
        InventorySearch.sortResults(
          items,
          sortOption: InventorySortOption.relevance,
        ).map((e) => e['id']).toList(),
        ['mid', 'new', 'old', 'nodate'],
      );
    });
  });

  group('InventorySearch normalization', () {
    test('normalizes AI category and gender labels onto valid options', () {
      expect(InventorySearch.normalizeCategory('Poló'), 'Póló');
      expect(InventorySearch.normalizeCategory('melegítő nadrág'), 'melegítő');
      expect(InventorySearch.normalizeCategory('nyakkendő'), 'other');
      expect(InventorySearch.normalizeCategory('unknown_cat'), 'Minden');
      expect(InventorySearch.normalizeGender('ferfi'), 'férfi');
      expect(InventorySearch.normalizeGender('NŐI'), 'női');
      expect(InventorySearch.normalizeGender('invalid'), 'Minden');
    });
  });
}
