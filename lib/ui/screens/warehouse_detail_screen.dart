import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency.dart';
import '../../data/models/ledger_transaction.dart';
import '../../data/models/warehouse.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/warehouse_repository.dart';
import '../../domain/report_service.dart';
import '../../domain/validation.dart';
import '../../services.dart';
import '../widgets/common.dart';
import '../widgets/paged_transactions.dart';
import '../widgets/revision_builder.dart';
import '../widgets/transaction_widgets.dart';

typedef _Detail = ({Warehouse? warehouse, WarehouseTotals totals});

class WarehouseDetailScreen extends StatelessWidget {
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  final int warehouseId;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppServices>();
    return RevisionBuilder<_Detail>(
      dependency: warehouseId,
      load: () async => (
        warehouse: await s.warehouses.byId(warehouseId),
        totals: await s.reports.warehouseTotals(warehouseId),
      ),
      builder: (context, d) {
        final w = d.warehouse;
        if (w == null) {
          return Scaffold(
            appBar: AppBar(),
            // [تم التعديل] - ترجمة رسالة عدم وجود المستودع
            body: const EmptyState(message: 'لم يعد هذا المستودع موجوداً.'),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(w.name, overflow: TextOverflow.ellipsis),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => _onMenu(context, v, w, d.totals.paymentCount),
                itemBuilder: (_) => [
                  // [تم التعديل] - ترجمة خيارات قائمة المستودع
                  const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(w.isActive ? 'تعطيل المستودع' : 'إعادة تفعيل المستودع')),
                  if (d.totals.paymentCount == 0)
                    const PopupMenuItem(value: 'delete', child: Text('حذف المستودع')),
                ],
              ),
            ],
          ),
          floatingActionButton: w.isActive
              ? FloatingActionButton.extended(
                  onPressed: () => openAddPayment(context, warehouseId: w.id),
                  icon: const Icon(Icons.add),
                  // [تم التعديل] - ترجمة زر إضافة دفعة
                  label: const Text('إضافة دفعة'),
                )
              : null,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (!w.isActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    // [تم التعديل] - ترجمة تحذير المستودع المعطّل
                    child: Text(
                      'هذا المستودع معطّل. يُحتفظ بسجل الدفعات الخاص به، '
                      'ولكنه يُخفى عند إضافة دفعات جديدة.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                SectionCard(
                  // [تم التعديل] - ترجمة عنوان بطاقة الإجماليات
                  title: 'إجمالي المدفوع',
                  subtitle:
                      '${d.totals.paymentCount} ${d.totals.paymentCount == 1 ? 'دفعة' : 'دفعة'}',
                  child: Column(
                    children: [
                      for (final c in Currency.reportOrder)
                        AmountRow(
                          // [تم التعديل] - ترجمة تسمية إجمالي كل عملة
                          label: 'إجمالي ${c.code} المدفوع',
                          minor: d.totals.total(c),
                          currency: c,
                          muted: d.totals.total(c) == 0,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // [تم التعديل] - ترجمة عنوان سجل الدفعات
                Text('سجل الدفعات',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                PagedTransactionList(
                  dependency: w.id!,
                  // [تم التعديل] - ترجمة رسالة عدم وجود دفعات
                  emptyMessage: 'لا توجد دفعات مسجلة لهذا المستودع.',
                  loader: (limit, offset) => s.transactions.search(
                    TransactionFilter(warehouseId: w.id, type: TransactionType.payment),
                    limit: limit,
                    offset: offset,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onMenu(BuildContext context, String action, Warehouse w, int count) async {
    final repo = context.read<AppServices>().warehouses;
    try {
      switch (action) {
        case 'rename':
          final name = await _askName(context, w.name);
          if (name != null) await repo.rename(w.id!, name);
        case 'toggle':
          if (w.isActive) {
            // [تم التعديل] - ترجمة حوار تعطيل المستودع
            final ok = await confirmDialog(
              context,
              title: 'تعطيل المستودع؟',
              message: 'سيُخفى "${w.name}" عند إضافة الدفعات. '
                  'جميع الدفعات الحالية ($count) ستبقى في تقاريرك.',
              confirmLabel: 'تعطيل',
            );
            if (ok) await repo.setActive(w.id!, false);
          } else {
            await repo.setActive(w.id!, true);
          }
        case 'delete':
          // [تم التعديل] - ترجمة حوار حذف المستودع
          final ok = await confirmDialog(
            context,
            title: 'حذف المستودع؟',
            message: '"${w.name}" ليس لديه أي دفعات وسيتم حذفه.',
            confirmLabel: 'حذف',
            destructive: true,
          );
          if (ok) {
            await repo.deleteUnused(w.id!);
            if (context.mounted) Navigator.pop(context);
          }
      }
    } on DuplicateWarehouseException {
      if (context.mounted) showMessage(context, Messages.warehouseExists);
    } on WarehouseInUseException catch (e) {
      if (context.mounted) showMessage(context, e.toString());
    } on ValidationException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    } catch (_) {
      // [تم التعديل] - ترجمة رسالة الخطأ العامة
      if (context.mounted) showMessage(context, 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
    }
  }

  Future<String?> _askName(BuildContext context, String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        // [تم التعديل] - ترجمة حوار إعادة التسمية
        title: const Text('إعادة تسمية المستودع'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: Validators.maxWarehouseName,
          textCapitalization: TextCapitalization.words,
          // [تم التعديل] - ترجمة تسمية حقل الاسم
          decoration: const InputDecoration(labelText: 'اسم المستودع'),
        ),
        actions: [
          // [تم التعديل] - ترجمة أزرار الحوار
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}