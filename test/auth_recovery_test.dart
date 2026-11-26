import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/main.dart';
import 'package:yoaron_app/screens/invite_password_screen.dart';
import 'package:yoaron_app/screens/login_screen.dart';
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

    testWidgets('shows recovery copy and read-only email for autofill', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: InvitePasswordScreen(
            mode: PasswordSetupMode.recovery,
            email: 'staff@yoaron.hu',
            onPasswordChanged: () {},
          ),
        ),
      );

      expect(find.text('Új jelszó beállítása'), findsOneWidget);
      expect(
        find.text('Adj meg egy új jelszót a fiókodhoz a folytatáshoz.'),
        findsOneWidget,
      );
      expect(find.byType(AutofillGroup), findsOneWidget);

      final textFields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(textFields, hasLength(3));
      expect(textFields[0].readOnly, isTrue);
      expect(textFields[0].controller?.text, 'staff@yoaron.hu');
      expect(
        textFields[0].autofillHints,
        containsAll([AutofillHints.username, AutofillHints.email]),
      );
      expect(textFields[1].autofillHints, contains(AutofillHints.newPassword));
      expect(textFields[2].autofillHints, contains(AutofillHints.newPassword));
    });
  });

  group('LoginScreen autofill', () {
    testWidgets('wraps email and password fields in AutofillGroup', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      );

      expect(find.byType(AutofillGroup), findsOneWidget);
      final textFields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(textFields, hasLength(2));
      expect(
        textFields[0].autofillHints,
        containsAll([AutofillHints.username, AutofillHints.email]),
      );
      expect(textFields[1].autofillHints, contains(AutofillHints.password));
    });
  });
}
