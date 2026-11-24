import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/invite_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

class YoaronApp extends StatefulWidget {
  const YoaronApp({
    super.key,
    this.openedFromInvite = false,
    this.themeController,
  });

  final bool openedFromInvite;
  final AppThemeController? themeController;

  @override
  State<YoaronApp> createState() => _YoaronAppState();
}

class _YoaronAppState extends State<YoaronApp> {
  late bool _mustChangeInvitePassword = widget.openedFromInvite;

  AppThemeController get _themeController =>
      widget.themeController ?? AppThemeController.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Yoaron Készlet',
          debugShowCheckedModeBanner: false,
          theme: _themeController.lightTheme,
          darkTheme: _themeController.darkTheme,
          themeMode: _themeController.themeMode,
          home: StreamBuilder<AuthState>(
            stream: Supabase.instance.client.auth.onAuthStateChange,
            builder: (context, snapshot) {
              final currentSession =
                  Supabase.instance.client.auth.currentSession;

              if (currentSession != null) {
                if (_mustChangeInvitePassword) {
                  return InvitePasswordScreen(
                    onPasswordChanged: () {
                      if (mounted) {
                        setState(() => _mustChangeInvitePassword = false);
                      }
                    },
                  );
                }
                return const MainShell();
              }
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}
