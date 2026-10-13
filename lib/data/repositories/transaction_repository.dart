import 'package:sqflite/sqflite.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../data/models/ledger_transaction.dart';
import '../../domain/validation.dart';

class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.type,
    this.warehouseId,
    this.currency,
    this.from,
    this.to,
    DateTime? fromDate,
    DateTime? toDate,
  })  : _fromDate = from ?? fromDate,
        _toDate = to ?? toDate;

  final String query;
  final TransactionType? type;
  final int? warehouseId;
  final Currency? currency;
  final DateTime? from;
  final DateTime? to;
  final DateTime? _fromDate;
  final DateTime? _toDate;

  DateTime? get fromDate => from ?? _fromDate;
  DateTime? get toDate => to ?? _toDate;

  bool get isEmpty =>
      query.isEmpty &&
      type == null &&
      warehouseId == null &&
      currency == null &&
      fromDate == null &&
      toDate == null;
}

class TransactionRepository {
  TransactionRepository(this._db, {required this.onChanged});

  final Database _db;
  final void Function() onChanged;

  Future<List<LedgerTransaction>> all() async {
    final rows = await _db.query('transactions',
        orderBy: 'transaction_date DESC, transaction_time DESC, id DESC');
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

  Future<Map<Currency, int>> totalsByCurrency(TransactionFilter filter) async {
    final (where, args) = _buildWhere(filter);
    final sql = where.isEmpty
        ? 'SELECT currency, SUM(amount_minor) as total FROM transactions GROUP BY currency'
        : 'SELECT currency, SUM(amount_minor) as total FROM transactions WHERE $where GROUP BY currency';
    final rows = await _db.rawQuery(sql, args);
    final result = <Currency, int>{};
    for (final r in rows) {
      final cur = Currency.fromCode(r['currency'] as String);
      result[cur] = (r['total'] as num).toInt();
    }
    return result;
  }

  Future<List<LedgerTransaction>> search(
    TransactionFilter filter, {
    int limit = 50,
    int offset = 0,
  }) async {
    final (where, args) = _buildWhere(filter);
    final sql = where.isEmpty
        ? 'SELECT * FROM transactions ORDER BY transaction_date DESC, transaction_time DESC, id DESC LIMIT ? OFFSET ?'
        : 'SELECT * FROM transactions WHERE $where ORDER BY transaction_date DESC, transaction_time DESC, id DESC LIMIT ? OFFSET ?';
    final rows = await _db.rawQuery(sql, [...args, limit, offset]);
    return rows.map(_fromRow).toList();
  }

  (String, List<Object?>) _buildWhere(TransactionFilter f) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (f.query.isNotEmpty) {
      clauses.add('(invoice_number LIKE ? OR note LIKE ?)');
      final q = '%${f.query}%';
      args..add(q)..add(q);
    }
    if (f.type != null) {
      clauses.add('type = ?');
      args.add(f.type == TransactionType.sale ? 'SALE' : 'PAYMENT');
    }
    if (f.warehouseId != null) {
      clauses.add('warehouse_id = ?');
      args.add(f.warehouseId);
    }
    if (f.currency != null) {
      clauses.add('currency = ?');
      args.add(f.currency!.code);
    }
    if (f.fromDate != null) {
      clauses.add('transaction_date >= ?');
      args.add(Dates.key(f.fromDate!));
    }
    if (f.toDate != null) {
      clauses.add('transaction_date <= ?');
      args.add(Dates.key(f.toDate!));
    }
    return (clauses.join(' AND '), args);
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

  /// [نهائي] تعديل transaction + دفعته المرتبطة معاً (صف واحد لكل منهما)
  Future<void> update(LedgerTransaction tx) async {
    if (tx.id == null) throw ArgumentError('Cannot update unsaved transaction');
    _validate(tx);
    final now = DateTime.now().toIso8601String();

    await _db.transaction((txn) async {
      await txn.update(
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

      if (tx.type == TransactionType.payment) {
        await txn.update(
          'invoice_payments',
          {
            'amount_minor': tx.amountMinor,
            'currency_paid': tx.currency.code,
            'note': tx.note,
            'payment_date': tx.date,
            'updated_at': now,
          },
          where: 'transaction_id = ?',
          whereArgs: [tx.id],
        );
      }
    });

    onChanged();
  }

  /// [نهائي] حذف transaction + دفعته المرتبطة معاً
  Future<void> delete(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('invoice_payments',
          where: 'transaction_id = ?', whereArgs: [id]);
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
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