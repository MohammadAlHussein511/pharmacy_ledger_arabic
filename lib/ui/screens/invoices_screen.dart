import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';
import 'invoice_detail_screen.dart';
import 'invoice_form_screen.dart';

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
    required this.invoiceDate,
  });
  final int id;
  final int warehouseId;
  final String warehouseName;
  final String currency;
  final int amountMinor;
  final int paidMinor;
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

String _money(int minor, String cur) => '${(minor / 100).toStringAsFixed(2)} $cur';

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<_InvRow> _rows = [];
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
      final db = services.db;
      final whs = await db.query('warehouses');
      final whNames = {for (final w in whs) w['id'] as int: w['name'] as String};
      final invs = await db.query('invoices', orderBy: 'invoice_date DESC, id DESC');

      final rows = <_InvRow>[];
      for (final i in invs) {
        final iid = i['id'] as int;
        final wid = i['warehouse_id'] as int;
        final invCur = i['currency'] as String;

        final paidResult = await db.rawQuery('''
          SELECT COALESCE(SUM(
            CASE
              WHEN currency_paid = ? THEN amount_minor
              WHEN exchange_rate IS NOT NULL AND exchange_rate > 0
                THEN CAST(ROUND(amount_minor * 1.0 / exchange_rate) AS INTEGER)
              ELSE 0
            END
          ), 0) as paid
          FROM invoice_payments
          WHERE invoice_id = ?
        ''', [invCur, iid]);
        final paid = (paidResult.first['paid'] as num).toInt();

        rows.add(_InvRow(
          id: iid,
          warehouseId: wid,
          warehouseName: whNames[wid] ?? 'مستودع محذوف',
          currency: invCur,
          amountMinor: i['amount_minor'] as int,
          paidMinor: paid,
          invoiceDate: i['invoice_date'] as String,
        ));
      }

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
    if (_filter == 'unpaid') return _rows.where((r) => r.remaining > 0).toList();
    if (_filter == 'paid') return _rows.where((r) => r.remaining <= 0).toList();
    return _rows;
  }

  Map<String, int> get _totals {
    final m = <String, int>{};
    for (final r in _rows) {
      if (r.remaining > 0) m[r.currency] = (m[r.currency] ?? 0) + r.remaining;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final totals = _totals;
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
                                  color: Theme.of(context).colorScheme.onPrimaryContainer)),
                          const SizedBox(height: 8),
                          // [جديد] كل عملة في صف مستقل
                          if (totals.isEmpty)
                            Text('لا يوجد ما علينا',
                                style: t.headlineSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                    fontWeight: FontWeight.w700))
                          else
                            for (final e in totals.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(_money(e.value, e.key),
                                    style: t.headlineSmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                        fontWeight: FontWeight.w700)),
                              ),
                          const SizedBox(height: 4),
                          Text('${_rows.length} فاتورة', style: t.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('الكل')),
                      ButtonSegment(value: 'unpaid', label: Text('غير مدفوعة')),
                      ButtonSegment(value: 'paid', label: Text('مدفوعة')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) => setState(() => _filter = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text('لا توجد فواتير', style: t.bodyLarge)),
                    )
                  else
                    ..._filtered.map((r) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  r.statusColor(context).withValues(alpha: 0.15),
                              child: Icon(Icons.receipt_long, color: r.statusColor(context)),
                            ),
                            title: Text(r.warehouseName),
                            subtitle: Text(
                              '${r.invoiceDate} · ${r.status}\n'
                              'المتبقي: ${_money(r.remaining, r.currency)}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              _money(r.amountMinor, r.currency),
                              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => InvoiceDetailScreen(invoiceId: r.id)),
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