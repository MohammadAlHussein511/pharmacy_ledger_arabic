import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_ledger/core/currency.dart';
import 'package:pharmacy_ledger/core/theme.dart';
import 'package:pharmacy_ledger/domain/period_summary.dart';
import 'package:pharmacy_ledger/ui/widgets/common.dart';

void main() {
  Widget host(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: Scaffold(body: SizedBox(width: 320, child: child)),
      );

  testWidgets('summary shows each currency separately, never a combined total', (tester) async {
    final summary = PeriodSummary(
      salesMinor: 450000,
      saleCount: 3,
      paymentCount: 3,
      payments: {
        Currency.turkishLira: 30000,
        Currency.usDollar: 10000,
        Currency.syrianPound: 5000000,
      },
    );
    await tester.pumpWidget(host(SummaryBlock(summary: summary)));
    expect(find.text('4,500 TRY'), findsOneWidget);
    expect(find.text('300 TRY'), findsOneWidget);
    expect(find.text('100 USD'), findsOneWidget);
    expect(find.text('50,000 SYP'), findsOneWidget);
    expect(find.textContaining('50,400'), findsNothing);
  });

  testWidgets('dashboard style shows all currencies and handles huge amounts in dark mode',
      (tester) async {
    final summary = PeriodSummary(
      salesMinor: 99999999999900,
      saleCount: 1,
      paymentCount: 1,
      payments: {Currency.syrianPound: 99999999999900},
    );
    await tester.pumpWidget(
        host(SummaryBlock(summary: summary, showAllCurrencies: true), mode: ThemeMode.dark));
    expect(find.text('999,999,999,999 TRY'), findsOneWidget);
    expect(find.text('0 USD'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow on a narrow screen');
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(host(SummaryBlock(summary: PeriodSummary.empty)));
    expect(find.text('No payments'), findsOneWidget);
    expect(find.text('0 TRY'), findsOneWidget);
  });
}
