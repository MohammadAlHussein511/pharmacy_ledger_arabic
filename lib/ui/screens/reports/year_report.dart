import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/period_summary.dart';
import '../../../services.dart';
import '../../day_clock.dart';
import '../../widgets/common.dart';
import '../../widgets/revision_builder.dart';
import 'month_report.dart';

/// Year tab (defaults to the current year): all 12 months + annual totals.
class YearReportView extends StatefulWidget {
  const YearReportView({super.key});

  @override
  State<YearReportView> createState() => _YearReportViewState();
}

class _YearReportViewState extends State<YearReportView> {
  int? _year;

  Future<void> _pickYear(int current) async {
    final services = context.read<AppServices>();
    final years = await services.reports.availableYears(DateTime.now());
    if (!mounted) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        // [تم التعديل] - ترجمة عنوان اختيار السنة
        title: const Text('اختر سنة'),
        children: [
          for (final y in years)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, y),
              child: Text('$y',
                  style: TextStyle(fontWeight: y == current ? FontWeight.w800 : FontWeight.w400)),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _year = picked);
  }

  @override
  Widget build(BuildContext context) {
    final today = context.watch<DayClock>().today;
    final year = _year ?? today.year;
    final reports = context.read<AppServices>().reports;
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        PeriodSwitcher(
          label: '$year',
          onPrevious: () => setState(() => _year = year - 1),
          onNext: () => setState(() => _year = year + 1),
          canGoNext: year < today.year,
          onTapLabel: () => _pickYear(year),
        ),
        const SizedBox(height: 8),
        RevisionBuilder<Map<int, PeriodSummary>>(
          dependency: year,
          load: () => reports.monthlyBreakdown(year),
          builder: (context, months) {
            final total = PeriodSummary.sum(months.values);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var m = 1; m <= 12; m++) ...[
                  SectionCard(
                    title: Dates.monthName(m),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => MonthReportScreen(month: DateTime(year, m))),
                    ),
                    child: SummaryBlock(summary: months[m]!, showAllCurrencies: true),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                // [تم التعديل] - ترجمة الإجمالي السنوي
                Text('الإجمالي السنوي $year',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SectionCard(
                  child: SummaryBlock(
                    summary: total,
                    // [تم التعديل] - ترجمة المبيعات السنوية
                    salesLabel: 'المبيعات السنوية',
                    showAllCurrencies: true,
                    emphasized: true,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}