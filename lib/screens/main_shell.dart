import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'account_screen.dart';
import 'inventory_intake_screen.dart';
import 'inventory_list_screen.dart';
import 'sales_dashboard_screen.dart';
import 'sales_screen.dart';

/// Top-level responsive 4-tab navigation shell for the signed-in application.
///
/// Uses a bottom [NavigationBar] on phones and a left [NavigationRail] on
/// wider tablet/web viewports while preserving each tab's state and keeping
/// Készlet and Napló automatically refreshed after sales or intake changes.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _selectedIndex = widget.initialIndex.clamp(0, 3);
  final ValueNotifier<int> _inventoryRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _salesRevision = ValueNotifier<int>(0);

  @override
  void dispose() {
    _inventoryRevision.dispose();
    _salesRevision.dispose();
    super.dispose();
  }

  void _openAccount() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AccountScreen()),
    );
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  void _notifyInventoryChanged() {
    _inventoryRevision.value++;
  }

  void _notifySaleRecorded() {
    _inventoryRevision.value++;
    _salesRevision.value++;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pages = <Widget>[
      SalesScreen(
        onOpenAccount: _openAccount,
        onSaleRecorded: _notifySaleRecorded,
        onOpenSalesLog: () => _selectTab(3),
      ),
      InventoryListScreen(
        onOpenAccount: _openAccount,
        refreshListenable: _inventoryRevision,
        onSaleRecorded: _notifySaleRecorded,
      ),
      InventoryScreen(
        onOpenAccount: _openAccount,
        onInventoryChanged: _notifyInventoryChanged,
      ),
      SalesDashboardScreen(
        onOpenAccount: _openAccount,
        refreshListenable: _salesRevision,
        onInventoryChanged: _notifyInventoryChanged,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 760;
        final extendedRail = constraints.maxWidth >= 1100;

        if (useRail) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  extended: extendedRail,
                  onDestinationSelected: _selectTab,
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: p.primaryAction,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              'Y',
                              style: TextStyle(
                                color: p.onPrimaryAction,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        if (extendedRail) ...[
                          const SizedBox(width: 10),
                          Text(
                            'YOARON',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              fontSize: 15,
                              color: p.ink,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: extendedRail
                            ? TextButton.icon(
                                onPressed: _openAccount,
                                icon: const Icon(Icons.person_outline),
                                label: const Text('Fiók'),
                              )
                            : IconButton(
                                tooltip: 'Fiók',
                                onPressed: _openAccount,
                                icon: const Icon(Icons.person_outline),
                              ),
                      ),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      selectedIcon: Icon(Icons.point_of_sale),
                      label: Text('Eladás'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.checkroom_outlined),
                      selectedIcon: Icon(Icons.checkroom),
                      label: Text('Készlet'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.add_a_photo_outlined),
                      selectedIcon: Icon(Icons.add_a_photo),
                      label: Text('Felvétel'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: Text('Napló'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(index: _selectedIndex, children: pages),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.point_of_sale_outlined),
                  selectedIcon: Icon(Icons.point_of_sale),
                  label: 'Eladás',
                ),
                NavigationDestination(
                  icon: Icon(Icons.checkroom_outlined),
                  selectedIcon: Icon(Icons.checkroom),
                  label: 'Készlet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_a_photo_outlined),
                  selectedIcon: Icon(Icons.add_a_photo),
                  label: 'Felvétel',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Napló',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
