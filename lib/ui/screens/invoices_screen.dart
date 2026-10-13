import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';
import 'invoice_detail_screen.dart';
import 'invoice_form_screen.dart';

/// قائمة الفواتير مع ملخص إجمالي ما علينا.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvRow {
  _InvRow({
    required this.id,
    required this.warehouseId,
    required this.warehouseName,
    required this.currency,
    required this.amountMinor,
    required this.paidMinor,
    required this.exchangeRate,
    required this.note,
    required this.invoiceDate,
  });
  final int id;
  final int warehouseId;
  final String warehouseName;
  final String currency;
  final int amountMinor;
  final int paidMinor;
  final double? exchangeRate;
  final String? note;
  final String invoiceDate;

  int get remaining => amountMinor - paidMinor;
  String get status =>
      paidMinor >= amountMinor ? 'مدفوعة' : paidMinor > 0 ? 'جزئية' : 'غير مدفوعة';
  Color statusColor(BuildContext c) => paidMinor >= amountMinor
      ? Colors.green
      : paidMinor > 0
          ? Colors.orange
          : Colors.red;
}

String _money(int minor, String cur) =>
    '${(minor / 100).toStringAsFixed(2)} $cur';

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<_InvRow> _rows = [];
  Map<int, String> _whNames = {};
  bool _loading = true;
  String _filter = 'all';

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
      final whs = (data['warehouses'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final invs = (data['invoices'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final pays = (data['invoice_payments'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      _whNames = {
        for (final w in whs) w['id'] as int: w['name'] as String,
      };

      final paidByInv = <int, int>{};
      for (final p in pays) {
        final invId = p['invoice_id'] as int;
        final amount = p['amount_minor'] as int;
        final paidCur = p['currency_paid'] as String;
        final rate = p['exchange_rate'] as double?;
        final inv = invs.firstWhere((i) => i['id'] == invId, orElse: () => {});
        final invCur = inv['currency'] as String?;
        if (invCur == null) continue;

        int equivalent;
        if (paidCur == invCur) {
          equivalent = amount;
        } else if (invCur == 'USD' && paidCur == 'TRY' && rate != null && rate > 0) {
          equivalent = (amount / rate).round();
        } else if (invCur == 'SYP' && paidCur == 'TRY' && rate != null && rate > 0) {
          equivalent = (amount / rate).round();
        } else {
          equivalent = amount;
        }
        paidByInv[invId] = (paidByInv[invId] ?? 0) + equivalent;
      }

      final rows = <_InvRow>[];
      for (final i in invs) {
        final id = i['id'] as int;
        final wid = i['warehouse_id'] as int;
        rows.add(_InvRow(
          id: id,
          warehouseId: wid,
          warehouseName: _whNames[wid] ?? 'مستودع محذوف',
          currency: i['currency'] as String,
          amountMinor: i['amount_minor'] as int,
          paidMinor: paidByInv[id] ?? 0,
          exchangeRate: (i['exchange_rate'] as num?)?.toDouble(),
          note: i['note'] as String?,
          invoiceDate: i['invoice_date'] as String,
        ));
      }
      rows.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<_InvRow> get _filtered {
    if (_filter == 'unpaid') {
      return _rows.where((r) => r.paidMinor < r.amountMinor).toList();
    }
    if (_filter == 'paid') {
      return _rows.where((r) => r.paidMinor >= r.amountMinor).toList();
    }
    return _rows;
  }

  Map<String, int> get _totals {
    final m = <String, int>{};
    for (final r in _rows) {
      m[r.currency] = (m[r.currency] ?? 0) + r.remaining;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final totals = _totals;
    final totalText = totals.isEmpty
        ? 'لا يوجد ما علينا'
        : totals.entries
            .map((e) => _money(e.value, e.key))
            .join(' + ');
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('إجمالي ما علينا',
                              style: t.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer)),
                          const SizedBox(height: 8),
                          Text(totalText,
                              style: t.headlineSmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.w700)),
                          Text('${_rows.length} فاتورة',
                              style: t.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('الكل')),
                      ButtonSegment(
                          value: 'unpaid', label: Text('غير مدفوعة')),
                      ButtonSegment(value: 'paid', label: Text('مدفوعة')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('لا توجد فواتير',
                            style: t.bodyLarge),
                      ),
                    )
                  else
                    ..._filtered.map((r) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: r.statusColor(context)
                                  .withValues(alpha: 0.15),
                              child: Icon(Icons.receipt_long,
                                  color: r.statusColor(context)),
                            ),
                            title: Text(r.warehouseName),
                            subtitle: Text(
                              '${r.invoiceDate} · ${r.status}\n'
                              'المتبقي: ${_money(r.remaining, r.currency)}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              _money(r.amountMinor, r.currency),
                              style: t.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => InvoiceDetailScreen(
                                          invoiceId: r.id,
                                        )),
                              );
                              _load();
                            },
                          ),
                        )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InvoiceFormScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('فاتورة جديدة'),
      ),
    );
  }
}