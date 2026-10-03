import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_ledger/backup/backup_service.dart';
import 'package:pharmacy_ledger/core/currency.dart';
import 'package:pharmacy_ledger/data/models/ledger_transaction.dart';
import 'package:pharmacy_ledger/data/repositories/transaction_repository.dart';
import 'package:pharmacy_ledger/data/repositories/warehouse_repository.dart';
import 'package:pharmacy_ledger/domain/report_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  late Database db;
  late BackupService backup;
  late TransactionRepository txs;
  late WarehouseRepository whs;
  late ReportService reports;
  final day = DateTime(2026, 9, 12);

  setUp(() async {
    db = await openTestDb();
    backup = BackupService(db, kdfIterations: 1000);
    txs = TransactionRepository(db);
    whs = WarehouseRepository(db);
    reports = ReportService(db);
  });

  tearDown(() async => db.close());

  Future<void> seed() async {
    final w = await whs.create('Al-Shifa Pharma');
    await txs.insert(LedgerTransaction.newSale(amountMinor: 125000, day: day, now: day));
    await txs.insert(LedgerTransaction.newPayment(
        amountMinor: 20000,
        currency: Currency.usDollar,
        warehouseId: w.id!,
        invoiceNumber: 'INV-9',
        note: 'Monthly order',
        day: day,
        now: day));
  }

  test('create backup and restore it (replaces current data)', () async {
    await seed();
    final bytes = await backup.createBackup();
    // Change data after the backup.
    await txs.insert(LedgerTransaction.newSale(amountMinor: 999900, day: day, now: day));
    expect((await reports.day(day)).salesMinor, 125000 + 999900);

    final preview = await backup.inspect(bytes);
    expect(preview.transactionCount, 2);
    expect(preview.warehouseCount, 1);
    expect(preview.encrypted, isFalse);
    await backup.restore(preview);

    final s = await reports.day(day);
    expect(s.salesMinor, 125000);
    expect(s.payment(Currency.usDollar), 20000);
    final p = (await txs.forDay(day, type: TransactionType.payment)).single;
    expect(p.invoiceNumber, 'INV-9');
    expect(p.warehouseName, 'Al-Shifa Pharma');
  });

  test('encrypted backup requires the right password', () async {
    await seed();
    final bytes = await backup.createBackup(password: 'secret123');
    expect(utf8.decode(bytes).contains('Al-Shifa'), isFalse, reason: 'contents are encrypted');
    expect(() => backup.inspect(bytes), throwsA(isA<BackupPasswordRequired>()));
    expect(
      () => backup.inspect(bytes, password: 'wrong'),
      throwsA(isA<BackupException>()
          .having((e) => e.message, 'message', BackupMessages.wrongPassword)),
    );
    final preview = await backup.inspect(bytes, password: 'secret123');
    expect(preview.transactionCount, 2);
  });

  test('rejects files that are not backups', () async {
    for (final bad in ['hello', '{}', '[]', '{"format":"other"}']) {
      expect(() => backup.inspect(utf8.encode(bad)), throwsA(isA<BackupException>()), reason: bad);
    }
  });

  test('rejects a tampered backup (checksum mismatch)', () async {
    await seed();
    final env = jsonDecode(utf8.decode(await backup.createBackup())) as Map<String, dynamic>;
    ((env['data'] as Map)['transactions'] as List).first['amount_minor'] = 1;
    expect(
      () => backup.inspect(utf8.encode(jsonEncode(env))),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', BackupMessages.corrupted)),
    );
  });

  test('rejects structurally invalid rows even with a valid checksum', () async {
    Future<void> expectRejected(Map<String, Object?> tx) async {
      final data = {
        'warehouses': <Object>[],
        'transactions': [tx],
      };
      final env = {
        'format': BackupService.format,
        'format_version': 1,
        'checksum_sha256': _sha(jsonEncode(data)),
        'encrypted': false,
        'data': data,
      };
      await expectLater(backup.inspect(utf8.encode(jsonEncode(env))), throwsA(isA<BackupException>()));
    }

    final ts = DateTime(2026).toIso8601String();
    final base = {
      'id': 1, 'type': 'SALE', 'amount_minor': 100, 'currency': 'TRY', 'warehouse_id': null,
      'invoice_number': null, 'note': null, 'transaction_date': '2026-09-01',
      'transaction_time': '10:00:00', 'created_at': ts, 'updated_at': ts,
    };
    await expectRejected({...base, 'currency': 'USD'}); // sale must be TRY
    await expectRejected({...base, 'amount_minor': -5});
    await expectRejected({...base, 'transaction_date': '2026-02-30'});
    await expectRejected({...base, 'type': 'PAYMENT', 'warehouse_id': 7}); // unknown warehouse
    await expectRejected({...base, 'type': 'REFUND'});
  });

  test('rejects backups from a newer app version', () async {
    final env = {'format': BackupService.format, 'format_version': 99, 'checksum_sha256': 'x'};
    expect(
      () => backup.inspect(utf8.encode(jsonEncode(env))),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', BackupMessages.newerVersion)),
    );
  });

  test('a failed restore leaves current data untouched', () async {
    await seed();
    final before = await reports.day(day);
    final ts = DateTime(2026).toIso8601String();
    Map<String, Object?> sale(int id) => {
          'id': id, 'type': 'SALE', 'amount_minor': 100, 'currency': 'TRY',
          'warehouse_id': null, 'invoice_number': null, 'note': null,
          'transaction_date': '2026-09-12', 'transaction_time': '10:00:00',
          'created_at': ts, 'updated_at': ts,
        };
    // Duplicate primary key forces a failure halfway through the restore.
    final broken = BackupPreview(
      createdAt: DateTime(2026),
      appVersion: '1.0.0',
      encrypted: false,
      warehouses: const [],
      transactions: [sale(1), sale(1)],
    );
    await expectLater(backup.restore(broken), throwsA(isA<BackupException>()));
    expect(await reports.day(day), before);
    expect((await whs.list()).single.name, 'Al-Shifa Pharma');
  });
}

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();
