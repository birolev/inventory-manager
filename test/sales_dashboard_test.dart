import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/screens/sales_dashboard_screen.dart';
import 'package:yoaron_app/theme/app_theme.dart';

void main() {
  testWidgets(
    'SalesDashboardScreen separates Csengery (Yoáron) and Astoria (BVS) and toggles between them',
    (tester) async {
      final now = DateTime.now();
      final todayIso = DateTime(
        now.year,
        now.month,
        now.day,
        11,
        30,
      ).toUtc().toIso8601String();

      final mockSales = <Map<String, dynamic>>[
        {
          'id': 'sale-csengery',
          'sold_at': todayIso,
          'location': 'Csengery',
          'payment_method': 'cash',
          'notes': '',
          'recorded_by_name': 'Anna',
          'sale_items': [
            {
              'id': 'si-1',
              'item_name': 'Yoáron Hoodie',
              'brand': 'Nike',
              'category': 'hoodie',
              'size': 'M',
              'actual_price': 10000,
            },
          ],
        },
        {
          'id': 'sale-astoria',
          'sold_at': todayIso,
          'location': 'Astoria',
          'payment_method': 'card',
          'notes': '',
          'recorded_by_name': 'Béla',
          'sale_items': [
            {
              'id': 'si-2',
              'item_name': 'BVS Jacket',
              'brand': 'Levi’s',
              'category': 'dzseki',
              'size': 'L',
              'actual_price': 15000,
            },
          ],
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SalesDashboardScreen(
            fetchMonthSales: (start, end) async => mockSales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default 'Összes' shows combined revenue (25 000 Ft) and both store sales.
      expect(find.text('25 000 Ft'), findsOneWidget);
      expect(find.text('2 db'), findsNWidgets(2));
      expect(find.textContaining('Yoáron · Készpénz · Anna'), findsOneWidget);
      expect(find.textContaining('BVS · Kártya · Béla'), findsOneWidget);

      // Toggle to Yoáron (Csengery only -> 10 000 Ft).
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<SalesStoreFilter>),
          matching: find.text('Yoáron'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10 000 Ft'), findsNWidgets(2));
      expect(find.text('1 db'), findsNWidgets(2));
      expect(find.textContaining('Yoáron · Készpénz · Anna'), findsOneWidget);
      expect(find.textContaining('BVS · Kártya · Béla'), findsNothing);

      // Toggle to BVS (Astoria only -> 15 000 Ft).
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<SalesStoreFilter>),
          matching: find.text('BVS'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('15 000 Ft'), findsNWidgets(2));
      expect(find.text('1 db'), findsNWidgets(2));
      expect(find.textContaining('BVS · Kártya · Béla'), findsOneWidget);
      expect(find.textContaining('Yoáron · Készpénz · Anna'), findsNothing);

      // Toggle back to Összes -> 25 000 Ft.
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<SalesStoreFilter>),
          matching: find.text('Összes'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('25 000 Ft'), findsOneWidget);
      expect(find.text('2 db'), findsNWidgets(2));
    },
  );
}
