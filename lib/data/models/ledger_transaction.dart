import '../../core/currency.dart';
import '../../core/dates.dart';

enum TransactionType {
  sale('SALE'),
  payment('PAYMENT');

  const TransactionType(this.code);
  final String code;

  static TransactionType fromCode(String code) =>
      TransactionType.values.firstWhere((t) => t.code == code,
          orElse: () => throw FormatException('Unknown transaction type: $code'));
}

/// One row of the `transactions` table. SALE and PAYMENT share one table
/// so every report is a single aggregate query over one source of truth.
/// New types (EXPENSE, SALARY, RENT...) can be added later without a new table.
class LedgerTransaction {
  const LedgerTransaction({
    this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
    this.warehouseId,
    this.warehouseName,
    this.invoiceNumber,
    this.note,
    required this.date,
    required this.time,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final TransactionType type;
  final int amountMinor;
  final Currency currency;
  final int? warehouseId;

  /// Joined from warehouses for display only (not stored on the row).
  final String? warehouseName;
  final String? invoiceNumber;
  final String? note;

  /// "yyyy-MM-dd" local date.
  final String date;

  /// "HH:mm:ss" local time.
  final String time;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSale => type == TransactionType.sale;
  bool get isPayment => type == TransactionType.payment;
  DateTime get day => Dates.parseKey(date);

  factory LedgerTransaction.newSale({
    required int amountMinor,
    required DateTime day,
    required DateTime now,
  }) =>
      LedgerTransaction(
        type: TransactionType.sale,
        amountMinor: amountMinor,
        currency: Currency.salesCurrency,
        date: Dates.key(day),
        time: Dates.timeKey(now),
      );

  factory LedgerTransaction.newPayment({
    required int amountMinor,
    required Currency currency,
    required int warehouseId,
    String? invoiceNumber,
    String? note,
    required DateTime day,
    required DateTime now,
  }) =>
      LedgerTransaction(
        type: TransactionType.payment,
        amountMinor: amountMinor,
        currency: currency,
        warehouseId: warehouseId,
        invoiceNumber: invoiceNumber,
        note: note,
        date: Dates.key(day),
        time: Dates.timeKey(now),
      );

  factory LedgerTransaction.fromMap(Map<String, Object?> m) => LedgerTransaction(
        id: m['id'] as int,
        type: TransactionType.fromCode(m['type'] as String),
        amountMinor: m['amount_minor'] as int,
        currency: Currency.fromCode(m['currency'] as String),
        warehouseId: m['warehouse_id'] as int?,
        warehouseName: m['warehouse_name'] as String?,
        invoiceNumber: m['invoice_number'] as String?,
        note: m['note'] as String?,
        date: m['transaction_date'] as String,
        time: m['transaction_time'] as String,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? ''),
        updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
      );

  Map<String, Object?> toRow() => {
        'type': type.code,
        'amount_minor': amountMinor,
        'currency': currency.code,
        'warehouse_id': isSale ? null : warehouseId,
        'invoice_number': isSale ? null : _blankToNull(invoiceNumber),
        'note': _blankToNull(note),
        'transaction_date': date,
        'transaction_time': time,
      };

  LedgerTransaction copyWith({
    int? amountMinor,
    Currency? currency,
    int? warehouseId,
    String? invoiceNumber,
    String? note,
    String? date,
    String? time,
  }) =>
      LedgerTransaction(
        id: id,
        type: type,
        amountMinor: amountMinor ?? this.amountMinor,
        currency: currency ?? this.currency,
        warehouseId: warehouseId ?? this.warehouseId,
        warehouseName: warehouseName,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        note: note ?? this.note,
        date: date ?? this.date,
        time: time ?? this.time,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
