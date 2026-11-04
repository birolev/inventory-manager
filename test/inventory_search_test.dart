import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/services/inventory_search.dart';

void main() {
  group('InventorySearch.seekFilter', () {
    test('advances timestamp pages in ascending order with an ID tie-breaker', () {
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
    });

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
}
