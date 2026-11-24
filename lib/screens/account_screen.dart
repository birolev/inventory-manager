import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/employee_stats_service.dart';
import '../theme/app_theme.dart';
import 'team_stats_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    this.statsGateway = const SupabaseEmployeeStatsGateway(),
  });

  final EmployeeStatsGateway statsGateway;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isSigningOut = false;
  bool _isLoadingStats = true;
  EmployeeStats? _stats;
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoadingStats = true;
      _statsError = null;
    });
    try {
      final stats = await widget.statsGateway.fetchMyStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _isLoadingStats = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statsError = error.toString();
        _isLoadingStats = false;
      });
    }
  }

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

  void _openTeamStats() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamStatsScreen(statsGateway: widget.statsGateway),
      ),
    );
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
    final email = _stats?.email.isNotEmpty == true
        ? _stats!.email
        : (user?.email ?? 'Ismeretlen fiók');
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final metaName =
        (metadata['display_name'] ??
                metadata['full_name'] ??
                metadata['name'] ??
                '')
            .toString()
            .trim();
    final displayName = _stats?.displayName.isNotEmpty == true
        ? _stats!.displayName
        : metaName.isNotEmpty
        ? metaName
        : email.contains('@')
        ? email.split('@').first
        : email;
    final initials = _initialsFor(displayName, email);
    final stats = _stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiók'),
        actions: [
          IconButton(
            tooltip: 'Statisztikák frissítése',
            onPressed: _isLoadingStats ? null : _loadStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: Center(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                                  child: Text(
                                    stats?.primaryRoleLabel ??
                                        'Aktív munkamenet',
                                    style: const TextStyle(
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
                      if (_isLoadingStats)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_statsError != null && stats == null)
                    Card(
                      color: AppColors.brickSoft,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.brick,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Nem sikerült betölteni a statisztikákat.',
                                style: TextStyle(color: AppColors.brick),
                              ),
                            ),
                            TextButton(
                              onPressed: _loadStats,
                              child: const Text('Újra'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    _StatRowTile(
                      icon: Icons.point_of_sale_outlined,
                      accentColor: AppColors.olive,
                      tintColor: AppColors.oliveSoft,
                      title: 'Eladások összesen',
                      subtitle: stats == null
                          ? 'Betöltés…'
                          : '${stats.salesCount} eladás · ${stats.soldItemsCount} termék',
                      value: stats == null
                          ? '—'
                          : AppFormat.forint(stats.totalSalesRevenue),
                    ),
                    const SizedBox(height: 10),
                    _StatRowTile(
                      icon: Icons.trending_up_rounded,
                      accentColor: AppColors.terracotta,
                      tintColor: AppColors.terracottaSoft,
                      title: 'Napi átlagos eladás',
                      subtitle: stats == null
                          ? 'Betöltés…'
                          : '${stats.activeSalesDays} aktív nap · ${AppFormat.amount(stats.dailyAvgSalesCount)} eladás/nap',
                      value: stats == null
                          ? '—'
                          : '${AppFormat.forint(stats.dailyAvgRevenue)} / nap',
                    ),
                    const SizedBox(height: 10),
                    _StatRowTile(
                      icon: Icons.checkroom_outlined,
                      accentColor: AppColors.ink,
                      tintColor: AppColors.surfaceMuted,
                      title: 'Feltöltött termékek',
                      subtitle: 'Általad a készletbe felvett darabok',
                      value: stats == null
                          ? '—'
                          : '${stats.uploadedItemsCount} db',
                    ),
                    const SizedBox(height: 10),
                    const _StatRowTile(
                      icon: Icons.star_outline_rounded,
                      accentColor: AppColors.inkMuted,
                      tintColor: AppColors.surfaceMuted,
                      title: 'Google értékelések',
                      subtitle: 'Hamarosan elérhető',
                      value: '—',
                    ),
                  ],
                  if (stats?.canViewTeamStats == true) ...[
                    const SizedBox(height: 20),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      color: AppColors.terracottaSoft,
                      child: InkWell(
                        onTap: _openTeamStats,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.groups_outlined,
                                  color: AppColors.terracotta,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Csapat statisztikák',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(color: AppColors.ink),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Minden munkatárs eladásai, napi átlaga és feltöltései',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.terracotta,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
      ),
    );
  }
}

class _StatRowTile extends StatelessWidget {
  const _StatRowTile({
    required this.icon,
    required this.accentColor,
    required this.tintColor,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final Color accentColor;
  final Color tintColor;
  final String title;
  final String subtitle;
  final String value;

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
                color: tintColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor),
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
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
