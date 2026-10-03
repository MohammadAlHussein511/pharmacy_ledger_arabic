import 'package:sqflite/sqflite.dart';

import '../../domain/validation.dart';
import '../models/warehouse.dart';

class DuplicateWarehouseException implements Exception {
  const DuplicateWarehouseException(this.existing);
  final Warehouse existing;
  @override
  String toString() => Messages.warehouseExists;
}

class WarehouseInUseException implements Exception {
  const WarehouseInUseException();
  @override
  String toString() =>
      'This warehouse has payment history and cannot be deleted. Deactivate it instead.';
}

class WarehouseSummaryRow {
  const WarehouseSummaryRow(this.warehouse, this.paymentCount);
  final Warehouse warehouse;
  final int paymentCount;
}

class WarehouseRepository {
  WarehouseRepository(this._db, {this.onChanged, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final void Function()? onChanged;
  final DateTime Function() _clock;

  Future<List<Warehouse>> list({bool includeInactive = false}) async {
    final rows = await _db.query(
      'warehouses',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'is_active DESC, name_key ASC',
    );
    return rows.map(Warehouse.fromMap).toList();
  }

  /// Warehouses with their number of payments, filtered by an optional query.
  Future<List<WarehouseSummaryRow>> listWithCounts({
    bool includeInactive = true,
    String? query,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeInactive) where.add('w.is_active = 1');
    final q = query?.trim().toLowerCase() ?? '';
    if (q.isNotEmpty) {
      where.add("w.name_key LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(q)}%');
    }
    final rows = await _db.rawQuery('''
      SELECT w.*, (SELECT COUNT(*) FROM transactions t
                   WHERE t.warehouse_id = w.id AND t.type = 'PAYMENT') AS payment_count
      FROM warehouses w
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY w.is_active DESC, w.name_key ASC
    ''', args);
    return rows
        .map((r) => WarehouseSummaryRow(Warehouse.fromMap(r), r['payment_count'] as int))
        .toList();
  }

  Future<Warehouse?> byId(int id) async {
    final rows = await _db.query('warehouses', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Warehouse.fromMap(rows.first);
  }

  Future<Warehouse?> byName(String name) async {
    final rows = await _db.query('warehouses',
        where: 'name_key = ?', whereArgs: [Validators.warehouseKey(name)], limit: 1);
    return rows.isEmpty ? null : Warehouse.fromMap(rows.first);
  }

  /// Creates a warehouse. If a deactivated warehouse with the same name
  /// exists it is reactivated (keeps its history). If an active one exists,
  /// throws [DuplicateWarehouseException] carrying it so the UI can select it.
  Future<Warehouse> create(String rawName) async {
    final error = Validators.warehouseName(rawName);
    if (error != null) throw ValidationException(error);
    final name = Validators.normalizeWarehouseName(rawName);
    final existing = await byName(name);
    if (existing != null) {
      if (existing.isActive) throw DuplicateWarehouseException(existing);
      await setActive(existing.id!, true);
      return (await byId(existing.id!))!;
    }
    final now = _clock().toIso8601String();
    try {
      final id = await _db.insert('warehouses', {
        'name': name,
        'name_key': Validators.warehouseKey(name),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      onChanged?.call();
      return (await byId(id))!;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        final dup = await byName(name);
        if (dup != null) throw DuplicateWarehouseException(dup);
      }
      rethrow;
    }
  }

  Future<void> rename(int id, String rawName) async {
    final error = Validators.warehouseName(rawName);
    if (error != null) throw ValidationException(error);
    final name = Validators.normalizeWarehouseName(rawName);
    final existing = await byName(name);
    if (existing != null && existing.id != id) throw DuplicateWarehouseException(existing);
    await _db.update(
      'warehouses',
      {
        'name': name,
        'name_key': Validators.warehouseKey(name),
        'updated_at': _clock().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    onChanged?.call();
  }

  Future<void> setActive(int id, bool active) async {
    await _db.update(
      'warehouses',
      {'is_active': active ? 1 : 0, 'updated_at': _clock().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    onChanged?.call();
  }

  Future<int> transactionCount(int id) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions WHERE warehouse_id = ?', [id]);
    return r.first['c'] as int;
  }

  /// Hard delete is only allowed for warehouses that were never used.
  /// Historical identity is always preserved (the FK is ON DELETE RESTRICT too).
  Future<void> deleteUnused(int id) async {
    await _db.transaction((txn) async {
      final r = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM transactions WHERE warehouse_id = ?', [id]);
      if ((r.first['c'] as int) > 0) throw const WarehouseInUseException();
      await txn.delete('warehouses', where: 'id = ?', whereArgs: [id]);
    });
    onChanged?.call();
  }

  static String _escapeLike(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
}
