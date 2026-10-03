import '../core/currency.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models/ledger_transaction.dart';

class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Messages {
  Messages._();
  
  // [تم التعديل] - ترجمة جميع رسائل الأخطاء إلى العربية
  static const invalidAmount = 'الرجاء إدخال مبلغ صحيح.';
  static const amountTooLarge = 'هذا المبلغ كبير جداً.';
  static const selectWarehouse = 'الرجاء اختيار مستودع.';
  static const selectCurrency = 'الرجاء اختيار عملة.';
  static const saleCurrency = 'يجب تسجيل المبيعات بالليرة التركية (TRY).';
  static const invalidDate = 'الرجاء اختيار تاريخ صحيح.';
  static const warehouseNameRequired = 'الرجاء إدخال اسم المستودع.';
  static const warehouseNameTooLong = 'اسم المستودع طويل جداً.';
  static const warehouseExists = 'يوجد مستودع بهذا الاسم بالفعل.';
  static const warehouseInactive = 'هذا المستودع مُعطَّل.';
  static const textTooLong = 'هذا النص طويل جداً.';
}

class Validators {
  Validators._();

  static const int maxWarehouseName = 80;
  static const int maxInvoice = 40;
  static const int maxNote = 300;

  /// Form validator for amount fields. Returns an error message or null.
  static String? amount(String? input) {
    final raw = input?.trim() ?? '';
    if (raw.isEmpty) return Messages.invalidAmount;
    final wholePart = raw.replaceAll(',', '.').split('.').first;
    if (RegExp(r'^\d+$').hasMatch(wholePart) &&
        wholePart.replaceFirst(RegExp(r'^0+'), '').length > Money.maxWholeDigits) {
      return Messages.amountTooLarge;
    }
    final minor = Money.parseToMinor(raw);
    if (minor == null || minor <= 0) return Messages.invalidAmount;
    return null;
  }

  /// Trims and collapses internal whitespace: "  Al-Shifa   Pharma " -> "Al-Shifa Pharma".
  static String normalizeWarehouseName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Case-insensitive uniqueness key.
  static String warehouseKey(String name) => normalizeWarehouseName(name).toLowerCase();

  static String? warehouseName(String? input) {
    final n = normalizeWarehouseName(input ?? '');
    if (n.isEmpty) return Messages.warehouseNameRequired;
    if (n.length > maxWarehouseName) return Messages.warehouseNameTooLong;
    return null;
  }

  static String? optionalText(String? input, int max) =>
      (input?.trim().length ?? 0) > max ? Messages.textTooLong : null;

  /// Final business-rule check before any write.
  static void validateTransaction(LedgerTransaction tx) {
    if (tx.amountMinor <= 0) throw const ValidationException(Messages.invalidAmount);
    if (tx.amountMinor ~/ Money.scale >= _maxWhole) {
      throw const ValidationException(Messages.amountTooLarge);
    }
    if (!Dates.isValidKey(tx.date) || !Dates.isValidTime(tx.time)) {
      throw const ValidationException(Messages.invalidDate);
    }
    switch (tx.type) {
      case TransactionType.sale:
        if (tx.currency != Currency.salesCurrency) {
          throw const ValidationException(Messages.saleCurrency);
        }
      case TransactionType.payment:
        if (tx.warehouseId == null) {
          throw const ValidationException(Messages.selectWarehouse);
        }
    }
    if ((tx.invoiceNumber?.trim().length ?? 0) > maxInvoice ||
        (tx.note?.trim().length ?? 0) > maxNote) {
      throw const ValidationException(Messages.textTooLong);
    }
  }

  static final int _maxWhole = _pow10(Money.maxWholeDigits);
  static int _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}
