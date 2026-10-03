import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_ledger/core/currency.dart';
import 'package:pharmacy_ledger/core/dates.dart';
import 'package:pharmacy_ledger/data/models/ledger_transaction.dart';
import 'package:pharmacy_ledger/data/repositories/transaction_repository.dart';
import 'package:pharmacy_ledger/data/repositories/warehouse_repository.dart';
import 'package:pharmacy_ledger/domain/period_summary.dart';
import 'package:pharmacy_ledger/domain/report_service.dart';
import 'package:pharmacy_ledger/domain/validation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

const tryC = Currency.turkishLira;
const usd = Currency.usDollar;
const syp = Currency.syrianPound;

void main() {
  late Database db;
  late WarehouseRepository warehouses;
  late TransactionRepository txs;
  late ReportService reports;
  var changes = 0;
  final now = DateTime(2026, 9, 29, 9, 50);

  setUp(() async {
    db = await openTestDb();
    changes = 0;
    warehouses = WarehouseRepository(db, onChanged: () => changes++, clock: () => now);
    txs = TransactionRepository(db, onChanged: () => changes++, clock: () => now);
    reports = ReportService(db);
  });

  tearDown(() async => db.close());

  Future<LedgerTransaction> sale(DateTime day, int major) => txs.insert(
      LedgerTransaction.newSale(amountMinor: major * 100, day: day, now: now));

  Future<LedgerTransaction> pay(DateTime day, int major, Currency c, int warehouseId,
          {String? invoice}) =>
      txs.insert(LedgerTransaction.newPayment(
          amountMinor: major * 100,
          currency: c,
          warehouseId: warehouseId,
          invoiceNumber: invoice,
          day: day,
          now: now));

  group('Transactions', () {
    test('add sale: always TRY, no warehouse, time recorded', () async {
      final s = await sale(DateTime(2026, 9, 29), 850);
      expect(s.currency, tryC);
      expect(s.warehouseId, isNull);
      expect(s.time, '09:50:00');
      expect(s.date, '2026-09-29');
      expect(changes, 1);
    });

    test('add payment in each currency', () async {
      final w = await warehouses.create('ABC Pharma');
      for (final c in Currency.values) {
        final p = await pay(DateTime(2026, 9, 29), 250, c, w.id!);
        expect(p.currency, c);
        expect(p.warehouseName, 'ABC Pharma');
      }
    });

    test('edit sale and payment', () async {
      final w = await warehouses.create('ABC Pharma');
      final w2 = await warehouses.create('Al-Shifa Pharma');
      final s = await sale(DateTime(2026, 9, 5), 1000);
      await txs.update(s.copyWith(amountMinor: 150000));
      expect((await txs.byId(s.id!))!.amountMinor, 150000);

      final p = await pay(DateTime(2026, 9, 5), 100, usd, w.id!);
      await txs.update(p.copyWith(amountMinor: 20000, currency: syp, warehouseId: w2.id));
      final edited = (await txs.byId(p.id!))!;
      expect(edited.currency, syp);
      expect(edited.warehouseName, 'Al-Shifa Pharma');
    });

    test('delete sale and payment', () async {
      final w = await warehouses.create('ABC Pharma');
      final s = await sale(DateTime(2026, 9, 5), 1000);
      final p = await pay(DateTime(2026, 9, 5), 100, usd, w.id!);
      await txs.delete(s.id!);
      await txs.delete(p.id!);
      expect(await txs.forDay(DateTime(2026, 9, 5)), isEmpty);
      expect((await reports.day(DateTime(2026, 9, 5))).isEmpty, isTrue);
    });

    test('validation: zero, negative, payment without warehouse', () async {
      expect(() => txs.insert(LedgerTransaction.newSale(amountMinor: 0, day: now, now: now)),
          throwsA(isA<ValidationException>()));
      expect(() => txs.insert(LedgerTransaction.newSale(amountMinor: -100, day: now, now: now)),
          throwsA(isA<ValidationException>()));
      expect(
        () => txs.insert(LedgerTransaction(
            type: TransactionType.payment,
            amountMinor: 100,
            currency: usd,
            date: '2026-09-29',
            time: '10:00:00')),
        throwsA(isA<ValidationException>().having((e) => e.message, 'msg', Messages.selectWarehouse)),
      );
      expect(
        () => pay(DateTime(2026, 9, 29), 10, usd, 9999),
        throwsA(isA<ValidationException>()),
        reason: 'unknown warehouse',
      );
    });

    test('database itself rejects a non-TRY sale (defense in depth)', () async {
      expect(
        () => db.insert('transactions', {
          'type': 'SALE',
          'amount_minor': 100,
          'currency': 'USD',
          'transaction_date': '2026-09-29',
          'transaction_time': '10:00:00',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('Reports', () {
    test('Section 54 financial calculation test (never combines currencies)', () async {
      final w = await warehouses.create('ABC Pharma');
      await sale(DateTime(2026, 9, 1), 1000);
      await pay(DateTime(2026, 9, 1), 100, usd, w.id!);
      await sale(DateTime(2026, 9, 2), 2000);
      await pay(DateTime(2026, 9, 2), 300, tryC, w.id!);
      await sale(DateTime(2026, 9, 3), 1500);
      await pay(DateTime(2026, 9, 3), 50000, syp, w.id!);

      void expectTotals(PeriodSummary s) {
        expect(s.salesMinor, 450000);
        expect(s.payment(tryC), 30000);
        expect(s.payment(usd), 10000);
        expect(s.payment(syp), 5000000);
        expect(s.payments.length, 3, reason: 'one entry per currency, no combined total');
      }

      expectTotals(await reports.summary(DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 3))));
      expectTotals(await reports.week(Dates.weeksOfMonth(2026, 9).first));
      expectTotals(await reports.month(2026, 9));
      expectTotals(await reports.year(2026));
      expectTotals((await reports.monthlyBreakdown(2026))[9]!);
      final weekly = await reports.weeklyBreakdown(2026, 9);
      expectTotals(weekly.first.$2);
      expect(weekly[1].$2.isEmpty, isTrue);

      final daily = await reports.dailyBreakdown(Dates.monthRange(2026, 9));
      expect(daily['2026-09-01']!.salesMinor, 100000);
      expect(daily['2026-09-01']!.payment(usd), 10000);
      expect(daily['2026-09-02']!.payment(tryC), 30000);
      expect(daily['2026-09-03']!.payment(syp), 5000000);
    });

    test('weekly sales 500 + 700 + 900 = 2,100 TRY', () async {
      await sale(DateTime(2026, 9, 8), 500);
      await sale(DateTime(2026, 9, 9), 700);
      await sale(DateTime(2026, 9, 10), 900);
      expect((await reports.week(Dates.weeksOfMonth(2026, 9)[1])).salesMinor, 210000);
    });

    test('editing a historical transaction updates day, week, month and year', () async {
      final s = await sale(DateTime(2026, 9, 5), 1000);
      await sale(DateTime(2026, 9, 20), 400);
      await txs.update(s.copyWith(amountMinor: 150000));
      expect((await reports.day(DateTime(2026, 9, 5))).salesMinor, 150000);
      expect((await reports.week(Dates.weekContaining(DateTime(2026, 9, 5)))).salesMinor, 150000);
      expect((await reports.month(2026, 9)).salesMinor, 190000);
      expect((await reports.year(2026)).salesMinor, 190000);
    });

    test('month boundaries: 28, 29, 30, 31 day months', () async {
      await sale(DateTime(2026, 2, 28), 10);
      await sale(DateTime(2026, 3, 1), 20);
      await sale(DateTime(2028, 2, 29), 30);
      await sale(DateTime(2026, 4, 30), 40);
      await sale(DateTime(2026, 5, 31), 50);
      expect((await reports.month(2026, 2)).salesMinor, 1000);
      expect((await reports.month(2026, 3)).salesMinor, 2000);
      expect((await reports.month(2028, 2)).salesMinor, 3000);
      expect((await reports.week(Dates.weeksOfMonth(2028, 2).last)).salesMinor, 3000);
      expect((await reports.week(Dates.weeksOfMonth(2026, 4).last)).salesMinor, 4000);
      expect((await reports.week(Dates.weeksOfMonth(2026, 5).last)).salesMinor, 5000);
    });

    test('year boundaries: Dec 31 and Jan 1 go to the right year', () async {
      await sale(DateTime(2026, 1, 1), 100);
      await sale(DateTime(2026, 12, 31), 200);
      await sale(DateTime(2025, 12, 31), 999);
      await sale(DateTime(2027, 1, 1), 888);
      expect((await reports.year(2026)).salesMinor, 30000);
      final months = await reports.monthlyBreakdown(2026);
      expect(months.length, 12);
      expect(months[1]!.salesMinor, 10000);
      expect(months[12]!.salesMinor, 20000);
      expect(await reports.availableYears(DateTime(2026, 9, 29)), [2027, 2026, 2025]);
    });

    test('empty database gives zero totals and no crash', () async {
      final d = await reports.dashboard(now);
      expect(d.today.isEmpty && d.week.isEmpty && d.month.isEmpty && d.year.isEmpty, isTrue);
      expect(d.currentWeek.number, 5);
      expect(await reports.availableYears(now), [2026]);
    });

    test('dashboard uses today / reporting week / month / year', () async {
      await sale(DateTime(2026, 9, 29), 100); // today, week 5
      await sale(DateTime(2026, 9, 28), 200); // week 4
      await sale(DateTime(2026, 1, 15), 400); // same year
      final d = await reports.dashboard(now);
      expect(d.today.salesMinor, 10000);
      expect(d.week.salesMinor, 10000);
      expect(d.month.salesMinor, 30000);
      expect(d.year.salesMinor, 70000);
    });
  });

  group('Warehouses', () {
    test('names are normalized; duplicates are detected', () async {
      final a = await warehouses.create('  Al-Shifa   Pharma ');
      expect(a.name, 'Al-Shifa Pharma');
      expect(() => warehouses.create('al-shifa pharma'),
          throwsA(isA<DuplicateWarehouseException>()));
    });

    test('warehouse report totals per currency and payment history', () async {
      final w = await warehouses.create('Al-Shifa Pharma');
      await pay(DateTime(2026, 9, 1), 100, usd, w.id!, invoice: 'INV-1');
      await pay(DateTime(2026, 9, 2), 50, usd, w.id!);
      await pay(DateTime(2026, 9, 3), 500, tryC, w.id!);
      final t = await reports.warehouseTotals(w.id!);
      expect(t.paymentCount, 3);
      expect(t.total(usd), 15000);
      expect(t.total(tryC), 50000);
      expect(t.total(syp), 0);
      final history = await txs.search(TransactionFilter(warehouseId: w.id), limit: 2);
      expect(history.length, 2, reason: 'paginated');
      expect(history.first.date, '2026-09-03', reason: 'newest first');
    });

    test('search by warehouse name / invoice and filter by currency and date', () async {
      final a = await warehouses.create('Al-Shifa Pharma');
      final b = await warehouses.create('ABC Pharma');
      await pay(DateTime(2026, 9, 1), 100, usd, a.id!, invoice: 'INV-77');
      await pay(DateTime(2026, 9, 2), 200, syp, b.id!, invoice: 'X-1');
      await pay(DateTime(2026, 10, 2), 300, usd, b.id!);
      expect((await txs.search(const TransactionFilter(query: 'shifa'))).length, 1);
      expect((await txs.search(const TransactionFilter(query: 'inv-77'))).length, 1);
      expect((await txs.search(const TransactionFilter(currency: usd))).length, 2);
      expect(
          (await txs.search(TransactionFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30))))
              .length,
          2);
      expect(await txs.totalsByCurrency(TransactionFilter(warehouseId: b.id)),
          {syp: 20000, usd: 30000});
    });

    test('deactivation keeps history; used warehouses cannot be deleted', () async {
      final w = await warehouses.create('Old Supplier');
      await pay(DateTime(2026, 9, 1), 100, usd, w.id!);
      await warehouses.setActive(w.id!, false);
      expect((await warehouses.list()).any((x) => x.id == w.id), isFalse);
      expect((await warehouses.list(includeInactive: true)).any((x) => x.id == w.id), isTrue);
      expect((await reports.month(2026, 9)).payment(usd), 10000);
      expect(() => warehouses.deleteUnused(w.id!), throwsA(isA<WarehouseInUseException>()));
      // Re-adding the same name reactivates the original record.
      final again = await warehouses.create('old supplier');
      expect(again.id, w.id);
      expect(again.isActive, isTrue);
    });

    test('unused warehouse can be deleted', () async {
      final w = await warehouses.create('Typo Warehouse');
      await warehouses.deleteUnused(w.id!);
      expect(await warehouses.byId(w.id!), isNull);
    });
  });

  test('performance: 20,000 transactions aggregate quickly', () async {
    final w = await warehouses.create('Bulk');
    final batch = db.batch();
    final ts = now.toIso8601String();
    for (var i = 0; i < 20000; i++) {
      final d = DateTime(2026, 1, 1).add(Duration(days: i % 365));
      final isSale = i.isEven;
      batch.insert('transactions', {
        'type': isSale ? 'SALE' : 'PAYMENT',
        'amount_minor': 100 + i,
        'currency': isSale ? 'TRY' : Currency.values[i % 3].code,
        'warehouse_id': isSale ? null : w.id,
        'transaction_date': Dates.key(d),
        'transaction_time': '12:00:00',
        'created_at': ts,
        'updated_at': ts,
      });
    }
    await batch.commit(noResult: true);
    final sw = Stopwatch()..start();
    final months = await reports.monthlyBreakdown(2026);
    await reports.dashboard(now);
    sw.stop();
    expect(PeriodSummary.sum(months.values).saleCount, 10000);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
