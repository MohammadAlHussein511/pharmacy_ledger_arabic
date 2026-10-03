import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/ledger_transaction.dart';
import '../../data/models/warehouse.dart';
import '../../domain/validation.dart';
import '../../services.dart';
import '../widgets/common.dart';
import '../widgets/warehouse_picker.dart';

/// Add / edit form for both sales and payments.
/// New transactions get the current local time automatically.
class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({
    super.key,
    required this.type,
    this.existing,
    this.initialDay,
    this.initialWarehouseId,
  });

  final TransactionType type;
  final LedgerTransaction? existing;
  final DateTime? initialDay;
  final int? initialWarehouseId;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _invoice;
  late final TextEditingController _note;
  late DateTime _day;
  Warehouse? _warehouse;
  Currency? _currency;
  bool _saving = false;
  String? _warehouseError;
  String? _currencyError;

  bool get _isSale => widget.type == TransactionType.sale;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : Money.toInput(e.amountMinor));
    _invoice = TextEditingController(text: e?.invoiceNumber ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _day = e?.day ?? Dates.dateOnly(widget.initialDay ?? DateTime.now());
    final services = context.read<AppServices>();
    if (_isSale) {
      _currency = Currency.salesCurrency;
    } else {
      _currency = e?.currency ?? services.settings.lastPaymentCurrency;
      final whId = e?.warehouseId ?? widget.initialWarehouseId;
      if (whId != null) {
        services.warehouses.byId(whId).then((w) {
          if (mounted) setState(() => _warehouse = w);
        });
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _invoice.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      // [تم التعديل] - ترجمة نص المساعدة في منتقي التاريخ
      helpText: 'تاريخ المعاملة',
    );
    if (picked != null) setState(() => _day = Dates.dateOnly(picked));
  }

  Future<void> _pickWarehouse() async {
    final w = await showWarehousePicker(context);
    if (w != null) {
      setState(() {
        _warehouse = w;
        _warehouseError = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _warehouseError = !_isSale && _warehouse == null ? Messages.selectWarehouse : null;
      _currencyError = !_isSale && _currency == null ? Messages.selectCurrency : null;
    });
    if (!formOk || _warehouseError != null || _currencyError != null) return;

    final minor = Money.parseToMinor(_amount.text)!;
    final services = context.read<AppServices>();
    final repo = services.transactions;
    final now = DateTime.now();
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final e = widget.existing!;
        await repo.update(LedgerTransaction(
          id: e.id,
          type: e.type,
          amountMinor: minor,
          currency: _isSale ? Currency.salesCurrency : _currency!,
          warehouseId: _isSale ? null : _warehouse!.id,
          invoiceNumber: _isSale ? null : _invoice.text,
          note: _note.text,
          date: Dates.key(_day),
          time: e.time,
        ));
      } else if (_isSale) {
        await repo.insert(LedgerTransaction.newSale(amountMinor: minor, day: _day, now: now)
            .copyWith(note: _note.text));
      } else {
        await repo.insert(LedgerTransaction.newPayment(
          amountMinor: minor,
          currency: _currency!,
          warehouseId: _warehouse!.id!,
          invoiceNumber: _invoice.text,
          note: _note.text,
          day: _day,
          now: now,
        ));
        await services.settings.setLastPaymentCurrency(_currency!);
      }
      if (!mounted) return;
      // [تم التعديل] - ترجمة رسائل الحفظ
      showMessage(context, _isEdit ? 'تم حفظ التغييرات.' : (_isSale ? 'تم حفظ البيع.' : 'تم حفظ الدفعة.'));
      Navigator.pop(context);
    } on ValidationException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      // [تم التعديل] - ترجمة رسالة خطأ الحفظ
      if (mounted) showMessage(context, 'تعذّر الحفظ. لم تتغير بياناتك. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // [تم التعديل] - ترجمة عناوين الشاشة حسب نوع المعاملة
    final title = _isEdit ? (_isSale ? 'تعديل بيع' : 'تعديل دفعة') : (_isSale ? 'إضافة بيع' : 'إضافة دفعة');
    final isToday = Dates.isSameDay(_day, DateTime.now());

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_isSale) ...[
                // [تم التعديل] - ترجمة تسمية حقل المستودع
                const _FieldLabel('المستودع'),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickWarehouse,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.warehouse_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      errorText: _warehouseError,
                      // [تم التعديل] - ترجمة النص التلميحي
                      hintText: 'اختر مستودعاً',
                    ),
                    isEmpty: _warehouse == null,
                    child: _warehouse == null
                        ? null
                        : Text(
                            _warehouse!.isActive
                                ? _warehouse!.name
                                // [تم التعديل] - ترجمة كلمة "معطّل"
                                : '${_warehouse!.name} (معطّل)',
                            overflow: TextOverflow.ellipsis),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final w = await showAddWarehouseDialog(context);
                      if (w != null) {
                        setState(() {
                          _warehouse = w;
                          _warehouseError = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.add),
                    // [تم التعديل] - ترجمة زر إضافة مستودع جديد
                    label: const Text('إضافة مستودع جديد'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // [تم التعديل] - ترجمة تسمية حقل المبلغ
              const _FieldLabel('المبلغ'),
              TextFormField(
                controller: _amount,
                autofocus: !_isEdit && _isSale,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  _DecimalCommaFormatter(),
                  LengthLimitingTextInputFormatter(16),
                ],
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: _isSale ? 'TRY' : (_currency?.code ?? ''),
                ),
                validator: Validators.amount,
                onFieldSubmitted: (_) => _isSale ? _save() : null,
              ),
              const SizedBox(height: 16),
              // [تم التعديل] - ترجمة تسمية حقل العملة
              const _FieldLabel('العملة'),
              if (_isSale)
                InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline),
                    // [تم التعديل] - ترجمة النص المساعد للعملة
                    helperText: 'تُسجَّل المبيعات دائماً بالليرة التركية.',
                  ),
                  child: Text('TRY · ${Currency.salesCurrency.label}'),
                )
              else ...[
                SegmentedButton<Currency>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    for (final c in Currency.paymentOptions)
                      ButtonSegment(value: c, label: Text(c.code), tooltip: c.label),
                  ],
                  selected: {if (_currency != null) _currency!},
                  onSelectionChanged: (s) => setState(() {
                    _currency = s.isEmpty ? _currency : s.first;
                    _currencyError = null;
                  }),
                ),
                if (_currencyError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(_currencyError!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ),
              ],
              const SizedBox(height: 16),
              // [تم التعديل] - ترجمة تسمية حقل التاريخ
              const _FieldLabel('التاريخ'),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDay,
                child: InputDecorator(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.event_outlined),
                    // [تم التعديل] - ترجمة النص المساعد للتاريخ
                    helperText: _isEdit
                        ? 'الوقت: ${Dates.shortTime(widget.existing!.time)}'
                        : 'يُسجَّل الوقت تلقائياً عند الحفظ.',
                  ),
                  // [تم التعديل] - ترجمة كلمة "اليوم" في عرض التاريخ
                  child: Text(isToday ? 'اليوم · ${Dates.mediumDate(_day)}' : Dates.fullDate(_day)),
                ),
              ),
              if (!_isSale) ...[
                const SizedBox(height: 16),
                // [تم التعديل] - ترجمة تسمية حقل رقم الفاتورة
                const _FieldLabel('رقم الفاتورة (اختياري)'),
                TextFormField(
                  controller: _invoice,
                  maxLength: Validators.maxInvoice,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.tag)),
                ),
              ],
              const SizedBox(height: 8),
              // [تم التعديل] - ترجمة تسمية حقل الملاحظة
              const _FieldLabel('ملاحظة (اختياري)'),
              TextFormField(
                controller: _note,
                maxLength: Validators.maxNote,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.notes)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    // [تم التعديل] - ترجمة زر الحفظ
                    : const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

/// Accepts "," as a decimal separator (common on Turkish keyboards) and keeps
/// at most one separator with two decimals.
class _DecimalCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.');
    final firstDot = text.indexOf('.');
    if (firstDot != -1) {
      if (text.indexOf('.', firstDot + 1) != -1) return oldValue;
      if (text.length - firstDot - 1 > 2) return oldValue;
    }
    return newValue.copyWith(text: text);
  }
}
