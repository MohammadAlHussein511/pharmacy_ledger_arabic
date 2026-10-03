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
import 'week_report.dart';

/// Month tab (defaults to the current month).
class MonthReportView extends StatefulWidget {
  const MonthReportView({super.key, this.initialMonth});
  final DateTime? initialMonth;

  @override
  State<MonthReportView> createState() => _MonthReportViewState();
}

class _MonthReportViewState extends State<MonthReportView> {
  late DateTime? _month = widget.initialMonth;

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
        MonthReportBody(year: month.year, month: month.month, today: today),
      ],
    );
  }
}

class MonthReportScreen extends StatelessWidget {
  const MonthReportScreen({super.key, required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context) => Scaffold(
        // [تم التعديل] - ترجمة عنوان الشاشة
        appBar: AppBar(title: const Text('التقرير الشهري')),
        body: SafeArea(child: MonthReportView(initialMonth: month)),
      );
}

class MonthReportBody extends StatelessWidget {
  const MonthReportBody({super.key, required this.year, required this.month, required this.today});
  final int year;
  final int month;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final reports = context.read<AppServices>().reports;
    final t = Theme.of(context).textTheme;
    return RevisionBuilder<Map<String, PeriodSummary>>(
      dependency: '$year-$month',
      load: () => reports.dailyBreakdown(Dates.monthRange(year, month)),
      builder: (context, daily) {
        final total = PeriodSummary.sum(daily.values);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: Dates.monthYear(DateTime(year, month)),
              // [تم التعديل] - ترجمة تسمية المبيعات الشهرية
              child: SummaryBlock(summary: total, salesLabel: 'المبيعات الشهرية', emphasized: true),
            ),
            const SizedBox(height: 16),
            SectionCard(
              // [تم التعديل] - ترجمة عنوان التقويم والنص المساعد
              title: 'التقويم',
              subtitle: 'اضغط على يوم لرؤية إجمالياته',
              child: _MonthCalendar(year: year, month: month, daily: daily, today: today),
            ),
            const SizedBox(height: 20),
            // [تم التعديل] - ترجمة عنوان الأسابيع
            Text('الأسابيع', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            WeekList(year: year, month: month, highlight: today),
            const SizedBox(height: 8),
            SectionCard(
              // [تم التعديل] - ترجمة الإجمالي الشهري
              title: 'الإجمالي الشهري',
              child: SummaryBlock(summary: total, emphasized: true),
            ),
          ],
        );
      },
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.year,
    required this.month,
    required this.daily,
    required this.today,
  });

  final int year;
  final int month;
  final Map<String, PeriodSummary> daily;
  final DateTime today;

  // [تم التعديل] - ترجمة أسماء أيام الأسبوع
  static const _weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = Dates.daysInMonth(year, month);
    final leading = DateTime(year, month, 1).weekday - 1; // Monday first
    final cells = leading + days;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(builder: (context) {
                    final dayNum = r * 7 + c - leading + 1;
                    if (dayNum < 1 || dayNum > days) return const SizedBox(height: 48);
                    final date = DateTime(year, month, dayNum);
                    final summary = daily[Dates.key(date)];
                    final isToday = Dates.isSameDay(date, today);
                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: Material(
                        color: isToday
                            ? cs.primaryContainer
                            : (summary != null
                                ? cs.secondaryContainer.withValues(alpha: 0.45)
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showDay(context, date, summary),
                          child: SizedBox(
                            height: 44,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$dayNum',
                                    style: TextStyle(
                                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (summary?.hasSales ?? false) _Dot(color: cs.primary),
                                    if (summary?.hasPayments ?? false) _Dot(color: cs.secondary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Dot(color: cs.primary),
            // [تم التعديل] - ترجمة دليل الألوان
            const Text(' المبيعات    ', style: TextStyle(fontSize: 12)),
            _Dot(color: cs.secondary),
            const Text(' الدفعات', style: TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }

  void _showDay(BuildContext context, DateTime date, PeriodSummary? summary) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(Dates.mediumDate(date),
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SummaryBlock(summary: summary ?? PeriodSummary.empty),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openDay(context, date);
                },
                icon: const Icon(Icons.list_alt),
                // [تم التعديل] - ترجمة زر عرض المعاملات
                label: const Text('عرض المعاملات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}