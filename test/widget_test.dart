import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/app.dart';
import 'package:yoaron_app/screens/account_screen.dart';
import 'package:yoaron_app/screens/main_shell.dart';
import 'package:yoaron_app/services/employee_stats_service.dart';
import 'package:yoaron_app/theme/app_theme.dart';

class _StubStatsGateway implements EmployeeStatsGateway {
  @override
  Future<EmployeeStats> fetchMyStats() async => const EmployeeStats(
    userId: 'test-user',
    displayName: 'Teszt Felhasználó',
    email: 'test@example.com',
    roles: ['staff'],
    uploadedItemsCount: 3,
    salesCount: 2,
    soldItemsCount: 4,
    totalSalesRevenue: 20000,
    activeSalesDays: 2,
    dailyAvgRevenue: 10000,
    dailyAvgSalesCount: 1,
  );

  @override
  Future<List<EmployeeStats>> fetchAllEmployeeStats() async => const [];
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets('shows the sign-in screen when there is no session', (
    tester,
  ) async {
    await tester.pumpWidget(const YoaronApp());

    expect(find.text('Yoaron Készlet'), findsOneWidget);
    expect(find.text('Bejelentkezés'), findsOneWidget);
  });

  testWidgets(
    'MainShell shows 4-tab NavigationBar on mobile and NavigationRail on wide screens',
    (tester) async {
      // Mobile viewport -> bottom NavigationBar
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const MainShell()),
      );
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Eladás'), findsOneWidget);
      expect(find.text('Készlet'), findsOneWidget);
      expect(find.text('Felvétel'), findsOneWidget);
      expect(find.text('Napló'), findsOneWidget);

      // Wide viewport -> NavigationRail
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Fiók'), findsOneWidget);
    },
  );

  testWidgets('AccountScreen shows personal stats and sign-out action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AccountScreen(statsGateway: _StubStatsGateway()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fiók'), findsOneWidget);
    expect(find.text('Saját statisztikák'), findsOneWidget);
    expect(find.text('Eladások összesen'), findsOneWidget);
    expect(find.text('Napi átlagos eladás'), findsOneWidget);
    expect(find.text('Feltöltött termékek'), findsOneWidget);
    expect(find.text('Google értékelések'), findsOneWidget);
    expect(find.text('Kijelentkezés'), findsOneWidget);
  });
}
