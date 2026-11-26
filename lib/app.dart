import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/invite_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

class YoaronApp extends StatefulWidget {
  const YoaronApp({
    super.key,
    this.initialPasswordSetupMode,
    this.themeController,
  });

  final PasswordSetupMode? initialPasswordSetupMode;
  final AppThemeController? themeController;

  @override
  State<YoaronApp> createState() => _YoaronAppState();
}

class _YoaronAppState extends State<YoaronApp> {
  late Session? _currentSession = Supabase.instance.client.auth.currentSession;
  late PasswordSetupMode? _pendingPasswordSetupMode =
      widget.initialPasswordSetupMode;
  StreamSubscription<AuthState>? _authSubscription;

  AppThemeController get _themeController =>
      widget.themeController ?? AppThemeController.instance;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      authState,
    ) {
      if (!mounted) return;
      setState(() {
        _currentSession = authState.session;
        if (authState.event == AuthChangeEvent.passwordRecovery) {
          _pendingPasswordSetupMode = PasswordSetupMode.recovery;
        } else if (authState.event == AuthChangeEvent.signedOut) {
          _pendingPasswordSetupMode = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        final home = switch ((_currentSession, _pendingPasswordSetupMode)) {
          (null, _) => const LoginScreen(),
          (_, final PasswordSetupMode mode) => InvitePasswordScreen(
            mode: mode,
            onPasswordChanged: () {
              if (mounted) {
                setState(() => _pendingPasswordSetupMode = null);
              }
            },
          ),
          _ => const MainShell(),
        };

        return MaterialApp(
          title: 'Yoaron Készlet',
          debugShowCheckedModeBanner: false,
          theme: _themeController.lightTheme,
          darkTheme: _themeController.darkTheme,
          themeMode: _themeController.themeMode,
          home: home,
        );
      },
    );
  }
}
