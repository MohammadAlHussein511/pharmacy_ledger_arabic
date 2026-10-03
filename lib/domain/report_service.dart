import 'package:sqflite/sqflite.dart';

import '../core/currency.dart';
import '../core/dates.dart';
import 'period_summary.dart';

class DashboardData {
  const DashboardData({
    required this.today,
    required this.week,
    required this.month,
    required this.year,
    required this.todayDate,
    required this.currentWeek,
  });

  final PeriodSummary today;
  final PeriodSummary week;
  final PeriodSummary month;
  final PeriodSummary year;
  final DateTime todayDate;
  final MonthWeek currentWeek;
}

class WarehouseTotals {
  const WarehouseTotals({required this.paymentCount, required this.totals});
  final int paymentCount;
  final Map<Currency, int> totals;
  int total(Currency c) => totals[c] ?? 0;
}

/// Report / calculation layer. Every number is computed on demand from the
/// transactions table with indexed GROUP BY queries, so edits and deletes of
/// historical records are reflected everywhere automatically.
class ReportService {
  ReportService(this._db);

  final Database _db;

  /// Totals for an inclusive date range.
  Future<PeriodSummary> summary(DateRange range) async {
    final rows = await _db.rawQuery('''
      SELECT type, currency, SUM(amount_minor) AS total, COUNT(*) AS cnt
      FROM transactions
      WHERE transaction_date BETWEEN ? AND ?
      GROUP BY type, currency
    ''', [range.startKey, range.endKey]);
    final b = SummaryBuilder();
    for (final r in rows) {
      b.addRow(r['type'] as String, r['currency'] as String, r['total'] as int, r['cnt'] as int);
    }
    return b.build();
  }

  Future<PeriodSummary> day(DateTime d) => summary(Dates.dayRange(d));
  Future<PeriodSummary> week(MonthWeek w) => summary(w.range);
  Future<PeriodSummary> month(int year, int month) => summary(Dates.monthRange(year, month));
  Future<PeriodSummary> year(int year) => summary(Dates.yearRange(year));

  /// One summary per day that has data, keyed by "yyyy-MM-dd".
  Future<Map<String, PeriodSummary>> dailyBreakdown(DateRange range) async {
    final rows = await _db.rawQuery('''
      SELECT transaction_date AS d, type, currency, SUM(amount_minor) AS total, COUNT(*) AS cnt
      FROM transactions
      WHERE transaction_date BETWEEN ? AND ?
      GROUP BY transaction_date, type, currency
    ''', [range.startKey, range.endKey]);
    final builders = <String, SummaryBuilder>{};
    for (final r in rows) {
      builders.putIfAbsent(r['d'] as String, SummaryBuilder.new).addRow(
          r['type'] as String, r['currency'] as String, r['total'] as int, r['cnt'] as int);
    }
    return builders.map((k, v) => MapEntry(k, v.build()));
  }

  /// Monthly summaries of a year, keyed by month number 1..12 (all 12 present).
  Future<Map<int, PeriodSummary>> monthlyBreakdown(int year) async {
    final range = Dates.yearRange(year);
    final rows = await _db.rawQuery('''
      SELECT CAST(substr(transaction_date, 6, 2) AS INTEGER) AS m, type, currency,
             SUM(amount_minor) AS total, COUNT(*) AS cnt
      FROM transactions
      WHERE transaction_date BETWEEN ? AND ?
      GROUP BY m, type, currency
    ''', [range.startKey, range.endKey]);
    final builders = {for (var m = 1; m <= 12; m++) m: SummaryBuilder()};
    for (final r in rows) {
      builders[r['m'] as int]!.addRow(
          r['type'] as String, r['currency'] as String, r['total'] as int, r['cnt'] as int);
    }
    return builders.map((k, v) => MapEntry(k, v.build()));
  }

  /// Weekly summaries of a month, derived from the daily breakdown.
  Future<List<(MonthWeek, PeriodSummary)>> weeklyBreakdown(int year, int month) async {
    final daily = await dailyBreakdown(Dates.monthRange(year, month));
    return [
      for (final w in Dates.weeksOfMonth(year, month))
        (
          w,
          PeriodSummary.sum(w.range.days
              .map((d) => daily[Dates.key(d)])
              .whereType<PeriodSummary>()),
        ),
    ];
  }

  Future<DashboardData> dashboard(DateTime now) async {
    final today = Dates.dateOnly(now);
    final week = Dates.weekContaining(today);
    final results = await Future.wait([
      day(today),
      summary(week.range),
      month(today.year, today.month),
      year(today.year),
    ]);
    return DashboardData(
      today: results[0],
      week: results[1],
      month: results[2],
      year: results[3],
      todayDate: today,
      currentWeek: week,
    );
  }

  Future<WarehouseTotals> warehouseTotals(int warehouseId) async {
    final rows = await _db.rawQuery('''
      SELECT currency, SUM(amount_minor) AS total, COUNT(*) AS cnt
      FROM transactions
      WHERE warehouse_id = ? AND type = 'PAYMENT'
      GROUP BY currency
    ''', [warehouseId]);
    var count = 0;
    final totals = <Currency, int>{};
    for (final r in rows) {
      totals[Currency.fromCode(r['currency'] as String)] = r['total'] as int;
      count += r['cnt'] as int;
    }
    return WarehouseTotals(paymentCount: count, totals: totals);
  }

  /// Years available in the year selector: every year with data plus the current year.
  Future<List<int>> availableYears(DateTime now) async {
    final r = await _db.rawQuery(
        'SELECT MIN(transaction_date) AS mn, MAX(transaction_date) AS mx FROM transactions');
    var first = now.year;
    var last = now.year;
    final mn = r.first['mn'] as String?;
    final mx = r.first['mx'] as String?;
    if (mn != null) {
      final y = int.parse(mn.substring(0, 4));
      if (y < first) first = y;
    }
    if (mx != null) {
      final y = int.parse(mx.substring(0, 4));
      if (y > last) last = y;
    }
    return [for (var y = last; y >= first; y--) y];
  }
}
