import 'package:sqflite/sqflite.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../data/models/ledger_transaction.dart';
import '../../domain/validation.dart';

class TransactionRepository {
  TransactionRepository(this._db, {required this.onChanged});

  final Database _db;
  final VoidCallback onChanged;

  Future<List<LedgerTransaction>> all() async {
    final rows = await _db.query('transactions', orderBy: 'transaction_date DESC, transaction_time DESC, id DESC');
    return rows.map(_fromRow).toList();
  }

  Future<List<LedgerTransaction>> onDay(DateTime day) async {
    final key = Dates.key(day);
    final rows = await _db.query(
      'transactions',
      where: 'transaction_date = ?',
      whereArgs: [key],
      orderBy: 'transaction_time DESC, id DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<LedgerTransaction>> paymentsForWarehouse(int warehouseId) async {
    final rows = await _db.query(
      'transactions',
      where: 'type = ? AND warehouse_id = ?',
      whereArgs: ['PAYMENT', warehouseId],
      orderBy: 'transaction_date DESC, transaction_time DESC, id DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<int> insert(LedgerTransaction tx) async {
    _validate(tx);
    final now = DateTime.now().toIso8601String();
    final id = await _db.insert('transactions', {
      'type': tx.type.name.toUpperCase(),
      'amount_minor': tx.amountMinor,
      'currency': tx.currency.code,
      'warehouse_id': tx.warehouseId,
      'invoice_number': tx.invoiceNumber,
      'note': tx.note,
      'transaction_date': tx.date,
      'transaction_time': tx.time,
      'created_at': now,
      'updated_at': now,
    });
    onChanged();
    return id;
  }

  Future<void> update(LedgerTransaction tx) async {
    if (tx.id == null) throw ArgumentError('Cannot update unsaved transaction');
    _validate(tx);
    final now = DateTime.now().toIso8601String();
    await _db.update(
      'transactions',
      {
        'type': tx.type.name.toUpperCase(),
        'amount_minor': tx.amountMinor,
        'currency': tx.currency.code,
        'warehouse_id': tx.warehouseId,
        'invoice_number': tx.invoiceNumber,
        'note': tx.note,
        'transaction_date': tx.date,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [tx.id],
    );
    
    // [جديد] تحديث invoice_payments المرتبطة
    if (tx.type == TransactionType.payment) {
      await _db.update(
        'invoice_payments',
        {
          'amount_minor': tx.amountMinor,
          'currency_paid': tx.currency.code,
          'updated_at': now,
        },
        where: 'note = ? AND invoice_id IN (SELECT id FROM invoices WHERE warehouse_id = ?)',
        whereArgs: ['خصم تلقائي من دفعة', tx.warehouseId],
      );
    }
    
    onChanged();
  }

  Future<void> delete(int id) async {
    // [جديد] حذف invoice_payments المرتبطة قبل حذف الـ transaction
    final tx = await _db.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (tx.isNotEmpty) {
      final row = tx.first;
      if (row['type'] == 'PAYMENT') {
        final warehouseId = row['warehouse_id'] as int?;
        final amountMinor = row['amount_minor'] as int;
        final currency = row['currency'] as String;
        
        // حذف الدفعات المرتبطة بنفس القيمة والعملة
        if (warehouseId != null) {
          await _db.delete(
            'invoice_payments',
            where: 'amount_minor = ? AND currency_paid = ? AND note = ? '
                'AND invoice_id IN (SELECT id FROM invoices WHERE warehouse_id = ?)',
            whereArgs: [amountMinor, currency, 'خصم تلقائي من دفعة', warehouseId],
          );
        }
      }
    }
    
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    onChanged();
  }

  void _validate(LedgerTransaction tx) {
    if (tx.amountMinor <= 0) throw const ValidationException('Amount must be positive');
    if (tx.type == TransactionType.sale) {
      if (tx.currency != Currency.salesCurrency) {
        throw const ValidationException('Sales must be in TRY');
      }
      if (tx.warehouseId != null) {
        throw const ValidationException('Sales cannot be linked to warehouses');
      }
    } else {
      if (tx.warehouseId == null) {
        throw const ValidationException('Payments must be linked to a warehouse');
      }
    }
  }

  LedgerTransaction _fromRow(Map<String, dynamic> row) {
    final type = row['type'] == 'SALE' ? TransactionType.sale : TransactionType.payment;
    return LedgerTransaction(
      id: row['id'] as int,
      type: type,
      amountMinor: row['amount_minor'] as int,
      currency: Currency.fromCode(row['currency'] as String),
      warehouseId: row['warehouse_id'] as int?,
      invoiceNumber: row['invoice_number'] as String?,
      note: row['note'] as String?,
      date: row['transaction_date'] as String,
      time: row['transaction_time'] as String,
    );
  }
}

typedef VoidCallback = void Function();