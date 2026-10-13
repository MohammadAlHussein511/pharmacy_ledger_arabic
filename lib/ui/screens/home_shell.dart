import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';
import '../../sync/auto_sync.dart';
import 'accounts_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'reports/reports_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'weeks_screen.dart';  // [مضاف] هذا الاستيراد كان ناقصاً

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static HomeShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _tick = 0;
  final _reportsKey = GlobalKey<ReportsScreenState>();
  AutoSync? _autoSync;

  /// إعادة بناء الشاشات لقراءة أحدث البيانات
  void bump() {
    if (mounted) setState(() => _tick++);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoSync = AutoSync(context.read<AppServices>())..start();
    });
  }

  @override
  void dispose() {
    _autoSync?.stop();
    super.dispose();
  }

  void openTab(int index) => setState(() {
        _index = index;
        _tick++;
      });

  void openReports(ReportTab tab) {
    setState(() {
      _index = 3;
      _tick++;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportsKey.currentState?.show(tab));
  }

  Widget _tabChild(int index) {
    switch (index) {
      case 1:
        return TodayScreen(key: ValueKey('today-$_tick'));
      case 2:
        return WeeksScreen(key: ValueKey('weeks-$_tick'));
      case 3:
        return ReportsScreen(key: _reportsKey);
      case 4:
        return AccountsScreen(key: ValueKey('accounts-$_tick'));
      case 5:
        return const SettingsScreen();
      case 6:
        return const MoreScreen();
      default:
        return HomeScreen(key: ValueKey('home-$_tick'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: _tabChild(_index),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: openTab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'الرئيسية'),
            NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: 'اليوم'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'الأسابيع'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'التقارير'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'الحسابات'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'الإعدادات'),
            NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'المزيد'),
          ],
        ),
      ),
    );
  }
}