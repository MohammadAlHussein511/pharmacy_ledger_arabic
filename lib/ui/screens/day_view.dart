import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/ledger_transaction.dart';
import '../../domain/period_summary.dart';
import '../../services.dart';
import '../day_clock.dart';
import '../widgets/common.dart';
import '../widgets/revision_builder.dart';
import '../widgets/transaction_widgets.dart';

typedef _DayData = ({PeriodSummary summary, List<LedgerTransaction> items});

/// Shows one day: totals and every sale and payment. Used by the Today tab
/// and for any historical day opened from reports.
class DayView extends StatelessWidget {
  const DayView({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final today = context.watch<DayClock>().today;
    final isToday = Dates.isSameDay(day, today);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return RevisionBuilder<_DayData>(
      dependency: Dates.key(day),
      load: () async {
        final r = await Future.wait<Object>([
          services.reports.day(day),
          // التعديل: تغيير forDay إلى onDay
          services.transactions.onDay(day),
        ]);
        return (summary: r[0] as PeriodSummary, items: r[1] as List<LedgerTransaction>);
      },
      builder: (context, data) {
        final sales = data.items.where((x) => x.isSale).toList();
        final payments = data.items.where((x) => x.isPayment).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(Dates.fullDate(day), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // ----------------------------------- sales
            // [تم التعديل] - ترجمة قسم المبيعات
            SectionCard(
              title: 'المبيعات',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AmountRow(
                    label: isToday ? 'مبيعات اليوم' : 'المبيعات',
                    minor: data.summary.salesMinor,
                    currency: Currency.salesCurrency,
                    emphasized: true,
                  ),
                  const SizedBox(height: 4),
                  if (sales.isEmpty)
                    EmptyState(
                      icon: Icons.point_of_sale_outlined,
                      message: isToday ? 'لا توجد مبيعات مسجلة اليوم.' : 'لا توجد مبيعات مسجلة في هذا اليوم.',
                    )
                  else ...[
                    const Divider(),
                    for (final s in sales) _SaleLine(tx: s),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => openAddSale(context, day: day),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بيع'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ----------------------------------- payments
            // [تم التعديل] - ترجمة قسم دفعات المستودعات
            SectionCard(
              title: 'دفعات المستودعات',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (data.summary.paidCurrencies.isEmpty)
                    Text('الإجمالي: لا شيء',
                        style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                  else
                    for (final c in data.summary.paidCurrencies)
                      AmountRow(label: 'إجمالي ${c.code}', minor: data.summary.payment(c), currency: c),

                  if (payments.isEmpty)
                    EmptyState(
                      icon: Icons.local_shipping_outlined,
                      message: isToday
                          ? 'لا توجد دفعات مسجلة اليوم.'
                          : 'لا توجد دفعات مسجلة في هذا اليوم.',
                    )
                  else ...[
                    const Divider(),
                    for (final p in payments) TransactionTile(tx: p),
                  ],

                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => openAddPayment(context, day: day),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة دفعة'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "12:35 — 850 TRY", tap for Edit / Delete.
class _SaleLine extends StatelessWidget {
  const _SaleLine({required this.tx});

  final LedgerTransaction tx;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showTransactionActions(context, tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Text(Dates.shortTime(tx.time),
                style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Text(' — '),
            Expanded(
              child: Text(Money.format(tx.amountMinor, tx.currency),
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (tx.note != null)
              Icon(Icons.notes, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const Icon(Icons.more_vert, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Pushed page for any historical day.
class DayScreen extends StatelessWidget {
  const DayScreen({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Dates.mediumDate(day))),
        body: SafeArea(child: DayView(day: day)),
      );
}

void openDay(BuildContext context, DateTime day) => Navigator.push(
      context, MaterialPageRoute<void>(builder: (_) => DayScreen(day: Dates.dateOnly(day))));