import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/warehouse.dart';
import '../../data/repositories/warehouse_repository.dart';
import '../../domain/validation.dart';
import '../../services.dart';
import 'common.dart';

/// Dialog to create a warehouse. Returns the created (or existing) warehouse.
Future<Warehouse?> showAddWarehouseDialog(BuildContext context, {String initial = ''}) {
  return showDialog<Warehouse>(
    context: context,
    builder: (_) => _AddWarehouseDialog(initial: initial),
  );
}

class _AddWarehouseDialog extends StatefulWidget {
  const _AddWarehouseDialog({required this.initial});
  final String initial;

  @override
  State<_AddWarehouseDialog> createState() => _AddWarehouseDialogState();
}

class _AddWarehouseDialogState extends State<_AddWarehouseDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = context.read<AppServices>().warehouses;
    try {
      final w = await repo.create(_controller.text);
      if (mounted) Navigator.pop(context, w);
    } on DuplicateWarehouseException catch (e) {
      if (!mounted) return;
      // [تم التعديل] - ترجمة رسالة وجود المستودع
      showMessage(context, '"${e.existing.name}" موجود بالفعل وتم اختياره.');
      Navigator.pop(context, e.existing);
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      // [تم التعديل] - ترجمة رسالة خطأ الحفظ
      setState(() => _error = 'تعذّر حفظ المستودع. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // [تم التعديل] - ترجمة عنوان الحوار
      title: const Text('إضافة مستودع جديد'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: Validators.maxWarehouseName,
          // [تم التعديل] - ترجمة تسمية الحقل
          decoration: InputDecoration(labelText: 'اسم المستودع', errorText: _error),
          validator: Validators.warehouseName,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        // [تم التعديل] - ترجمة أزرار الحوار
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _saving ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

/// Searchable bottom sheet listing active warehouses, with "+ Add New Warehouse".
Future<Warehouse?> showWarehousePicker(BuildContext context) {
  return showModalBottomSheet<Warehouse>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _WarehousePickerSheet(),
  );
}

class _WarehousePickerSheet extends StatefulWidget {
  const _WarehousePickerSheet();

  @override
  State<_WarehousePickerSheet> createState() => _WarehousePickerSheetState();
}

class _WarehousePickerSheetState extends State<_WarehousePickerSheet> {
  List<Warehouse>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<AppServices>().warehouses.list();
    if (mounted) setState(() => _all = list);
  }

  Future<void> _addNew() async {
    final w = await showAddWarehouseDialog(context, initial: _query);
    if (w != null && mounted) Navigator.pop(context, w);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = (_all ?? const <Warehouse>[])
        .where((w) => q.isEmpty || w.name.toLowerCase().contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              // [تم التعديل] - ترجمة عنوان الشاشة
              child: Text('اختر مستودعاً', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                    // [تم التعديل] - ترجمة النص التلميحي للبحث
                    prefixIcon: Icon(Icons.search), hintText: 'البحث في المستودعات'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              // [تم التعديل] - ترجمة زر إضافة مستودع جديد
              title: const Text('+ إضافة مستودع جديد'),
              onTap: _addNew,
            ),
            const Divider(height: 1),
            Expanded(
              child: _all == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? EmptyState(
                          icon: Icons.warehouse_outlined,
                          // [تم التعديل] - ترجمة رسائل الحالة الفارغة
                          message: _all!.isEmpty
                              ? 'لا توجد مستودعات بعد. أضف أول مستودع لك.'
                              : 'لا يوجد مستودع يطابق بحثك.',
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: const Icon(Icons.warehouse_outlined),
                            title: Text(items[i].name),
                            onTap: () => Navigator.pop(context, items[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
