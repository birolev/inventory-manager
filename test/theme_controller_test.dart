import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/screens/account_screen.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppThemeController persists theme mode and color preset', () async {
    final controller = AppThemeController();
    expect(controller.themeMode, ThemeMode.light);
    expect(controller.preset, AppColorSchemePreset.atelier);

    await controller.setThemeMode(ThemeMode.dark);
    await controller.setPreset(AppColorSchemePreset.studio);

    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.preset, AppColorSchemePreset.studio);

    final reloaded = AppThemeController();
    await reloaded.load();
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.preset, AppColorSchemePreset.studio);
  });

  testWidgets(
    'AccountScreen toggles dark mode and switches color scheme previews',
    (tester) async {
      final controller = AppThemeController();

      await tester.pumpWidget(
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => MaterialApp(
            theme: controller.lightTheme,
            darkTheme: controller.darkTheme,
            themeMode: controller.themeMode,
            home: AccountScreen(
              statsGateway: _StubStatsGateway(),
              themeController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Megjelenés'), findsOneWidget);
      expect(find.text('Világos'), findsOneWidget);
      expect(find.text('Sötét'), findsOneWidget);
      expect(find.text('Rendszer'), findsOneWidget);
      expect(find.text('Atelier'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('Indigo'), findsOneWidget);

      await tester.ensureVisible(find.text('Sötét'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sötét'));
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.dark);

      final darkScaffoldContext = tester.element(find.byType(AccountScreen));
      expect(Theme.of(darkScaffoldContext).brightness, Brightness.dark);

      await tester.ensureVisible(find.text('Indigo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Indigo'));
      await tester.pumpAndSettle();
      expect(controller.preset, AppColorSchemePreset.indigo);

      final indigoContext = tester.element(find.byType(AccountScreen));
      expect(
        indigoContext.palette.accent,
        AppColorSchemePreset.indigo.paletteFor(Brightness.dark).accent,
      );
    },
  );
}
