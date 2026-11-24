import 'package:flutter/material.dart';

import '../services/employee_stats_service.dart';
import '../theme/app_theme.dart';

enum _TeamStatsSort { revenue, dailyAvg, uploads }

class TeamStatsScreen extends StatefulWidget {
  const TeamStatsScreen({
    super.key,
    this.statsGateway = const SupabaseEmployeeStatsGateway(),
  });

  final EmployeeStatsGateway statsGateway;

  @override
  State<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends State<TeamStatsScreen> {
  List<EmployeeStats> _members = const [];
  bool _isLoading = true;
  String? _error;
  _TeamStatsSort _sort = _TeamStatsSort.revenue;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final members = await widget.statsGateway.fetchAllEmployeeStats();
      if (!mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  List<EmployeeStats> get _sortedMembers {
    final copy = List<EmployeeStats>.from(_members);
    copy.sort((a, b) {
      return switch (_sort) {
        _TeamStatsSort.revenue => b.totalSalesRevenue.compareTo(
          a.totalSalesRevenue,
        ),
        _TeamStatsSort.dailyAvg => b.dailyAvgRevenue.compareTo(
          a.dailyAvgRevenue,
        ),
        _TeamStatsSort.uploads => b.uploadedItemsCount.compareTo(
          a.uploadedItemsCount,
        ),
      };
    });
    return copy;
  }

  String _initialsFor(EmployeeStats stats) {
    final source = stats.displayName.trim().isNotEmpty
        ? stats.displayName
        : stats.email;
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
    final sorted = _sortedMembers;
    final totalRevenue = sorted.fold<double>(
      0,
      (sum, member) => sum + member.totalSalesRevenue,
    );
    final totalSalesCount = sorted.fold<int>(
      0,
      (sum, member) => sum + member.salesCount,
    );
    final totalUploads = sorted.fold<int>(
      0,
      (sum, member) => sum + member.uploadedItemsCount,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Csapat statisztikák'),
        actions: [
          IconButton(
            tooltip: 'Frissítés',
            onPressed: _isLoading ? null : _loadStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading && _members.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _members.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 42,
                      color: AppColors.brick,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A csapat statisztikák csak manager és admin jogosultsággal érhetők el.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _loadStats,
                      child: const Text('Újrapróbálás'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _TeamSummaryStrip(
                        totalRevenue: AppFormat.forint(totalRevenue),
                        totalSalesCount: '$totalSalesCount db',
                        totalUploads: '$totalUploads db',
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<_TeamStatsSort>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          selectedBackgroundColor: AppColors.terracottaSoft,
                          selectedForegroundColor: AppColors.terracotta,
                          foregroundColor: AppColors.inkMuted,
                          side: const BorderSide(color: AppColors.border),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: _TeamStatsSort.revenue,
                            label: Text('Összes eladás'),
                          ),
                          ButtonSegment(
                            value: _TeamStatsSort.dailyAvg,
                            label: Text('Napi átlag'),
                          ),
                          ButtonSegment(
                            value: _TeamStatsSort.uploads,
                            label: Text('Feltöltések'),
                          ),
                        ],
                        selected: {_sort},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          setState(() => _sort = selection.first);
                        },
                      ),
                      const SizedBox(height: 14),
                      if (sorted.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            'Még nincs megjeleníthető munkatársi statisztika.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.inkMuted),
                          ),
                        )
                      else
                        for (final member in sorted) ...[
                          _EmployeeStatsCard(
                            member: member,
                            initials: _initialsFor(member),
                          ),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TeamSummaryStrip extends StatelessWidget {
  const _TeamSummaryStrip({
    required this.totalRevenue,
    required this.totalSalesCount,
    required this.totalUploads,
  });

  final String totalRevenue;
  final String totalSalesCount;
  final String totalUploads;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final cards = [
          _SummaryBox(
            label: 'Csapat bevétel',
            value: totalRevenue,
            icon: Icons.payments_outlined,
            accent: AppColors.olive,
            tint: AppColors.oliveSoft,
          ),
          _SummaryBox(
            label: 'Eladások',
            value: totalSalesCount,
            icon: Icons.receipt_long_outlined,
            accent: AppColors.terracotta,
            tint: AppColors.terracottaSoft,
          ),
          _SummaryBox(
            label: 'Feltöltések',
            value: totalUploads,
            icon: Icons.checkroom_outlined,
            accent: AppColors.ink,
            tint: AppColors.surfaceMuted,
          ),
        ];

        if (compact) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cards[1]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[2]),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeStatsCard extends StatelessWidget {
  const _EmployeeStatsCard({required this.member, required this.initials});

  final EmployeeStats member;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final isPrivileged = member.isAdmin || member.isManager;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.terracottaSoft,
                  foregroundColor: AppColors.terracotta,
                  child: Text(
                    initials,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (member.email.isNotEmpty)
                        Text(
                          member.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPrivileged
                        ? AppColors.terracottaSoft
                        : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    member.primaryRoleLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isPrivileged
                          ? AppColors.terracotta
                          : AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: _MetricColumn(
                    label: 'Összes eladás',
                    value: AppFormat.forint(member.totalSalesRevenue),
                    detail:
                        '${member.salesCount} eladás · ${member.soldItemsCount} db',
                    valueColor: AppColors.olive,
                  ),
                ),
                Expanded(
                  child: _MetricColumn(
                    label: 'Napi átlag',
                    value: AppFormat.forint(member.dailyAvgRevenue),
                    detail:
                        '${member.activeSalesDays} aktív nap · ${AppFormat.amount(member.dailyAvgSalesCount)}/nap',
                  ),
                ),
                Expanded(
                  child: _MetricColumn(
                    label: 'Feltöltve',
                    value: '${member.uploadedItemsCount} db',
                    detail: 'Készletbe felvéve',
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    required this.detail,
    this.valueColor,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final String detail;
  final Color? valueColor;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final alignment = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}
