import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

enum PasswordSetupMode { invite, recovery }

class InvitePasswordScreen extends StatefulWidget {
  const InvitePasswordScreen({
    required this.onPasswordChanged,
    this.mode = PasswordSetupMode.invite,
    this.email,
    super.key,
  });

  final VoidCallback onPasswordChanged;
  final PasswordSetupMode mode;
  final String? email;

  @override
  State<InvitePasswordScreen> createState() => _InvitePasswordScreenState();
}

class _InvitePasswordScreenState extends State<InvitePasswordScreen> {
  late final _emailController = TextEditingController(text: widget.email ?? '');
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSaving = false;
  bool _obscurePassword = true;

  @override
  void didUpdateWidget(covariant InvitePasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.email != oldWidget.email) {
      _emailController.text = widget.email ?? '';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
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
      TextInput.finishAutofillContext();
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
      SnackBar(content: Text(message), backgroundColor: context.palette.brick),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
                          color: p.accentSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.lock_reset,
                          size: 28,
                          color: p.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.mode == PasswordSetupMode.recovery
                          ? 'Új jelszó beállítása'
                          : 'Jelszó beállítása',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.mode == PasswordSetupMode.recovery
                          ? 'Adj meg egy új jelszót a fiókodhoz a folytatáshoz.'
                          : 'Adj meg egy jelszót a meghívott fiókodhoz a folytatáshoz.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.email != null &&
                              widget.email!.trim().isNotEmpty) ...[
                            TextField(
                              controller: _emailController,
                              readOnly: true,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'E-mail cím',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
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
                            onSubmitted: (_) =>
                                _isSaving ? null : _savePassword(),
                            decoration: InputDecoration(
                              labelText: 'Új jelszó megerősítése',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: toggleButton,
                            ),
                          ),
                        ],
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
