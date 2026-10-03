import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_ledger/core/currency.dart';
import 'package:pharmacy_ledger/core/money.dart';
import 'package:pharmacy_ledger/domain/validation.dart';

void main() {
  group('Money parsing (integer minor units, no floating point)', () {
    test('whole and decimal amounts', () {
      expect(Money.parseToMinor('1250'), 125000);
      expect(Money.parseToMinor('1250.5'), 125050);
      expect(Money.parseToMinor('1250.05'), 125005);
      expect(Money.parseToMinor('1250,50'), 125050, reason: 'comma decimal separator');
      expect(Money.parseToMinor('0.1'), 10);
      expect(Money.parseToMinor(' 7 '), 700);
    });

    test('0.1 + 0.2 is exact', () {
      expect(Money.parseToMinor('0.1')! + Money.parseToMinor('0.2')!, Money.parseToMinor('0.3'));
    });

    test('rejects invalid input', () {
      for (final bad in ['', ' ', 'abc', '-5', '1.234', '1.2.3', '١٢٣', '1e5', '.', '12a']) {
        expect(Money.parseToMinor(bad), isNull, reason: bad);
      }
    });

    test('rejects extremely large amounts', () {
      expect(Money.parseToMinor('9999999999999'), isNull);
      expect(Money.parseToMinor('999999999999'), 99999999999900);
    });
  });

  group('Formatting uses Western digits and thousands separators', () {
    test('examples', () {
      expect(Money.format(125000, Currency.turkishLira), '1,250 TRY');
      expect(Money.format(30000000, Currency.syrianPound), '300,000 SYP');
      expect(Money.format(550000000, Currency.syrianPound), '5,500,000 SYP');
      expect(Money.format(25000, Currency.usDollar), '250 USD');
      expect(Money.format(125050, Currency.turkishLira), '1,250.50 TRY');
      expect(Money.formatMinor(0), '0');
      expect(Money.formatMinor(99), '0.99');
      expect(Money.formatMinor(1234567), '12,345.67');
    });

    test('toInput round trips', () {
      for (final v in [100, 125000, 125050, 125005, 1]) {
        expect(Money.parseToMinor(Money.toInput(v)), v);
      }
    });
  });

  group('Amount validation messages', () {
    test('empty, zero, negative, invalid', () {
      expect(Validators.amount(''), Messages.invalidAmount);
      expect(Validators.amount('0'), Messages.invalidAmount);
      expect(Validators.amount('0.00'), Messages.invalidAmount);
      expect(Validators.amount('-10'), Messages.invalidAmount);
      expect(Validators.amount('abc'), Messages.invalidAmount);
      expect(Validators.amount('10000000000000'), Messages.amountTooLarge);
      expect(Validators.amount('850'), isNull);
    });

    test('warehouse name normalization', () {
      expect(Validators.normalizeWarehouseName('  Al-Shifa   Pharma  '), 'Al-Shifa Pharma');
      expect(Validators.warehouseKey('AL-SHIFA  pharma'), Validators.warehouseKey('al-shifa pharma'));
      expect(Validators.warehouseName('   '), Messages.warehouseNameRequired);
    });
  });
}
