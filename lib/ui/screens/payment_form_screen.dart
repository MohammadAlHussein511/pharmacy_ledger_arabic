import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';

class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({
    super.key,
    required this.invoiceId,
    required this.invoiceCurrency,
    required this.remainingMinor,
    this.invoiceRate,
  });

  final int invoiceId;
  final String invoiceCurrency;
  final int remainingMinor;
  final double? invoiceRate;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _rateController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();

  String _currencyPaid = 'TRY';
  int? _warehouseId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _dateController.text = '${n.year}-${two(n.month)}-${two(n.day)}';
    _timeController.text = '${two(n.hour)}:${two(n.minute)}:00';
    _currencyPaid = widget.invoiceCurrency;
    if (widget.invoiceRate != null && widget.invoiceRate! > 0) {
      _rateController.text = '${widget.invoiceRate}';
    }
    _loadWarehouseId();
  }

  // [جوهري] جلب warehouse_id من الفاتورة
  Future<void> _loadWarehouseId() async {
    try {
      final services = context.read<AppServices>();
      final invs = await services.db.query('invoices',
          where: 'id = ?', whereArgs: [widget.invoiceId]);
      if (invs.isNotEmpty && mounted) {
        setState(() => _warehouseId = invs.first['warehouse_id'] as int);
      }
    } catch (_) {}
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
        _timeController.text = '${two(picked.hour)}:${two(picked.minute)}:00';
      });
    }
  }

  bool get _needsRate => _currencyPaid != widget.invoiceCurrency;

  int? get _equivalentInInvoiceCurrency {
    final amount = double.tryParse(_amountController.text);
    if (amount == null) return null;
    final minor = (amount * 100).round();
    if (_currencyPaid == widget.invoiceCurrency) return minor;
    final rate = double.tryParse(_rateController.text);
    if (rate == null || rate <= 0) return null;
    return (minor / rate).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن العثور على المستودع')),
      );
      return;
    }

    final equivalent = _equivalentInInvoiceCurrency;
    if (equivalent != null && equivalent > widget.remainingMinor) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'الدفعة (${(equivalent / 100).toStringAsFixed(2)} ${widget.invoiceCurrency}) '
              'تتجاوز المتبقي (${(widget.remainingMinor / 100).toStringAsFixed(2)} ${widget.invoiceCurrency})'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final services = context.read<AppServices>();
      final now = DateTime.now();
      final amount = (double.parse(_amountController.text) * 100).round();
      final rate = _needsRate ? double.tryParse(_rateController.text) : null;

      // [جوهري] عملية ذرية: transaction + invoice_payment مع transaction_id
      await services.db.transaction((txn) async {
        final txId = await txn.insert('transactions', {
          'type': 'PAYMENT',
          'amount_minor': amount,
          'currency': _currencyPaid,
          'warehouse_id': _warehouseId,
          'invoice_number': null,
          'note': 'دفعة على فاتورة',
          'transaction_date': _dateController.text,
          'transaction_time': _timeController.text,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });

        await txn.insert('invoice_payments', {
          'invoice_id': widget.invoiceId,
          'transaction_id': txId,
          'amount_minor': amount,
          'currency_paid': _currencyPaid,
          'exchange_rate': rate,
          'note': 'دفعة على فاتورة',
          'payment_date': _dateController.text,
          'payment_time': _timeController.text,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
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
    _amountController.dispose();
    _rateController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  String _curLabel(String c) => switch (c) {
        'TRY' => 'ليرة تركية',
        'USD' => 'دولار أمريكي',
        'SYP' => 'ليرة سورية',
        _ => c,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final equivalent = _equivalentInInvoiceCurrency;
    return Scaffold(
      appBar: AppBar(title: const Text('دفعة جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المتبقي على الفاتورة: ${(widget.remainingMinor / 100).toStringAsFixed(2)} ${widget.invoiceCurrency}',
                      style: t.bodyMedium,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _currencyPaid,
              decoration: const InputDecoration(
                labelText: 'عملة الدفع',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'TRY', child: Text('ليرة تركية')),
                DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي')),
                DropdownMenuItem(value: 'SYP', child: Text('ليرة سورية')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _currencyPaid = v);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'قيمة الدفعة (${_curLabel(_currencyPaid)}) *',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.isEmpty) return 'أدخل القيمة';
                final n = double.tryParse(v);
                if (n == null || n <= 0) return 'قيمة غير صحيحة';
                return null;
              },
            ),
            if (_needsRate) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _rateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      'قيمة الصرف: 1 ${widget.invoiceCurrency} = ؟ ${_curLabel(_currencyPaid)} *',
                  hintText: 'مثال: 34.5',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (!_needsRate) return null;
                  if (v == null || v.isEmpty) return 'أدخل قيمة الصرف';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'قيمة غير صحيحة';
                  return null;
                },
              ),
            ],
            if (equivalent != null && _currencyPaid != widget.invoiceCurrency) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.calculate_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيُخصم من الفاتورة: ${(equivalent / 100).toStringAsFixed(2)} ${widget.invoiceCurrency}',
                        style: t.bodyMedium,
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'التاريخ *', border: OutlineInputBorder()),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _timeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'الوقت *', border: OutlineInputBorder()),
                  onTap: _pickTime,
                ),
              ),
            ]),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الدفعة'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}