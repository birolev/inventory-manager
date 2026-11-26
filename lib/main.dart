import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'screens/invite_password_screen.dart';
import 'theme/app_theme.dart';

const _authDiagnosticsEnabled = bool.fromEnvironment(
  'AUTH_DIAGNOSTICS',
  defaultValue: false,
);

PasswordSetupMode? _parsePasswordSetupType(String? rawType) {
  return switch (rawType?.toLowerCase()) {
    'invite' => PasswordSetupMode.invite,
    'recovery' => PasswordSetupMode.recovery,
    _ => null,
  };
}

PasswordSetupMode? passwordSetupModeFromUri(Uri uri) {
  final queryMode = _parsePasswordSetupType(uri.queryParameters['type']);
  if (queryMode != null) return queryMode;

  // Supabase's implicit auth flow returns the auth parameters in the fragment.
  final fragment = uri.fragment;
  if (fragment.isEmpty) return null;
  try {
    final queryPart = fragment.contains('?')
        ? fragment.substring(fragment.indexOf('?') + 1)
        : fragment;
    final parameters = Uri.splitQueryString(queryPart);
    return _parsePasswordSetupType(parameters['type']);
  } on FormatException {
    return null;
  }
}

Set<String> _fragmentParameterNames(Uri uri) {
  if (uri.fragment.isEmpty) return const {};
  try {
    final queryPart = uri.fragment.contains('?')
        ? uri.fragment.substring(uri.fragment.indexOf('?') + 1)
        : uri.fragment;
    return Uri.splitQueryString(queryPart).keys.toSet();
  } on FormatException {
    return const {};
  }
}

void _logAuthCallback(Uri uri, {required String phase, bool? hasSession}) {
  if (!_authDiagnosticsEnabled) return;

  final fragmentParameterNames = _fragmentParameterNames(uri);
  final parameterNames = {
    ...uri.queryParameters.keys,
    ...fragmentParameterNames,
  };
  final setupMode = passwordSetupModeFromUri(uri);
  final diagnostics = [
    'phase=$phase',
    'setupMode=${setupMode?.name ?? 'none'}',
    'hasCode=${parameterNames.contains('code')}',
    'hasToken=${parameterNames.contains('token') || parameterNames.contains('token_hash')}',
    'hasAccessToken=${parameterNames.contains('access_token')}',
    'hasRefreshToken=${parameterNames.contains('refresh_token')}',
    if (hasSession != null) 'hasSession=$hasSession',
  ].join(', ');
  debugPrint('Auth callback diagnostics: $diagnostics');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dot-prefixed assets can be omitted by static hosts such as Netlify.
  // Keep the web runtime config in a regular-named bundled asset.
  await dotenv.load(fileName: 'supabase.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabaseAnonKey == null ||
      supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY in bundled supabase.env.',
    );
  }

  final callbackUri = Uri.base;
  final initialPasswordSetupMode = passwordSetupModeFromUri(callbackUri);
  _logAuthCallback(callbackUri, phase: 'beforeInitialize');
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  _logAuthCallback(
    callbackUri,
    phase: 'afterInitialize',
    hasSession: Supabase.instance.client.auth.currentSession != null,
  );
  if (_authDiagnosticsEnabled) {
    Supabase.instance.client.auth.onAuthStateChange.listen((authState) {
      debugPrint(
        'Auth event: ${authState.event.name}, '
        'hasSession=${authState.session != null}',
      );
    });
  }

  await AppThemeController.instance.load();
  runApp(YoaronApp(initialPasswordSetupMode: initialPasswordSetupMode));
}
