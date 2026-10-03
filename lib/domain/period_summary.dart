import '../core/currency.dart';

/// Totals for any period. Sales are TRY only; payments are kept strictly
/// separated per currency and are never summed across currencies.
class PeriodSummary {
  PeriodSummary({
    this.salesMinor = 0,
    Map<Currency, int>? payments,
    this.saleCount = 0,
    this.paymentCount = 0,
  }) : payments = Map.unmodifiable(payments ?? const {});

  static final PeriodSummary empty = PeriodSummary();

  final int salesMinor;
  final Map<Currency, int> payments;
  final int saleCount;
  final int paymentCount;

  int payment(Currency c) => payments[c] ?? 0;

  bool get hasSales => saleCount > 0;
  bool get hasPayments => paymentCount > 0;
  bool get isEmpty => saleCount == 0 && paymentCount == 0;

  /// Currencies with a non-zero payment total, in report order (TRY, USD, SYP).
  List<Currency> get paidCurrencies =>
      Currency.reportOrder.where((c) => payment(c) != 0).toList();

  PeriodSummary operator +(PeriodSummary o) {
    final merged = <Currency, int>{...payments};
    o.payments.forEach((c, v) => merged[c] = (merged[c] ?? 0) + v);
    return PeriodSummary(
      salesMinor: salesMinor + o.salesMinor,
      payments: merged,
      saleCount: saleCount + o.saleCount,
      paymentCount: paymentCount + o.paymentCount,
    );
  }

  static PeriodSummary sum(Iterable<PeriodSummary> items) =>
      items.fold(PeriodSummary.empty, (a, b) => a + b);

  @override
  bool operator ==(Object other) {
    if (other is! PeriodSummary) return false;
    if (other.salesMinor != salesMinor ||
        other.saleCount != saleCount ||
        other.paymentCount != paymentCount) {
      return false;
    }
    for (final c in Currency.values) {
      if (other.payment(c) != payment(c)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(salesMinor, saleCount, paymentCount,
      payment(Currency.turkishLira), payment(Currency.usDollar), payment(Currency.syrianPound));

  @override
  String toString() =>
      'PeriodSummary(sales: $salesMinor, payments: $payments, sales#: $saleCount, payments#: $paymentCount)';
}

/// Mutable accumulator used while reading aggregate rows.
class SummaryBuilder {
  int _sales = 0;
  int _saleCount = 0;
  int _paymentCount = 0;
  final Map<Currency, int> _payments = {};

  void addRow(String type, String currency, int total, int count) {
    if (type == 'SALE') {
      _sales += total;
      _saleCount += count;
    } else if (type == 'PAYMENT') {
      final c = Currency.fromCode(currency);
      _payments[c] = (_payments[c] ?? 0) + total;
      _paymentCount += count;
    }
  }

  PeriodSummary build() => PeriodSummary(
        salesMinor: _sales,
        payments: _payments,
        saleCount: _saleCount,
        paymentCount: _paymentCount,
      );
}
