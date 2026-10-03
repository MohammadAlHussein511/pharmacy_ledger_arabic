import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_ledger/core/dates.dart';

void main() {
  List<String> labels(int y, int m) =>
      Dates.weeksOfMonth(y, m).map((w) => '${w.firstDay}-${w.lastDay}').toList();

  group('Monthly week structure (1-7, 8-14, 15-21, 22-28, 29-end)', () {
    test('28-day month has exactly 4 weeks (no empty 5th week)', () {
      expect(labels(2026, 2), ['1-7', '8-14', '15-21', '22-28']);
    });

    test('29-day leap February has week 5 = day 29', () {
      expect(Dates.isLeapYear(2028), isTrue);
      expect(labels(2028, 2), ['1-7', '8-14', '15-21', '22-28', '29-29']);
      expect(Dates.weeksOfMonth(2028, 2).last.daysLabel, 'Day 29');
    });

    test('30-day month', () {
      expect(labels(2026, 9), ['1-7', '8-14', '15-21', '22-28', '29-30']);
    });

    test('31-day month', () {
      expect(labels(2026, 12), ['1-7', '8-14', '15-21', '22-28', '29-31']);
    });

    test('no day is ever lost', () {
      for (var y = 2024; y <= 2030; y++) {
        for (var m = 1; m <= 12; m++) {
          final days = Dates.weeksOfMonth(y, m).expand((w) => w.range.days).toList();
          expect(days.length, Dates.daysInMonth(y, m));
          expect(days.first, DateTime(y, m, 1));
          expect(days.last, DateTime(y, m, Dates.daysInMonth(y, m)));
        }
      }
    });

    test('weekContaining', () {
      expect(Dates.weekContaining(DateTime(2026, 9, 18)).number, 3);
      expect(Dates.weekContaining(DateTime(2026, 9, 29)).number, 5);
      expect(Dates.weekContaining(DateTime(2026, 9, 7)).number, 1);
      expect(Dates.weekContaining(DateTime(2026, 9, 8)).number, 2);
    });
  });

  group('Calendar rules', () {
    test('leap years', () {
      expect(Dates.isLeapYear(2024), isTrue);
      expect(Dates.isLeapYear(2026), isFalse);
      expect(Dates.isLeapYear(2100), isFalse);
      expect(Dates.isLeapYear(2000), isTrue);
      expect(Dates.daysInMonth(2024, 2), 29);
      expect(Dates.daysInMonth(2026, 2), 28);
    });

    test('year transitions', () {
      expect(Dates.addMonths(DateTime(2026, 12), 1), DateTime(2027, 1));
      expect(Dates.addMonths(DateTime(2026, 1), -1), DateTime(2025, 12));
      expect(Dates.yearRange(2026).startKey, '2026-01-01');
      expect(Dates.yearRange(2026).endKey, '2026-12-31');
      expect(Dates.monthRange(2026, 12).endKey, '2026-12-31');
    });

    test('date keys', () {
      expect(Dates.key(DateTime(2026, 9, 5, 23, 59)), '2026-09-05');
      expect(Dates.parseKey('2028-02-29'), DateTime(2028, 2, 29));
      expect(Dates.isValidKey('2026-02-29'), isFalse);
      expect(Dates.isValidKey('2026-13-01'), isFalse);
      expect(Dates.isValidTime('23:59:59'), isTrue);
      expect(Dates.isValidTime('24:00:00'), isFalse);
    });

    test('English display with Western digits', () {
      expect(Dates.fullDate(DateTime(2026, 9, 28)), 'Monday, September 28, 2026');
      expect(Dates.monthYear(DateTime(2026, 9)), 'September 2026');
    });
  });
}
