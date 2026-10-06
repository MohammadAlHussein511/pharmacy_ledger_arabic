import 'package:intl/intl.dart';

// [تم التعديل] - دالة عامة لتحويل الأرقام العربية الشرقية إلى غربية
String _westernDigits(String s) =>
    s.replaceAllMapped(
      RegExp('[\u0660-\u0669]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x0660 + 0x0030),
    );

/// Inclusive date range of calendar days.
class DateRange {
  DateRange(DateTime start, DateTime end)
      : start = Dates.dateOnly(start),
        end = Dates.dateOnly(end);

  final DateTime start;
  final DateTime end;

  String get startKey => Dates.key(start);
  String get endKey => Dates.key(end);

  bool contains(DateTime d) {
    final x = Dates.dateOnly(d);
    return !x.isBefore(start) && !x.isAfter(end);
  }

  /// Every day in the range, in order.
  List<DateTime> get days {
    final out = <DateTime>[];
    var d = start;
    while (!d.isAfter(end)) {
      out.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$startKey..$endKey';
}

/// A reporting week inside a month.
class MonthWeek {
  const MonthWeek({
    required this.year,
    required this.month,
    required this.number,
    required this.firstDay,
    required this.lastDay,
  });

  final int year;
  final int month;
  final int number;
  final int firstDay;
  final int lastDay;

  DateRange get range =>
      DateRange(DateTime(year, month, firstDay), DateTime(year, month, lastDay));

  String get title => 'الأسبوع $number';

  String get daysLabel =>
      firstDay == lastDay ? 'اليوم $firstDay' : 'الأيام $firstDay–$lastDay';

  String get longLabel =>
      '${_westernDigits(DateFormat('MMMM', 'ar').format(DateTime(year, month)))} $firstDay–$lastDay';

  @override
  bool operator ==(Object other) =>
      other is MonthWeek &&
      other.year == year &&
      other.month == month &&
      other.number == number;

  @override
  int get hashCode => Object.hash(year, month, number);
}

class Dates {
  Dates._();

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_2(d.month)}-${_2(d.day)}';

  static final RegExp _keyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d):([0-5]\d)$');

  static DateTime parseKey(String key) {
    final m = _keyPattern.firstMatch(key);
    if (m == null) throw FormatException('Invalid date: $key');
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final dt = DateTime(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) {
      throw FormatException('Invalid date: $key');
    }
    return dt;
  }

  static bool isValidKey(String key) {
    try {
      parseKey(key);
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool isValidTime(String time) => _timePattern.hasMatch(time);

  static String timeKey(DateTime d) => '${_2(d.hour)}:${_2(d.minute)}:${_2(d.second)}';

  static String shortTime(String timeKey) =>
      timeKey.length >= 5 ? timeKey.substring(0, 5) : timeKey;

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  static DateRange dayRange(DateTime d) => DateRange(d, d);

  static DateRange monthRange(int year, int month) =>
      DateRange(DateTime(year, month, 1), DateTime(year, month, daysInMonth(year, month)));

  static DateRange yearRange(int year) =>
      DateRange(DateTime(year, 1, 1), DateTime(year, 12, 31));

  static List<MonthWeek> weeksOfMonth(int year, int month) {
    final days = daysInMonth(year, month);
    final weeks = <MonthWeek>[];
    var number = 1;
    for (var first = 1; first <= days; first += 7) {
      final last = (first + 6) > days ? days : first + 6;
      weeks.add(MonthWeek(
          year: year, month: month, number: number, firstDay: first, lastDay: last));
      number++;
    }
    return weeks;
  }

  static MonthWeek weekContaining(DateTime d) {
    final index = (d.day - 1) ~/ 7;
    return weeksOfMonth(d.year, d.month)[index];
  }

  static DateTime addMonths(DateTime month, int delta) =>
      DateTime(month.year, month.month + delta, 1);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String fullDate(DateTime d) => 
      _westernDigits(DateFormat('EEEE، d MMMM y', 'ar').format(d));
      
  static String mediumDate(DateTime d) => 
      _westernDigits(DateFormat('d MMMM y', 'ar').format(d));
      
  static String shortDate(DateTime d) => 
      _westernDigits(DateFormat('EEE، d MMM', 'ar').format(d));
      
  static String monthYear(DateTime d) => 
      _westernDigits(DateFormat('MMMM y', 'ar').format(d));
      
  static String monthName(int month) => 
      _westernDigits(DateFormat('MMMM', 'ar').format(DateTime(2000, month)));
      
  static String shortMonthName(int month) => 
      _westernDigits(DateFormat('MMM', 'ar').format(DateTime(2000, month)));

  static String _2(int v) => v.toString().padLeft(2, '0');
}