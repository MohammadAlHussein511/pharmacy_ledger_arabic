import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/invoice_math.dart';
import '../../services.dart';
import 'invoice_form_screen.dart';
import 'payment_form_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final int invoiceId;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, Object?>? _invoice;
  String? _warehouseName;
  int _paid = 0;
  List<PayRow> _payments = [];
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
      final db = services.db;
      final invs = await db.query('invoices', where: 'id = ?', whereArgs: [widget.invoiceId]);
      if (invs.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final inv = invs.first;
      final wid = inv['warehouse_id'] as int;
      final whs = await db.query('warehouses', where: 'id = ?', whereArgs: [wid]);
      final paidMap = await InvoiceMath.paidByInvoice(db, wid);
      final pays = await InvoiceMath.warehousePayments(db, wid);

      if (!mounted) return;
      setState(() {
        _invoice = inv.cast<String, Object?>();
        _warehouseName = whs.isEmpty ? 'مستودع محذوف' : whs.first['name'] as String;
        _paid = paidMap[widget.invoiceId] ?? 0;
        _payments = pays.reversed.toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _editInvoice() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => InvoiceFormScreen(existing: _invoice)),
    );
    if (result == true && mounted) _load();
  }

  Future<void> _deleteInvoice() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الفاتورة؟'),
        content: const Text('سيتم حذف الفاتورة. الدفعات المرتبطة بالمستودع تبقى محفوظة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final services = context.read<AppServices>();
    final db = services.db;
    final wid = _invoice!['warehouse_id'] as int;

    await db.transaction((txn) async {
      // إعادة ربط دفعات هذه الفاتورة بأقدم فاتورة أخرى للمستودع
      final others = await txn.query('invoices',
          where: 'warehouse_id = ? AND id != ?',
          whereArgs: [wid, widget.invoiceId],
          orderBy: 'invoice_date ASC, id ASC');
      final pays = await txn.query('invoice_payments',
          where: 'invoice_id = ?', whereArgs: [widget.invoiceId]);
      for (final p in pays) {
        if (others.isNotEmpty) {
          await txn.update('invoice_payments', {'invoice_id': others.first['id']},
              where: 'id = ?', whereArgs: [p['id']]);
        } else {
          final txId = p['transaction_id'] as int?;
          if (txId != null) {
            await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
          }
          await txn.delete('invoice_payments', where: 'id = ?', whereArgs: [p['id']]);
        }
      }
      await txn.delete('invoices', where: 'id = ?', whereArgs: [widget.invoiceId]);
    });
    services.store.changed();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _editPayment(PayRow p) async {
    final amountController = TextEditingController(text: (p.amountMinor / 100).toStringAsFixed(2));
    final rateController = TextEditingController(text: p.exchangeRate?.toString() ?? '');
    final invCur = _invoice?['currency'] as String?;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الدفعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'القيمة (${p.currencyPaid})', border: const OutlineInputBorder()),
            ),
            if (p.currencyPaid != invCur) ...[
              const SizedBox(height: 12),
              TextField(
                controller: rateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'قيمة الصرف', border: OutlineInputBorder()),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, {'amount': amountController.text, 'rate': rateController.text}),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final amount = double.tryParse(result['amount'] as String);
    if (amount == null || amount <= 0) return;
    final rate = double.tryParse(result['rate'] as String);
    final services = context.read<AppServices>();
    final now = DateTime.now().toIso8601String();

    // [نهائي] تعديل الدفعة + الـ transaction المرتبط معاً
    await services.db.transaction((txn) async {
      await txn.update('invoice_payments', {
        'amount_minor': (amount * 100).round(),
        'exchange_rate': rate,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [p.id]);
      if (p.transactionId != null) {
        await txn.update('transactions', {
          'amount_minor': (amount * 100).round(),
          'updated_at': now,
        }, where: 'id = ?', whereArgs: [p.transactionId]);
      }
    });
    services.store.changed();
    _load();
  }

  Future<void> _deletePayment(PayRow p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الدفعة؟'),
        content: const Text('ستُحذف من الحسابات ومن الصفحة الرئيسية معاً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final services = context.read<AppServices>();

    // [نهائي] حذف الدفعة + الـ transaction المرتبط معاً
    await services.db.transaction((txn) async {
      if (p.transactionId != null) {
        await txn.delete('transactions', where: 'id = ?', whereArgs: [p.transactionId]);
      }
      await txn.delete('invoice_payments', where: 'id = ?', whereArgs: [p.id]);
    });
    services.store.changed();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final inv = _invoice;
    if (inv == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('لم تعد موجودة')));
    }
    final invCur = inv['currency'] as String;
    final amount = inv['amount_minor'] as int;
    final remaining = amount - _paid;
    final progress = amount > 0 ? (_paid / amount).clamp(0.0, 1.0) : 0.0;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_warehouseName ?? 'فاتورة'),
        actions: [
          IconButton(
              tooltip: 'تعديل الفاتورة',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editInvoice),
          IconButton(
              tooltip: 'حذف الفاتورة',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteInvoice),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تفاصيل الفاتورة', style: t.titleMedium),
                    const SizedBox(height: 12),
                    Row(children: [
                      Text('المستودع:', style: t.bodyMedium),
                      const Spacer(),
                      Text(_warehouseName ?? '',
                          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('التاريخ:', style: t.bodyMedium),
                      const Spacer(),
                      Text(inv['invoice_date'] as String, style: t.bodyMedium),
                    ]),
                    const Divider(height: 24),
                    Text('قيمة الفاتورة',
                        style: t.bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                    Text(moneyText(amount, invCur),
                        style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${(progress * 100).toStringAsFixed(0)}%'),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('المدفوع', style: t.bodySmall),
                        Text(moneyText(_paid, invCur),
                            style: t.titleMedium
                                ?.copyWith(color: Colors.green, fontWeight: FontWeight.w700)),
                      ]),
                      const Spacer(),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('المتبقي', style: t.bodySmall),
                        Text(moneyText(remaining, invCur),
                            style: t.titleMedium?.copyWith(
                                color: remaining > 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('دفعات المستودع (${_payments.length})', style: t.titleMedium),
              const Spacer(),
              if (remaining > 0)
                FilledButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PaymentFormScreen(
                                invoiceId: widget.invoiceId,
                                invoiceCurrency: invCur,
                                remainingMinor: remaining,
                                warehouseId: inv['warehouse_id'] as int,
                              )),
                    );
                    if (result == true && mounted) _load();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('دفعة'),
                ),
            ]),
            const SizedBox(height: 8),
            if (_payments.isEmpty)
              const Card(child: ListTile(title: Text('لا توجد دفعات بعد')))
            else
              ..._payments.map((p) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: currencyAvatar(p.currencyPaid),
                      title: Text(moneyText(p.amountMinor, p.currencyPaid)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p.date} · ${p.time.substring(0, 5)}'),
                          if (p.note != null && p.note!.isNotEmpty)
                            Text(p.note!,
                                style: t.bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              tooltip: 'تعديل',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _editPayment(p)),
                          IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deletePayment(p)),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}