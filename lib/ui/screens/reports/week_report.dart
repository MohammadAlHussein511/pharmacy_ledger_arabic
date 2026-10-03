import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/period_summary.dart';
import '../../../services.dart';
import '../../day_clock.dart';
import '../../widgets/common.dart';
import '../../widgets/revision_builder.dart';
import '../day_view.dart';
import 'month_picker.dart';

/// Week tab: pick a month (defaults to the current month), see its weeks.
class WeekReportView extends StatefulWidget {
  const WeekReportView({super.key});

  @override
  State<WeekReportView> createState() => _WeekReportViewState();
}

class _WeekReportViewState extends State<WeekReportView> {
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final today = context.watch<DayClock>().today;
    final month = _month ?? DateTime(today.year, today.month);
    final isCurrent = month.year == today.year && month.month == today.month;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        PeriodSwitcher(
          label: Dates.monthYear(month),
          onPrevious: () => setState(() => _month = Dates.addMonths(month, -1)),
          onNext: () => setState(() => _month = Dates.addMonths(month, 1)),
          canGoNext: !isCurrent,
          onTapLabel: () async {
            final m = await showMonthPicker(context, month);
            if (m != null) setState(() => _month = m);
          },
        ),
        const SizedBox(height: 8),
        WeekList(year: month.year, month: month.month, highlight: today),
      ],
    );
  }
}

/// The weeks of one month (1-7, 8-14, 15-21, 22-28, 29-end), each with totals.
class WeekList extends StatelessWidget {
  const WeekList({super.key, required this.year, required this.month, this.highlight});
  final int year;
  final int month;
  final DateTime? highlight;

  @override
  Widget build(BuildContext context) {
    final reports = context.read<AppServices>().reports;
    return RevisionBuilder<List<(MonthWeek, PeriodSummary)>>(
      dependency: '$year-$month',
      load: () => reports.weeklyBreakdown(year, month),
      builder: (context, weeks) => Column(
        children: [
          for (final (week, summary) in weeks) ...[
            SectionCard(
              title: week.title,
              // [تم التعديل] - ترجمة "الأسبوع الحالي" ورسالة عدم وجود معاملات
              subtitle: week.daysLabel +
                  (highlight != null && week.range.contains(highlight!) ? ' · الأسبوع الحالي' : ''),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => WeekDetailScreen(week: week)),
              ),
              child: summary.isEmpty
                  ? Text('لا توجد معاملات مسجلة لهذه الفترة.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                  // [تم التعديل] - ترجمة المبيعات الأسبوعية
                  : SummaryBlock(summary: summary, salesLabel: 'المبيعات الأسبوعية'),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class WeekDetailScreen extends StatelessWidget {
  const WeekDetailScreen({super.key, required this.week});
  final MonthWeek week;

  @override
  Widget build(BuildContext context) {
    final reports = context.read<AppServices>().reports;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
          title: Text('${week.title} · ${Dates.monthYear(DateTime(week.year, week.month))}')),
      body: SafeArea(
        child: RevisionBuilder<Map<String, PeriodSummary>>(
          dependency: week,
          load: () => reports.dailyBreakdown(week.range),
          builder: (context, daily) {
            final total = PeriodSummary.sum(daily.values);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(week.daysLabel, style: t.bodyLarge),
                const SizedBox(height: 12),
                SectionCard(
                  // [تم التعديل] - ترجمة إجمالي الأسبوع والمبيعات الأسبوعية
                  title: 'إجمالي الأسبوع',
                  child: SummaryBlock(
                      summary: total, salesLabel: 'المبيعات الأسبوعية', emphasized: true),
                ),
                const SizedBox(height: 20),
                // [تم التعديل] - ترجمة "حسب اليوم"
                Text('حسب اليوم', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final day in week.range.days) ...[
                  SectionCard(
                    // [تم التعديل] - ترجمة "اليوم"
                    title: 'اليوم ${day.day}',
                    subtitle: Dates.shortDate(day),
                    onTap: () => openDay(context, day),
                    child: daily[Dates.key(day)] == null
                        ? Text('لا توجد معاملات',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                        : SummaryBlock(summary: daily[Dates.key(day)]!),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
