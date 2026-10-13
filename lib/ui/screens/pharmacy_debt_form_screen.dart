import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';

class PharmacyDebtFormScreen extends StatefulWidget {
  const PharmacyDebtFormScreen({super.key});

  @override
  State<PharmacyDebtFormScreen> createState() => _PharmacyDebtFormScreenState();
}

class _PharmacyDebtFormScreenState extends State<PharmacyDebtFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final services = context.read<AppServices>();
      final now = DateTime.now().toIso8601String();
      final name = _nameController.text.trim();
      await services.db.insert('pharmacy_debts', {
        'name': name,
        'name_key': name.toLowerCase(),
        'created_at': now,
        'updated_at': now,
      });
      services.store.changed();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صيدلية جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم الصيدلية *',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'أدخل الاسم';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}