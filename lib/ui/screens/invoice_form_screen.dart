import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';

class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key, this.existing});
  final Map<String, Object?>? existing;

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _WhOption {
  _WhOption(this.id, this.name);
  final int id;
  final String name;
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  String _currency = 'USD';
  _WhOption? _selectedWh;
  List<_WhOption> _warehouses = [];
  bool _loadingWh = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final e = widget.existing!;
      _amountController.text = ((e['amount_minor'] as int) / 100).toStringAsFixed(2);
      _dateController.text = e['invoice_date'] as String;
      _currency = e['currency'] as String;
    } else {
      _dateController.text = _today();
    }
    _loadWarehouses();
  }

  String _today() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  Future<void> _loadWarehouses() async {
    try {
      final services = context.read<AppServices>();
      final bytes = await services.backup.createBackup();
      final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = env['data'] as Map<String, dynamic>;
      final whs = (data['warehouses'] as List? ?? []).cast<Map<String, dynamic>>();
      final list = <_WhOption>[];
      for (final w in whs) {
        if (w['is_active'] == 1) {
          list.add(_WhOption(w['id'] as int, w['name'] as String));
        }
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _warehouses = list;
        _loadingWh = false;
        if (_isEdit) {
          final wid = widget.existing!['warehouse_id'] as int;
          final match = list.where((w) => w.id == wid);
          if (match.isNotEmpty) _selectedWh = match.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWh = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateController.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      String two(int v) => v.toString().padLeft(2, '0');
      setState(() {
        _dateController.text = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWh == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر المستودع')));
      return;
    }
    setState(() => _saving = true);
    try {
      final services = context.read<AppServices>();
      final now = DateTime.now().toIso8601String();
      final amount = (double.parse(_amountController.text) * 100).round();
      if (_isEdit) {
        await services.db.update('invoices', {
          'warehouse_id': _selectedWh!.id,
          'currency': _currency,
          'amount_minor': amount,
          'invoice_date': _dateController.text,
          'updated_at': now,
        }, where: 'id = ?', whereArgs: [widget.existing!['id']]);
      } else {
        await services.db.insert('invoices', {
          'warehouse_id': _selectedWh!.id,
          'currency': _currency,
          'amount_minor': amount,
          'paid_minor': 0,
          'invoice_date': _dateController.text,
          'created_at': now,
          'updated_at': now,
        });
      }
      services.store.changed();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل الفاتورة' : 'فاتورة جديدة')),
      body: _loadingWh
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<_WhOption>(
                    value: _selectedWh,
                    decoration: const InputDecoration(labelText: 'المستودع *', border: OutlineInputBorder()),
                    items: [for (final w in _warehouses) DropdownMenuItem(value: w, child: Text(w.name))],
                    onChanged: (v) => setState(() => _selectedWh = v),
                    validator: (v) => v == null ? 'اختر المستودع' : null,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'USD', label: Text('دولار أمريكي')),
                      ButtonSegment(value: 'SYP', label: Text('ليرة سورية')),
                    ],
                    selected: {_currency},
                    onSelectionChanged: (s) => setState(() => _currency = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'قيمة الفاتورة (${_currency == 'USD' ? 'دولار' : 'ليرة سورية'}) *',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'أدخل القيمة';
                      final n = double.tryParse(v);
                      if (n == null || n <= 0) return 'قيمة غير صحيحة';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'تاريخ الفاتورة *',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: _pickDate,
                    validator: (v) => v == null || v.isEmpty ? 'أدخل التاريخ' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'جارٍ الحفظ...' : (_isEdit ? 'حفظ التعديلات' : 'حفظ الفاتورة')),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ],
              ),
            ),
    );
  }
}