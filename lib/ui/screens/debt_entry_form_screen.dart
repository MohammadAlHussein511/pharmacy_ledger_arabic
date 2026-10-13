import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';

class DebtEntryFormScreen extends StatefulWidget {
  const DebtEntryFormScreen({super.key, required this.pharmacyId, this.existing});
  final int pharmacyId;
  final Map<String, Object?>? existing;

  @override
  State<DebtEntryFormScreen> createState() => _DebtEntryFormScreenState();
}

class _DebtEntryFormScreenState extends State<DebtEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  String _direction = 'OWED_TO_US';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final e = widget.existing!;
      _itemController.text = (e['note'] as String?) ?? '';
      _dateController.text = e['entry_date'] as String;
      _timeController.text = e['entry_time'] as String;
      _direction = e['direction'] as String;
    } else {
      final n = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      _dateController.text = '${n.year}-${two(n.month)}-${two(n.day)}';
      _timeController.text = '${two(n.hour)}:${two(n.minute)}';
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      String two(int v) => v.toString().padLeft(2, '0');
      setState(() {
        _timeController.text = '${two(picked.hour)}:${two(picked.minute)}';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final services = context.read<AppServices>();
      final now = DateTime.now().toIso8601String();
      if (_isEdit) {
        await services.db.update('pharmacy_debt_entries', {
          'direction': _direction,
          'note': _itemController.text.trim(),
          'entry_date': _dateController.text,
          'entry_time': _timeController.text,
          'updated_at': now,
        }, where: 'id = ?', whereArgs: [widget.existing!['id']]);
      } else {
        await services.db.insert('pharmacy_debt_entries', {
          'pharmacy_id': widget.pharmacyId,
          'direction': _direction,
          'amount_minor': 1,
          'currency': 'TRY',
          'note': _itemController.text.trim(),
          'entry_date': _dateController.text,
          'entry_time': _timeController.text,
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
    _itemController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل الحركة' : 'حركة دين جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'OWED_TO_US', label: Text('لنا عندهم'), icon: Icon(Icons.arrow_downward)),
                ButtonSegment(value: 'OWED_BY_US', label: Text('علينا لهم'), icon: Icon(Icons.arrow_upward)),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'اسم الدواء / الصنف *',
                hintText: 'مثال: أموكسيسيلين 500 — علبة واحدة',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'أدخل اسم الدواء';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _dateController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'التاريخ *', border: OutlineInputBorder()),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _timeController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'الوقت *', border: OutlineInputBorder()),
                  onTap: _pickTime,
                ),
              ),
            ]),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'جارٍ الحفظ...' : (_isEdit ? 'حفظ التعديلات' : 'حفظ الحركة')),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}