import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/main.dart';
import 'package:yoaron_app/screens/invite_password_screen.dart';
import 'package:yoaron_app/theme/app_theme.dart';

void main() {
  group('passwordSetupModeFromUri', () {
    test('detects invite from query parameters and implicit fragment', () {
      expect(
        passwordSetupModeFromUri(
          Uri.parse('https://example.com/?type=invite'),
        ),
        PasswordSetupMode.invite,
      );
      expect(
        passwordSetupModeFromUri(
          Uri.parse(
            'https://example.com/#access_token=abc&refresh_token=def&type=invite',
          ),
        ),
        PasswordSetupMode.invite,
      );
    });

    test('detects recovery from query parameters and implicit fragment', () {
      expect(
        passwordSetupModeFromUri(
          Uri.parse('https://example.com/?type=recovery'),
        ),
        PasswordSetupMode.recovery,
      );
      expect(
        passwordSetupModeFromUri(
          Uri.parse(
            'https://example.com/#access_token=abc&refresh_token=def&type=recovery',
          ),
        ),
        PasswordSetupMode.recovery,
      );
      expect(
        passwordSetupModeFromUri(
          Uri.parse('https://example.com/#/callback?type=RECOVERY'),
        ),
        PasswordSetupMode.recovery,
      );
    });

    test('returns null for non-password-setup URIs', () {
      expect(
        passwordSetupModeFromUri(Uri.parse('https://example.com/')),
        isNull,
      );
      expect(
        passwordSetupModeFromUri(
          Uri.parse('https://example.com/#access_token=abc&type=magiclink'),
        ),
        isNull,
      );
    });
  });

  group('InvitePasswordScreen', () {
    testWidgets('shows invite copy by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: InvitePasswordScreen(onPasswordChanged: () {}),
        ),
      );

      expect(find.text('Jelszó beállítása'), findsOneWidget);
      expect(
        find.text('Adj meg egy jelszót a meghívott fiókodhoz a folytatáshoz.'),
        findsOneWidget,
      );
    });

    testWidgets('shows recovery copy when in recovery mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: InvitePasswordScreen(
            mode: PasswordSetupMode.recovery,
            onPasswordChanged: () {},
          ),
        ),
      );

      expect(find.text('Új jelszó beállítása'), findsOneWidget);
      expect(
        find.text('Adj meg egy új jelszót a fiókodhoz a folytatáshoz.'),
        findsOneWidget,
      );
    });
  });
}
