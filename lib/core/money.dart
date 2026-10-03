import 'currency.dart';

/// Money helpers. All amounts are stored as integer MINOR units
/// (1 TRY = 100 minor units) so no floating point arithmetic is ever used.
class Money {
  Money._();

  static const int scale = 100;

  /// Maximum whole-unit amount accepted for a single transaction
  /// (999,999,999,999). Large enough for SYP, small enough that sums
  /// of millions of rows stay far below the 64-bit integer limit.
  static const int maxWholeDigits = 12;

  static final RegExp _pattern = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$');

  /// Parses user input like "1250", "1250.5", "1250,50" into minor units.
  /// Returns null for anything that is not a valid non-negative amount.
  static int? parseToMinor(String? input) {
    if (input == null) return null;
    final s = input.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (s.isEmpty) return null;
    final m = _pattern.firstMatch(s);
    if (m == null) return null;
    final whole = m.group(1)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (whole.length > maxWholeDigits) return null;
    final frac = (m.group(2) ?? '').padRight(2, '0');
    return int.parse(whole) * scale + int.parse(frac);
  }

  /// Formats minor units with Western digits and thousands separators.
  /// Decimals are shown only when non-zero: 125000 -> "1,250", 125050 -> "1,250.50".
  static String formatMinor(int minor) {
    final negative = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ scale;
    final frac = abs % scale;
    final buffer = StringBuffer(_group(whole));
    if (frac != 0) buffer.write('.${frac.toString().padLeft(2, '0')}');
    return negative ? '-$buffer' : buffer.toString();
  }

  /// "1,250 TRY"
  static String format(int minor, Currency currency) =>
      '${formatMinor(minor)} ${currency.code}';

  /// Plain editable representation without separators: "1250" / "1250.5".
  static String toInput(int minor) {
    final whole = minor ~/ scale;
    final frac = minor % scale;
    if (frac == 0) return '$whole';
    var f = frac.toString().padLeft(2, '0');
    if (f.endsWith('0')) f = f.substring(0, 1);
    return '$whole.$f';
  }

  static String _group(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
