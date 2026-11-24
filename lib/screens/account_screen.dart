import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isSigningOut = false;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kijelentkezés'),
        content: const Text('Biztosan ki szeretnél jelentkezni a fiókodból?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brick),
            child: const Text('Kijelentkezés'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSigningOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sikertelen kijelentkezés: $error'),
          backgroundColor: AppColors.brick,
        ),
      );
    }
  }

  String _initialsFor(String displayName, String email) {
    final source = displayName.isNotEmpty ? displayName : email;
    final parts = source
        .trim()
        .split(RegExp(r'[\s._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Y';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Ismeretlen fiók';
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final fullName = (metadata['full_name'] ?? metadata['name'] ?? '')
        .toString()
        .trim();
    final displayName = fullName.isNotEmpty
        ? fullName
        : email.contains('@')
        ? email.split('@').first
        : email;
    final initials = _initialsFor(fullName, email);

    return Scaffold(
      appBar: AppBar(title: const Text('Fiók')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.terracottaSoft,
                          foregroundColor: AppColors.terracotta,
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.inkMuted),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.oliveSoft,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Aktív munkamenet',
                                  style: TextStyle(
                                    color: AppColors.olive,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Saját statisztikák',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Hamarosan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Itt fogod látni a saját eladásaidat, feltöltött termékeidet és az elért Google értékeléseket.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const _UpcomingStatTile(
                  icon: Icons.point_of_sale_outlined,
                  title: 'Rögzített eladások',
                  subtitle: 'Saját eladások száma és havi forgalom',
                ),
                const SizedBox(height: 10),
                const _UpcomingStatTile(
                  icon: Icons.checkroom_outlined,
                  title: 'Feltöltött termékek',
                  subtitle: 'Készletbe felvett darabok száma',
                ),
                const SizedBox(height: 10),
                const _UpcomingStatTile(
                  icon: Icons.star_outline_rounded,
                  title: 'Google értékelések',
                  subtitle: 'Ügyfelektől kapott értékelések nyomon követése',
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _isSigningOut ? null : _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brick,
                    side: const BorderSide(color: AppColors.brick),
                  ),
                  icon: _isSigningOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout),
                  label: Text(
                    _isSigningOut ? 'Kijelentkezés…' : 'Kijelentkezés',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingStatTile extends StatelessWidget {
  const _UpcomingStatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.inkMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Text(
              '—',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
