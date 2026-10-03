import 'package:flutter/material.dart';

import '../../../core/dates.dart';

/// Grid month selector with year navigation. Returns the first day of the month.
Future<DateTime?> showMonthPicker(BuildContext context, DateTime initial) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _MonthPickerDialog(initial: initial),
  );
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});
  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          IconButton(
              // [تم التعديل] - ترجمة tooltip السنة السابقة
              tooltip: 'السنة السابقة',
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.chevron_left)),
          Expanded(child: Center(child: Text('$_year'))),
          IconButton(
              // [تم التعديل] - ترجمة tooltip السنة التالية
              tooltip: 'السنة التالية',
              onPressed: _year >= now.year ? null : () => setState(() => _year++),
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          childAspectRatio: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var m = 1; m <= 12; m++)
              Builder(builder: (context) {
                final selected = _year == widget.initial.year && m == widget.initial.month;
                final future = DateTime(_year, m).isAfter(DateTime(now.year, now.month));
                return selected
                    ? FilledButton(
                        style: FilledButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero),
                        onPressed: () => Navigator.pop(context, DateTime(_year, m)),
                        child: Text(Dates.shortMonthName(m)),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: EdgeInsets.zero,
                            foregroundColor: future ? cs.onSurfaceVariant : null),
                        onPressed: future ? null : () => Navigator.pop(context, DateTime(_year, m)),
                        child: Text(Dates.shortMonthName(m)),
                      );
              }),
          ],
        ),
      ),
      actions: [
        // [تم التعديل] - ترجمة زر الإلغاء
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
    );
  }
}