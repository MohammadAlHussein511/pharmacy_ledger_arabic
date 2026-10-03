import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/warehouse_repository.dart';
import '../../services.dart';
import '../widgets/common.dart';
import '../widgets/revision_builder.dart';
import '../widgets/warehouse_picker.dart';
import 'warehouse_detail_screen.dart';

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key, this.standalone = false});

  /// True when pushed from Settings (shows a back button).
  final bool standalone;

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  String _query = '';
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppServices>().warehouses;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        // [تم التعديل] - ترجمة عنوان الشاشة
        title: const Text('المستودعات'),
        automaticallyImplyLeading: widget.standalone,
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => setState(() => _showInactive = !_showInactive),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'inactive',
                checked: _showInactive,
                // [تم التعديل] - ترجمة خيار إظهار المستودعات المعطّلة
                child: const Text('إظهار المعطّلة'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddWarehouseDialog(context),
        icon: const Icon(Icons.add),
        // [تم التعديل] - ترجمة زر إضافة مستودع
        label: const Text('إضافة مستودع'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                    // [تم التعديل] - ترجمة النص التلميحي للبحث
                    prefixIcon: Icon(Icons.search), hintText: 'البحث في المستودعات'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: RevisionBuilder<List<WarehouseSummaryRow>>(
                dependency: '$_query|$_showInactive',
                load: () => repo.listWithCounts(includeInactive: _showInactive, query: _query),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyState(
                      icon: Icons.warehouse_outlined,
                      // [تم التعديل] - ترجمة رسائل الحالة الفارغة
                      message: _query.isEmpty
                          ? 'لا توجد مستودعات بعد.\nأضف المستودعات التي تدفع لها لتتمكن من اختيارها بسرعة.'
                          : 'لا يوجد مستودع يطابق بحثك.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                r.warehouse.isActive ? cs.secondaryContainer : cs.surfaceContainerHighest,
                            child: const Icon(Icons.warehouse_outlined),
                          ),
                          title: Text(r.warehouse.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          // [تم التعديل] - ترجمة عدد الدفعات مع مفرد/جمع
                          subtitle: Text(
                              '${r.paymentCount} ${r.paymentCount == 1 ? 'دفعة' : 'دفعة'}'
                              '${r.warehouse.isActive ? '' : ' · معطّل'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => WarehouseDetailScreen(warehouseId: r.warehouse.id!)),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
