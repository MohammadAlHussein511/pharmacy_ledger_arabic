import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';

class WeeksScreen extends StatefulWidget {
  const WeeksScreen({super.key});

  @override
  State<WeeksScreen> createState() => _WeeksScreenState();
}

class _WeekRow {
  _WeekRow(this.start, this.end);
  final DateTime start;
  final DateTime end;
  final Map<String, int> sales = {};
  final Map<String, int> payments = {};
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmt(DateTime d) => '${d.year}/${_two(d.month)}/${_two(d.day)}';
String _money(int minor) => (minor / 100).toStringAsFixed(2);

String _curLabel(String c) => switch (c) {
      'TRY' => 'ليرة تركية',
      'USD' => 'دولار',
      'SYP' => 'ليرة سورية',
      _ => c,
    };

int _offsetFromSaturday(DateTime d) {
  switch (d.weekday) {
    case 6:
      return 0;
    case 7:
      return 1;
    default:
      return d.weekday + 1;
  }
}

class _WeeksScreenState extends State<WeeksScreen> {
  List<_WeekRow> _weeks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = context.read<AppServices>();
      final bytes = await services.backup.createBackup();
      final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = env['data'] as Map<String, dynamic>;
      final txs = (data['transactions'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final map = <String, _WeekRow>{};
      for (final t in txs) {
        final date = DateTime.tryParse('${t['transaction_date']}');
        if (date == null) continue;
        final start = date.subtract(Duration(days: _offsetFromSaturday(date)));
        final end = start.add(const Duration(days: 6));
        final key = _fmt(start);
        final row = map.putIfAbsent(key, () => _WeekRow(start, end));
        final cur = '${t['currency']}';
        final amt = t['amount_minor'] as int;
        if (t['type'] == 'SALE') {
          row.sales[cur] = (row.sales[cur] ?? 0) + amt;
        } else {
          row.payments[cur] = (row.payments[cur] ?? 0) + amt;
        }
      }

      final list = map.values.toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      if (!mounted) return;
      setState(() {
        _weeks = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _currencyLines(Map<String, int> m) {
    if (m.isEmpty) {
      return Text('—', style: Theme.of(context).textTheme.bodyLarge);
    }
    final sorted = m.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${_money(e.value)} ${_curLabel(e.key)}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير الأسابيع'),
        actions: [
          IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _weeks.isEmpty
              ? const Center(child: Text('لا توجد بيانات بعد'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _weeks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final w = _weeks[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('من ${_fmt(w.start)} إلى ${_fmt(w.end)}',
                                style: t.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            Text('المبيعات',
                                style: t.bodyMedium?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline)),
                            const SizedBox(height: 4),
                            _currencyLines(w.sales),
                            const SizedBox(height: 12),
                            Text('المدفوعات',
                                style: t.bodyMedium?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline)),
                            const SizedBox(height: 4),
                            _currencyLines(w.payments),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}