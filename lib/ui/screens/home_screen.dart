import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../domain/period_summary.dart';
import '../../domain/report_service.dart';
import '../../services.dart';
import '../day_clock.dart';
import '../widgets/common.dart';
import '../widgets/revision_builder.dart';
import '../widgets/transaction_widgets.dart';
import 'home_shell.dart';
import 'reports/reports_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = context.read<AppServices>().reports;
    final today = context.watch<DayClock>().today;
    return Scaffold(
      appBar: AppBar(
        // [تم التعديل] - ترك الاسم بالإنجليزية كما هو، مع تحسين الخط
        title: const Text('دفتر الصيدلية', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            // [تم التعديل] - ترجمة tooltip البحث
            tooltip: 'البحث في المدفوعات',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: RevisionBuilder<DashboardData>(
          dependency: Dates.key(today),
          load: () => reports.dashboard(today),
          builder: (context, d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(Dates.fullDate(d.todayDate),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => openAddSale(context),
                      icon: const Icon(Icons.add),
                      // [تم التعديل] - ترجمة زر إضافة بيع
                      label: const Text('إضافة بيع'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => openAddPayment(context),
                      icon: const Icon(Icons.add),
                      // [تم التعديل] - ترجمة زر إضافة دفعة
                      label: const Text('إضافة دفعة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // [تم التعديل] - ترجمة عناوين الفترات الزمنية
              _PeriodCard(
                title: 'اليوم',
                subtitle: Dates.mediumDate(d.todayDate),
                summary: d.today,
                onTap: () => HomeShell.of(context)?.openTab(1),
                emphasized: true,
              ),
              const SizedBox(height: 12),
              _PeriodCard(
                title: 'هذا الأسبوع',
                subtitle: '${d.currentWeek.title} · ${d.currentWeek.longLabel}',
                summary: d.week,
                onTap: () => HomeShell.of(context)?.openReports(ReportTab.week),
              ),
              const SizedBox(height: 12),
              _PeriodCard(
                title: 'هذا الشهر',
                subtitle: Dates.monthYear(d.todayDate),
                summary: d.month,
                onTap: () => HomeShell.of(context)?.openReports(ReportTab.month),
              ),
              const SizedBox(height: 12),
              _PeriodCard(
                title: 'هذه السنة',
                subtitle: '${d.todayDate.year}',
                summary: d.year,
                onTap: () => HomeShell.of(context)?.openReports(ReportTab.year),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.onTap,
    this.emphasized = false,
  });

  final String title;
  final String subtitle;
  final PeriodSummary summary;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        child: SummaryBlock(summary: summary, showAllCurrencies: true, emphasized: emphasized),
      );
}

