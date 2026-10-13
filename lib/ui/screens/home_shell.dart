import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services.dart';
import '../../sync/auto_sync.dart';
import 'accounts_screen.dart';
import 'home_screen.dart';
import 'reports/reports_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'warehouses_screen.dart';
import 'weeks_screen.dart';

/// 7 تبويبات: الرئيسية، اليوم، الحسابات، المستودعات، الأسابيع، التقارير، الإعدادات
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static HomeShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _reportsKey = GlobalKey<ReportsScreenState>();
  AutoSync? _autoSync;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoSync = AutoSync(context.read<AppServices>())..start();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _autoSync?.stop();
    super.dispose();
  }

  void openTab(int index) {
    setState(() {
      _tabController.index = index;
    });
  }

  void openReports(ReportTab tab) {
    setState(() {
      _tabController.index = 5; // التقارير
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportsKey.currentState?.show(tab));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tabController.index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _tabController.index = 0;
          });
        }
      },
      child: Scaffold(
        body: TabBarView(
          controller: _tabController,
          children: [
            const HomeScreen(),
            const TodayScreen(),
            const AccountsScreen(),
            const WarehousesScreen(standalone: true),
            const WeeksScreen(),
            ReportsScreen(key: _reportsKey),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            unselectedLabelStyle: Theme.of(context).textTheme.labelSmall,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'الرئيسية'),
              Tab(icon: Icon(Icons.today_outlined), text: 'اليوم'),
              Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'الحسابات'),
              Tab(icon: Icon(Icons.warehouse_outlined), text: 'المستودعات'),
              Tab(icon: Icon(Icons.calendar_month_outlined), text: 'الأسابيع'),
              Tab(icon: Icon(Icons.bar_chart_outlined), text: 'التقارير'),
              Tab(icon: Icon(Icons.settings_outlined), text: 'الإعدادات'),
            ],
          ),
        ),
      ),
    );
  }
}