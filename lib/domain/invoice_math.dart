import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

class PayRow {
  PayRow({
    required this.id,
    required this.transactionId,
    required this.invoiceId,
    required this.amountMinor,
    required this.currencyPaid,
    required this.exchangeRate,
    required this.date,
    required this.time,
    required this.note,
  });
  final int id;
  final int? transactionId;
  final int invoiceId;
  final int amountMinor;
  final String currencyPaid;
  final double? exchangeRate;
  final String date;
  final String time;
  final String? note;
}

/// حسابات الفواتير الموحدة: كل شيء يُشتق لحظياً من الدفعات المخزنة.
class InvoiceMath {
  /// كل دفعات مستودع (عبر فواتيره) مرتبة زمنياً
  static Future<List<PayRow>> warehousePayments(Database db, int warehouseId) async {
    final rows = await db.rawQuery('''
      SELECT ip.* FROM invoice_payments ip
      JOIN invoices i ON i.id = ip.invoice_id
      WHERE i.warehouse_id = ?
      ORDER BY ip.payment_date ASC, ip.payment_time ASC, ip.id ASC
    ''', [warehouseId]);
    return [
      for (final r in rows)
        PayRow(
          id: r['id'] as int,
          transactionId: r['transaction_id'] as int?,
          invoiceId: r['invoice_id'] as int,
          amountMinor: r['amount_minor'] as int,
          currencyPaid: r['currency_paid'] as String,
          exchangeRate: (r['exchange_rate'] as num?)?.toDouble(),
          date: r['payment_date'] as String,
          time: r['payment_time'] as String,
          note: r['note'] as String?,
        ),
    ];
  }

  static int _toInvoiceCurrency(PayRow p, String invoiceCurrency) {
    if (p.currencyPaid == invoiceCurrency) return p.amountMinor;
    final r = p.exchangeRate;
    if (r == null || r <= 0) return 0;
    return (p.amountMinor / r).round();
  }

  /// FIFO مشتق: كم دُفع لكل فاتورة
  static Future<Map<int, int>> paidByInvoice(Database db, int warehouseId) async {
    final invs = await db.query('invoices',
        where: 'warehouse_id = ?',
        whereArgs: [warehouseId],
        orderBy: 'invoice_date ASC, id ASC');
    final pays = await warehousePayments(db, warehouseId);
    final result = <int, int>{};
    final currencies = {for (final i in invs) i['currency'] as String};
    for (final c in currencies) {
      int capacity = 0;
      for (final p in pays) {
        capacity += _toInvoiceCurrency(
            PayRow(
                id: p.id,
                transactionId: p.transactionId,
                invoiceId: p.invoiceId,
                amountMinor: p.amountMinor,
                currencyPaid: p.currencyPaid,
                exchangeRate: p.exchangeRate,
                date: p.date,
                time: p.time,
                note: p.note),
            c);
      }
      for (final i in invs) {
        if ((i['currency'] as String) != c) continue;
        if (capacity <= 0) break;
        final iid = i['id'] as int;
        final amt = i['amount_minor'] as int;
        final take = capacity < amt ? capacity : amt;
        result[iid] = (result[iid] ?? 0) + take;
        capacity -= take;
      }
    }
    return result;
  }

  /// الرصيد المتبقي الموحد لكل عملة على المستودع
  static Future<Map<String, int>> warehouseRemaining(
      Database db, int warehouseId) async {
    final invs = await db.query('invoices',
        where: 'warehouse_id = ?', whereArgs: [warehouseId]);
    final paid = await paidByInvoice(db, warehouseId);
    final remaining = <String, int>{};
    for (final i in invs) {
      final cur = i['currency'] as String;
      final amt = i['amount_minor'] as int;
      final p = paid[i['id'] as int] ?? 0;
      remaining[cur] = (remaining[cur] ?? 0) + (amt - p);
    }
    return remaining;
  }

  /// أول فاتورة مفتوحة للمستودع (لربط الدفعة بها)
  static Future<int?> firstOpenInvoice(Database db, int warehouseId) async {
    final invs = await db.query('invoices',
        where: 'warehouse_id = ?',
        whereArgs: [warehouseId],
        orderBy: 'invoice_date ASC, id ASC');
    if (invs.isEmpty) return null;
    final paid = await paidByInvoice(db, warehouseId);
    for (final i in invs) {
      final iid = i['id'] as int;
      if ((paid[iid] ?? 0) < (i['amount_minor'] as int)) return iid;
    }
    return invs.first['id'] as int;
  }
}

/// أيقونة العملة: رمز بدل ورقة النقد
Widget currencyAvatar(String code, {double radius = 20}) {
  final symbol = switch (code) {
    'USD' => '\$',
    'TRY' => '₺',
    'SYP' => 'L.S',
    _ => code,
  };
  return CircleAvatar(
    radius: radius,
    child: Text(symbol, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

String moneyText(int minor, String cur) =>
    '${(minor / 100).toStringAsFixed(2)} $cur';