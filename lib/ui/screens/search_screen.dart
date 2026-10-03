import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../data/models/ledger_transaction.dart';
import '../../data/models/warehouse.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../services.dart';
import '../widgets/common.dart';
import '../widgets/paged_transactions.dart';
import '../widgets/revision_builder.dart';

/// Search payments by warehouse name or invoice number, and filter by
/// date range, currency and warehouse.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';
  DateTimeRange? _range;
  Currency? _currency;
  Warehouse? _warehouse;
  List<Warehouse> _warehouses = const [];

  @override
  void initState() {
    super.initState();
    context.read<AppServices>().warehouses.list(includeInactive: true).then((w) {
      if (mounted) setState(() => _warehouses = w);
    });
  }

  TransactionFilter get _filter => TransactionFilter(
        type: TransactionType.payment,
        query: _query,
        from: _range?.start,
        to: _range?.end,
        currency: _currency,
        warehouseId: _warehouse?.id,
      );

  String get _key =>
      '$_query|${_range?.start}|${_range?.end}|${_currency?.code}|${_warehouse?.id}';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      // [تم التعديل] - ترجمة نص المساعدة في منتقي التاريخ
      helpText: 'تصفية حسب التاريخ',
    );
    if (r != null) setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppServices>();
    final filter = _filter;
    return Scaffold(
      // [تم التعديل] - ترجمة عنوان الشاشة
      appBar: AppBar(title: const Text('البحث في المدفوعات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                // [تم التعديل] - ترجمة النص التلميحي في مربع البحث
                hintText: 'اسم المستودع أو رقم الفاتورة',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  // [تم التعديل] - ترجمة شريحة التاريخ
                  label: Text(_range == null
                      ? 'أي تاريخ'
                      : '${Dates.shortDate(_range!.start)} – ${Dates.shortDate(_range!.end)}'),
                  selected: _range != null,
                  onSelected: (_) => _pickRange(),
                  onDeleted: _range == null ? null : () => setState(() => _range = null),
                ),
                for (final c in Currency.reportOrder)
                  FilterChip(
                    label: Text(c.code),
                    selected: _currency == c,
                    onSelected: (v) => setState(() => _currency = v ? c : null),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              value: _warehouse?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  // [تم التعديل] - ترجمة تسمية المستودع
                  labelText: 'المستودع', prefixIcon: Icon(Icons.warehouse_outlined)),
              items: [
                // [تم التعديل] - ترجمة خيارات المستودعات
                const DropdownMenuItem<int?>(value: null, child: Text('جميع المستودعات')),
                for (final w in _warehouses)
                  DropdownMenuItem<int?>(
                    value: w.id,
                    child: Text(w.isActive ? w.name : '${w.name} (معطّل)',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() {
                _warehouse = id == null ? null : _warehouses.firstWhere((w) => w.id == id);
              }),
            ),
            const SizedBox(height: 16),
            RevisionBuilder<Map<Currency, int>>(
              dependency: _key,
              load: () => s.transactions.totalsByCurrency(filter),
              builder: (context, totals) => totals.isEmpty
                  ? const SizedBox.shrink()
                  : SectionCard(
                      // [تم التعديل] - ترجمة عنوان إجمالي النتائج
                      title: 'إجماليات النتائج',
                      child: Column(
                        children: [
                          for (final c in Currency.reportOrder)
                            if ((totals[c] ?? 0) != 0)
                              AmountRow(label: c.code, minor: totals[c]!, currency: c),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            PagedTransactionList(
              dependency: _key,
              // [تم التعديل] - ترجمة رسالة عدم وجود نتائج
              emptyMessage: 'لا توجد دفعات تطابق بحثك.',
              loader: (limit, offset) => s.transactions.search(filter, limit: limit, offset: offset),
            ),
          ],
        ),
      ),
    );
  }
}
