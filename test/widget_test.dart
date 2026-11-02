import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/app.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('shows the sign-in screen when there is no session', (
    tester,
  ) async {
    await tester.pumpWidget(const YoaronApp());

    expect(find.text('Yoaron Inventory'), findsOneWidget);
    expect(find.text('Bejelentkezés'), findsOneWidget);
  });
}
