import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/screens/account_screen.dart';
import 'package:yoaron_app/screens/team_stats_screen.dart';
import 'package:yoaron_app/services/employee_stats_service.dart';
import 'package:yoaron_app/theme/app_theme.dart';

class _FakeStatsGateway implements EmployeeStatsGateway {
  _FakeStatsGateway({
    required this.myStats,
    this.teamStats = const [],
    this.teamError,
  });

  final EmployeeStats myStats;
  final List<EmployeeStats> teamStats;
  final Object? teamError;

  @override
  Future<EmployeeStats> fetchMyStats() async => myStats;

  @override
  Future<List<EmployeeStats>> fetchAllEmployeeStats() async {
    if (teamError != null) throw teamError!;
    return teamStats;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets(
    'AccountScreen displays personal upload and sales stats and hides team stats for staff',
    (tester) async {
      final gateway = _FakeStatsGateway(
        myStats: const EmployeeStats(
          userId: 'u-staff',
          displayName: 'Kiss Anna',
          email: 'anna@yoaron.hu',
          roles: ['staff'],
          uploadedItemsCount: 42,
          salesCount: 10,
          soldItemsCount: 16,
          totalSalesRevenue: 120000,
          activeSalesDays: 4,
          dailyAvgRevenue: 30000,
          dailyAvgSalesCount: 2.5,
          canViewTeamStats: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AccountScreen(statsGateway: gateway),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kiss Anna'), findsOneWidget);
      expect(find.text('Munkatárs'), findsOneWidget);
      expect(find.text('120 000 Ft'), findsOneWidget);
      expect(find.text('30 000 Ft / nap'), findsOneWidget);
      expect(find.text('42 db'), findsOneWidget);
      expect(find.text('Csapat statisztikák'), findsNothing);
    },
  );

  testWidgets(
    'Manager/Admin can open TeamStatsScreen from AccountScreen and sort employee stats',
    (tester) async {
      final gateway = _FakeStatsGateway(
        myStats: const EmployeeStats(
          userId: 'u-manager',
          displayName: 'Nagy Béla',
          email: 'bela@yoaron.hu',
          roles: ['manager'],
          uploadedItemsCount: 18,
          salesCount: 8,
          soldItemsCount: 12,
          totalSalesRevenue: 90000,
          activeSalesDays: 3,
          dailyAvgRevenue: 30000,
          dailyAvgSalesCount: 2.67,
          canViewTeamStats: true,
        ),
        teamStats: const [
          EmployeeStats(
            userId: 'u-anna',
            displayName: 'Kiss Anna',
            email: 'anna@yoaron.hu',
            roles: ['staff'],
            uploadedItemsCount: 55,
            salesCount: 10,
            soldItemsCount: 15,
            totalSalesRevenue: 150000,
            activeSalesDays: 5,
            dailyAvgRevenue: 30000,
            dailyAvgSalesCount: 2,
          ),
          EmployeeStats(
            userId: 'u-bela',
            displayName: 'Nagy Béla',
            email: 'bela@yoaron.hu',
            roles: ['manager'],
            uploadedItemsCount: 18,
            salesCount: 6,
            soldItemsCount: 9,
            totalSalesRevenue: 120000,
            activeSalesDays: 2,
            dailyAvgRevenue: 60000,
            dailyAvgSalesCount: 3,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AccountScreen(statsGateway: gateway),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manager'), findsOneWidget);
      final teamStatsButton = find.text('Csapat statisztikák');
      expect(teamStatsButton, findsOneWidget);

      await tester.ensureVisible(teamStatsButton);
      await tester.tap(teamStatsButton);
      await tester.pumpAndSettle();

      expect(find.byType(TeamStatsScreen), findsOneWidget);
      expect(find.text('270 000 Ft'), findsOneWidget); // Combined revenue
      expect(find.text('73 db'), findsOneWidget); // Combined uploads
      expect(find.text('Kiss Anna'), findsOneWidget);
      expect(find.text('Nagy Béla'), findsOneWidget);
      expect(find.text('60 000 Ft'), findsOneWidget);
      expect(find.text('55 db'), findsOneWidget);

      // Sort by Napi átlag -> Nagy Béla (60 000) moves above Kiss Anna (30 000).
      await tester.tap(find.text('Napi átlag').first);
      await tester.pumpAndSettle();
      final belaY = tester.getTopLeft(find.text('Nagy Béla')).dy;
      final annaY = tester.getTopLeft(find.text('Kiss Anna')).dy;
      expect(belaY, lessThan(annaY));
    },
  );

  testWidgets('TeamStatsScreen displays permission error when unauthorized', (
    tester,
  ) async {
    final gateway = _FakeStatsGateway(
      myStats: const EmployeeStats(
        userId: 'u-staff',
        displayName: 'Staff',
        email: 'staff@yoaron.hu',
        roles: ['staff'],
        uploadedItemsCount: 0,
        salesCount: 0,
        soldItemsCount: 0,
        totalSalesRevenue: 0,
        activeSalesDays: 0,
        dailyAvgRevenue: 0,
        dailyAvgSalesCount: 0,
      ),
      teamError: Exception('Only managers and admins can view team statistics'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TeamStatsScreen(statsGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'A csapat statisztikák csak manager és admin jogosultsággal érhetők el.',
      ),
      findsOneWidget,
    );
  });
}
