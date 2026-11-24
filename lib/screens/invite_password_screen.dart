import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class InvitePasswordScreen extends StatefulWidget {
  const InvitePasswordScreen({required this.onPasswordChanged, super.key});

  final VoidCallback onPasswordChanged;

  @override
  State<InvitePasswordScreen> createState() => _InvitePasswordScreenState();
}

class _InvitePasswordScreenState extends State<InvitePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSaving = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final password = _passwordController.text;
    if (password.length < 8) {
      _showMessage('A jelszónak legalább 8 karakter hosszúnak kell lennie.');
      return;
    }
    if (password != _confirmationController.text) {
      _showMessage('A két jelszó nem egyezik.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) widget.onPasswordChanged();
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('Nem sikerült frissíteni a jelszót: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.brick),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toggleButton = IconButton(
      tooltip: _obscurePassword ? 'Jelszó megjelenítése' : 'Jelszó elrejtése',
      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      icon: Icon(
        _obscurePassword
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
      ),
    );

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.terracottaSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_reset,
                          size: 28,
                          color: AppColors.terracotta,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Jelszó beállítása',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Adj meg egy jelszót a meghívott fiókodhoz a folytatáshoz.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Új jelszó',
                        helperText: 'Legalább 8 karakter',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: toggleButton,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmationController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _isSaving ? null : _savePassword(),
                      decoration: InputDecoration(
                        labelText: 'Új jelszó megerősítése',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: toggleButton,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSaving ? null : _savePassword,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Jelszó mentése és belépés'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
