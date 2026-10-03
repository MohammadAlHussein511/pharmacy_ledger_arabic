import 'package:flutter/material.dart';

import 'month_report.dart';
import 'week_report.dart';
import 'year_report.dart';

enum ReportTab { week, month, year }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => ReportsScreenState();
}

class ReportsScreenState extends State<ReportsScreen> {
  ReportTab _tab = ReportTab.week;

  void show(ReportTab tab) {
    if (mounted) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [تم التعديل] - ترجمة عنوان الشاشة
      appBar: AppBar(title: const Text('التقارير')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ReportTab>(
                  showSelectedIcon: false,
                  segments: const [
                    // [تم التعديل] - ترجمة أسماء التبويبات
                    ButtonSegment(value: ReportTab.week, label: Text('أسبوع')),
                    ButtonSegment(value: ReportTab.month, label: Text('شهر')),
                    ButtonSegment(value: ReportTab.year, label: Text('سنة')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: const [WeekReportView(), MonthReportView(), YearReportView()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
