import 'package:sqflite/sqflite.dart';
import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../data/models/ledger_transaction.dart';
import '../../domain/validation.dart';

class TransactionFilter {
  final TransactionType? type;
  final String? query;
  final DateTime? from;
  final DateTime? to;
  final Currency? currency;
  final int? warehouseId;

  const TransactionFilter({
    this.type,
    this.query,
    this.from,
    this.to,
    this.currency,
    this.warehouseId,
  });
}

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

  Future<List<LedgerTransaction>> search(TransactionFilter filter, {int limit = 50, int offset = 0}) async {
    final whereClauses = <String>[];
    final args = <dynamic>[];

    if (filter.type != null) {
      whereClauses.add('t.type = ?');
      args.add(filter.type!.code.toUpperCase());
    }
    if (filter.warehouseId != null) {
      whereClauses.add('t.warehouse_id = ?');
      args.add(filter.warehouseId);
    }
    if (filter.currency != null) {
      whereClauses.add('t.currency = ?');
      args.add(filter.currency!.code);
    }
    if (filter.from != null) {
      whereClauses.add('t.transaction_date >= ?');
      args.add(Dates.key(filter.from!));
    }
    if (filter.to != null) {
      whereClauses.add('t.transaction_date <= ?');
      args.add(Dates.key(filter.to!));
    }
    if (filter.query != null && filter.query!.isNotEmpty) {
      whereClauses.add('(t.invoice_number LIKE ? OR t.note LIKE ? OR w.name LIKE ?)');
      args.add('%${filter.query}%');
      args.add('%${filter.query}%');
      args.add('%${filter.query}%');
    }

    final whereStr = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    final sql = '''
      SELECT t.*, w.name as warehouse_name FROM transactions t
      LEFT JOIN warehouses w ON t.warehouse_id = w.id
      ${whereStr != null ? 'WHERE $whereStr' : ''}
      ORDER BY t.transaction_date DESC, t.transaction_time DESC, t.id DESC
      LIMIT ? OFFSET ?
    ''';
    args.add(limit);
    args.add(offset);

    final rows = await _db.rawQuery(sql, args);
    return rows.map(_fromRow).toList();
  }

  Future<Map<Currency, int>> totalsByCurrency(TransactionFilter filter) async {
    final whereClauses = <String>[];
    final args = <dynamic>[];

    if (filter.type != null) {
      whereClauses.add('t.type = ?');
      args.add(filter.type!.code.toUpperCase());
    }
    if (filter.warehouseId != null) {
      whereClauses.add('t.warehouse_id = ?');
      args.add(filter.warehouseId);
    }
    if (filter.currency != null) {
      whereClauses.add('t.currency = ?');
      args.add(filter.currency!.code);
    }
    if (filter.from != null) {
      whereClauses.add('t.transaction_date >= ?');
      args.add(Dates.key(filter.from!));
    }
    if (filter.to != null) {
      whereClauses.add('t.transaction_date <= ?');
      args.add(Dates.key(filter.to!));
    }
    if (filter.query != null && filter.query!.isNotEmpty) {
      whereClauses.add('(t.invoice_number LIKE ? OR t.note LIKE ? OR w.name LIKE ?)');
      args.add('%${filter.query}%');
      args.add('%${filter.query}%');
      args.add('%${filter.query}%');
    }

    final whereStr = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    final sql = '''
      SELECT t.currency, SUM(t.amount_minor) as total
      FROM transactions t
      LEFT JOIN warehouses w ON t.warehouse_id = w.id
      ${whereStr != null ? 'WHERE $whereStr' : ''}
      GROUP BY t.currency
    ''';

    final rows = await _db.rawQuery(sql, args);
    final totals = <Currency, int>{};
    for (final row in rows) {
      final c = Currency.fromCode(row['currency'] as String);
      totals[c] = (row['total'] as num).toInt();
    }
    return totals;
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

    // جديد: تحديث invoice_payments المرتبطة باستخدام transaction_id
    if (tx.type == TransactionType.payment) {
      await _db.update(
        'invoice_payments',
        {
          'amount_minor': tx.amountMinor,
          'currency_paid': tx.currency.code,
          'updated_at': now,
        },
        where: 'transaction_id = ?',
        whereArgs: [tx.id],
      );
    }

    onChanged();
  }

  Future<void> delete(int id) async {
    // جديد: حذف invoice_payments المرتبطة باستخدام transaction_id
    await _db.delete('invoice_payments', where: 'transaction_id = ?', whereArgs: [id]);
    
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
      warehouseName: row['warehouse_name'] as String?,
      invoiceNumber: row['invoice_number'] as String?,
      note: row['note'] as String?,
      date: row['transaction_date'] as String,
      time: row['transaction_time'] as String,
    );
  }
}

typedef VoidCallback = void Function();