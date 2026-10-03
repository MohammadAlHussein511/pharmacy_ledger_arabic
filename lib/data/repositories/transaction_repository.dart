import 'package:sqflite/sqflite.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../domain/validation.dart';
import '../models/ledger_transaction.dart';

class TransactionFilter {
  const TransactionFilter({
    this.query,
    this.type,
    this.from,
    this.to,
    this.currency,
    this.warehouseId,
  });

  /// Matches warehouse name or invoice number.
  final String? query;
  final TransactionType? type;
  final DateTime? from;
  final DateTime? to;
  final Currency? currency;
  final int? warehouseId;
}

class TransactionRepository {
  TransactionRepository(this._db, {this.onChanged, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final void Function()? onChanged;
  final DateTime Function() _clock;

  static const _select = '''
    SELECT t.*, w.name AS warehouse_name
    FROM transactions t
    LEFT JOIN warehouses w ON w.id = t.warehouse_id
  ''';

  Future<LedgerTransaction> insert(LedgerTransaction tx) async {
    Validators.validateTransaction(tx);
    final now = _clock().toIso8601String();
    final id = await _db.transaction<int>((txn) async {
      if (tx.isPayment) await _ensureWarehouse(txn, tx.warehouseId!);
      return txn.insert('transactions', {
        ...tx.toRow(),
        'created_at': now,
        'updated_at': now,
      });
    });
    onChanged?.call();
    return (await byId(id))!;
  }

  Future<void> update(LedgerTransaction tx) async {
    if (tx.id == null) throw ArgumentError('Cannot update a transaction without id');
    Validators.validateTransaction(tx);
    await _db.transaction((txn) async {
      if (tx.isPayment) await _ensureWarehouse(txn, tx.warehouseId!);
      final n = await txn.update(
        'transactions',
        {...tx.toRow(), 'updated_at': _clock().toIso8601String()},
        where: 'id = ?',
        whereArgs: [tx.id],
      );
      if (n != 1) throw const ValidationException('This transaction no longer exists.');
    });
    onChanged?.call();
  }

  Future<void> delete(int id) async {
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    onChanged?.call();
  }

  Future<LedgerTransaction?> byId(int id) async {
    final rows = await _db.rawQuery('$_select WHERE t.id = ? LIMIT 1', [id]);
    return rows.isEmpty ? null : LedgerTransaction.fromMap(rows.first);
  }

  /// All transactions of one day (a single day is always small).
  Future<List<LedgerTransaction>> forDay(DateTime day, {TransactionType? type}) async {
    final args = <Object?>[Dates.key(day)];
    var where = 't.transaction_date = ?';
    if (type != null) {
      where += ' AND t.type = ?';
      args.add(type.code);
    }
    final rows = await _db.rawQuery(
        '$_select WHERE $where ORDER BY t.transaction_time ASC, t.id ASC', args);
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  /// Paginated search, newest first.
  Future<List<LedgerTransaction>> search(
    TransactionFilter f, {
    int limit = 50,
    int offset = 0,
  }) async {
    final (where, args) = _where(f);
    final rows = await _db.rawQuery(
      '$_select $where ORDER BY t.transaction_date DESC, t.transaction_time DESC, t.id DESC '
      'LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  /// Per-currency totals of everything matching [f] (never combined).
  Future<Map<Currency, int>> totalsByCurrency(TransactionFilter f) async {
    final (where, args) = _where(f);
    final rows = await _db.rawQuery('''
      SELECT t.currency AS currency, SUM(t.amount_minor) AS total
      FROM transactions t LEFT JOIN warehouses w ON w.id = t.warehouse_id
      $where GROUP BY t.currency
    ''', args);
    return {
      for (final r in rows) Currency.fromCode(r['currency'] as String): r['total'] as int,
    };
  }

  (String, List<Object?>) _where(TransactionFilter f) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (f.type != null) {
      clauses.add('t.type = ?');
      args.add(f.type!.code);
    }
    if (f.from != null) {
      clauses.add('t.transaction_date >= ?');
      args.add(Dates.key(f.from!));
    }
    if (f.to != null) {
      clauses.add('t.transaction_date <= ?');
      args.add(Dates.key(f.to!));
    }
    if (f.currency != null) {
      clauses.add('t.currency = ?');
      args.add(f.currency!.code);
    }
    if (f.warehouseId != null) {
      clauses.add('t.warehouse_id = ?');
      args.add(f.warehouseId);
    }
    final q = f.query?.trim().toLowerCase() ?? '';
    if (q.isNotEmpty) {
      final like = '%${_escapeLike(q)}%';
      clauses.add("(w.name_key LIKE ? ESCAPE '\\' OR LOWER(t.invoice_number) LIKE ? ESCAPE '\\')");
      args
        ..add(like)
        ..add(like);
    }
    return (clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', args);
  }

  Future<void> _ensureWarehouse(Transaction txn, int warehouseId) async {
    final r = await txn.query('warehouses',
        columns: ['id'], where: 'id = ?', whereArgs: [warehouseId], limit: 1);
    if (r.isEmpty) throw const ValidationException(Messages.selectWarehouse);
  }

  static String _escapeLike(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
}
