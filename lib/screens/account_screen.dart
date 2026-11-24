import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/employee_stats_service.dart';
import '../theme/app_theme.dart';
import 'team_stats_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    this.statsGateway = const SupabaseEmployeeStatsGateway(),
    this.themeController,
  });

  final EmployeeStatsGateway statsGateway;
  final AppThemeController? themeController;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isSigningOut = false;
  bool _isLoadingStats = true;
  EmployeeStats? _stats;
  String? _statsError;

  AppThemeController get _themeController =>
      widget.themeController ?? AppThemeController.instance;

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
    final p = context.palette;
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
            style: FilledButton.styleFrom(
              backgroundColor: p.brick,
              foregroundColor: Colors.white,
            ),
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
          backgroundColor: context.palette.brick,
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
    final p = context.palette;
    final brightness = Theme.of(context).brightness;
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
                            backgroundColor: p.accentSoft,
                            foregroundColor: p.accent,
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
                                      ?.copyWith(color: p.inkMuted),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.oliveSoft,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    stats?.primaryRoleLabel ??
                                        'Aktív munkamenet',
                                    style: TextStyle(
                                      color: p.olive,
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
                      color: p.brickSoft,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: p.brick),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Nem sikerült betölteni a statisztikákat.',
                                style: TextStyle(color: p.brick),
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
                      accentColor: p.olive,
                      tintColor: p.oliveSoft,
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
                      accentColor: p.accent,
                      tintColor: p.accentSoft,
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
                      accentColor: p.ink,
                      tintColor: p.surfaceMuted,
                      title: 'Feltöltött termékek',
                      subtitle: 'Általad a készletbe felvett darabok',
                      value: stats == null
                          ? '—'
                          : '${stats.uploadedItemsCount} db',
                    ),
                    const SizedBox(height: 10),
                    _StatRowTile(
                      icon: Icons.star_outline_rounded,
                      accentColor: p.inkMuted,
                      tintColor: p.surfaceMuted,
                      title: 'Google értékelések',
                      subtitle: 'Hamarosan elérhető',
                      value: '—',
                    ),
                  ],
                  if (stats?.canViewTeamStats == true) ...[
                    const SizedBox(height: 20),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      color: p.accentSoft,
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
                                  color: p.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.groups_outlined,
                                  color: p.accent,
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
                                          ?.copyWith(color: p.ink),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Minden munkatárs eladásai, napi átlaga és feltöltései',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: p.accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Megjelenés',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: _themeController,
                    builder: (context, _) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Sötét mód',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<ThemeMode>(
                                showSelectedIcon: false,
                                style: SegmentedButton.styleFrom(
                                  backgroundColor: p.surface,
                                  selectedBackgroundColor: p.accentSoft,
                                  selectedForegroundColor: p.accent,
                                  foregroundColor: p.inkMuted,
                                  side: BorderSide(color: p.border),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text('Világos'),
                                    icon: Icon(
                                      Icons.light_mode_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text('Sötét'),
                                    icon: Icon(
                                      Icons.dark_mode_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    label: Text('Rendszer'),
                                  ),
                                ],
                                selected: {_themeController.themeMode},
                                onSelectionChanged: (selection) {
                                  if (selection.isEmpty) return;
                                  _themeController.setThemeMode(
                                    selection.first,
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Színséma előnézet',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (
                                    var i = 0;
                                    i < AppColorSchemePreset.values.length;
                                    i++
                                  ) ...[
                                    if (i > 0) const SizedBox(width: 8),
                                    Expanded(
                                      child: _ThemePresetPreviewCard(
                                        preset: AppColorSchemePreset.values[i],
                                        brightness: brightness,
                                        selected:
                                            _themeController.preset ==
                                            AppColorSchemePreset.values[i],
                                        onTap: () => _themeController.setPreset(
                                          AppColorSchemePreset.values[i],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _isSigningOut ? null : _signOut,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.brick,
                      side: BorderSide(color: p.brick),
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

class _ThemePresetPreviewCard extends StatelessWidget {
  const _ThemePresetPreviewCard({
    required this.preset,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final AppColorSchemePreset preset;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = preset.paletteFor(brightness);
    final activePalette = context.palette;

    return Material(
      color: preview.canvas,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? activePalette.accent : preview.borderStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Miniature app bar + accent pill preview
              Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: preview.surface,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: preview.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 5,
                      decoration: BoxDecoration(
                        color: preview.ink,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: preview.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Miniature card tiles preview
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: preview.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: preview.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: preview.oliveSoft,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: preview.olive),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: preview.ink,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle,
                      size: 15,
                      color: activePalette.accent,
                    ),
                ],
              ),
              Text(
                preset.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: preview.inkMuted),
              ),
            ],
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
    final p = context.palette;
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
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
