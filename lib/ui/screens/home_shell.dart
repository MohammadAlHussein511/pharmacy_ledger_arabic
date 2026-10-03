import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'reports/reports_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'warehouses_screen.dart';

/// Five destinations keep navigation simple on a phone:
/// Home · Today · Reports (Week / Month / Year) · Warehouses · Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static HomeShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _reportsKey = GlobalKey<ReportsScreenState>();

  void openTab(int index) => setState(() => _index = index);

  void openReports(ReportTab tab) {
    setState(() => _index = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportsKey.currentState?.show(tab));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            const HomeScreen(),
            const TodayScreen(),
            ReportsScreen(key: _reportsKey),
            const WarehousesScreen(),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: openTab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            // [تم التعديل] - ترجمة علامات التبويب السفلية
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
            NavigationDestination(
                icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'اليوم'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'التقارير'),
            NavigationDestination(
                icon: Icon(Icons.warehouse_outlined), selectedIcon: Icon(Icons.warehouse), label: 'المستودعات'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }
}
