import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/ledger_transaction.dart';
import '../../services.dart';
import '../screens/home_shell.dart';
import '../screens/transaction_form_screen.dart';
import 'common.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, this.showDate = false});
  final LedgerTransaction tx;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final time = Dates.shortTime(tx.time);
    final when = showDate ? '${Dates.shortDate(tx.day)} · $time' : time;
    final details = <String>[
      when,
      if (tx.invoiceNumber != null) 'فاتورة ${tx.invoiceNumber}',
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: tx.isSale ? cs.primaryContainer : cs.secondaryContainer,
        foregroundColor: tx.isSale ? cs.onPrimaryContainer : cs.onSecondaryContainer,
        child: Icon(tx.isSale ? Icons.point_of_sale : Icons.local_shipping_outlined, size: 20),
      ),
      title: Text(
        tx.isSale ? 'بيع' : (tx.warehouseName ?? 'دفعة مستودع'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (tx.note != null)
            Text(tx.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
        ],
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: AmountText(tx.amountMinor, tx.currency),
        ),
      ),
      onTap: () => showTransactionActions(context, tx),
    );
  }
}

Future<void> showTransactionActions(BuildContext context, LedgerTransaction tx) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tx.isSale ? 'بيع' : (tx.warehouseName ?? 'دفعة')),
            subtitle: Text(
                '${Money.format(tx.amountMinor, tx.currency)} · ${Dates.mediumDate(tx.day)} ${Dates.shortTime(tx.time)}'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text('حذف', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;

  if (action == 'edit') {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TransactionFormScreen(type: tx.type, existing: tx),
    ));
    // [نهائي] تحديث كل الشاشات بعد التعديل
    if (context.mounted) HomeShell.of(context)?.bump();
    return;
  }

  final ok = await confirmDialog(
    context,
    title: 'حذف المعاملة',
    message: 'هل أنت متأكد أنك تريد حذف هذه المعاملة؟',
    confirmLabel: 'حذف',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String m) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
  try {
    await context.read<AppServices>().transactions.delete(tx.id!);
    say('تم حذف المعاملة.');
    // [نهائي] تحديث كل الشاشات بعد الحذف
    if (context.mounted) HomeShell.of(context)?.bump();
  } catch (_) {
    say('تعذّر حذف المعاملة. يرجى المحاولة مرة أخرى.');
  }
}

Future<void> openAddSale(BuildContext context, {DateTime? day}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => TransactionFormScreen(type: TransactionType.sale, initialDay: day),
  ));
  if (context.mounted) HomeShell.of(context)?.bump();
}

Future<void> openAddPayment(BuildContext context,
    {DateTime? day, int? warehouseId}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => TransactionFormScreen(
        type: TransactionType.payment, initialDay: day, initialWarehouseId: warehouseId),
  ));
  if (context.mounted) HomeShell.of(context)?.bump();
}