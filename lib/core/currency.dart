/// Supported currencies. Amounts in different currencies are NEVER combined
/// or converted anywhere in the application.
enum Currency {
  // [تم التعديل] - ترجمة أسماء العملات إلى العربية
  turkishLira('TRY', 'ليرة تركية'),
  usDollar('USD', 'دولار أمريكي'),
  syrianPound('SYP', 'ليرة سورية');

  const Currency(this.code, this.label);

  final String code;
  final String label;

  /// Display order used in every report: TRY, USD, SYP.
  static const List<Currency> reportOrder = [turkishLira, usDollar, syrianPound];

  /// Order offered in the payment currency selector (per specification).
  static const List<Currency> paymentOptions = [usDollar, syrianPound, turkishLira];

  /// Sales are always recorded in TRY.
  static const Currency salesCurrency = turkishLira;

  static Currency fromCode(String code) {
    for (final c in Currency.values) {
      if (c.code == code) return c;
    }
    throw FormatException('Unknown currency: $code');
  }

  static Currency? tryFromCode(String? code) {
    if (code == null) return null;
    for (final c in Currency.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
