import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/ledger_transaction.dart';
import '../../data/models/warehouse.dart';
import '../../domain/invoice_math.dart';
import '../../domain/validation.dart';
import '../../services.dart';
import '../widgets/common.dart';
import '../widgets/warehouse_picker.dart';

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
  late final TextEditingController _rate;
  late DateTime _day;
  Warehouse? _warehouse;
  Currency? _currency;
  bool _saving = false;
  String? _warehouseError;
  String? _currencyError;
  String? _rateError;
  String? _amountError;

  Map<String, int> _remaining = {};
  bool _loadingWarehouse = false;

  bool get _isSale => widget.type == TransactionType.sale;
  bool get _isEdit => widget.existing != null;

  String? get _invoiceCurrency =>
      _remaining.isEmpty ? null : _remaining.keys.first;

  bool get _needsRate {
    if (_isSale || _invoiceCurrency == null || _currency == null) return false;
    return _invoiceCurrency != _currency!.code;
  }

  int get _remainingForCurrency {
    if (_currency == null) return 0;
    return _remaining[_currency!.code] ??
        (_needsRate ? (_remaining[_invoiceCurrency] ?? 0) : 0);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : Money.toInput(e.amountMinor));
    _invoice = TextEditingController(text: e?.invoiceNumber ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _rate = TextEditingController();
    _day = e?.day ?? Dates.dateOnly(widget.initialDay ?? DateTime.now());
    final services = context.read<AppServices>();
    if (_isSale) {
      _currency = Currency.salesCurrency;
    } else {
      _currency = e?.currency ?? services.settings.lastPaymentCurrency;
      final whId = e?.warehouseId ?? widget.initialWarehouseId;
      if (whId != null) {
        services.warehouses.byId(whId).then((w) {
          if (mounted) {
            setState(() => _warehouse = w);
            _loadBalance(whId);
          }
        });
      }
    }
  }

  Future<void> _loadBalance(int warehouseId) async {
    if (_isSale) return;
    setState(() => _loadingWarehouse = true);
    try {
      final services = context.read<AppServices>();
      final rem = await InvoiceMath.warehouseRemaining(services.db, warehouseId);
      if (!mounted) return;
      setState(() {
        _remaining = rem;
        _loadingWarehouse = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWarehouse = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _invoice.dispose();
    _note.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
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
      _loadBalance(w.id!);
    }
  }

  int _toInvoiceEquivalent(int minorInPaid, double? rate) {
    final invCur = _invoiceCurrency;
    if (invCur == null) return 0;
    if (_currency?.code == invCur) return minorInPaid;
    if (rate == null || rate <= 0) return 0;
    return (minorInPaid / rate).round();
  }

  Future<void> _save() async {
    if (_saving) return;
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _warehouseError = !_isSale && _warehouse == null ? Messages.selectWarehouse : null;
      _currencyError = !_isSale && _currency == null ? Messages.selectCurrency : null;
      _rateError = null;
      _amountError = null;
    });

    double? rateValue;
    if (!_isSale && _needsRate) {
      final r = double.tryParse(_rate.text.trim());
      if (r == null || r <= 0) {
        setState(() => _rateError = 'قيمة الصرف مطلوبة عند اختلاف العملات');
        return;
      }
      rateValue = r;
    }

    if (!formOk || _warehouseError != null || _currencyError != null) return;

    final minor = Money.parseToMinor(_amount.text)!;
    final services = context.read<AppServices>();

    if (!_isSale) {
      // منع الدفع لمستودع بلا فواتير
      final invCount = await services.db.rawQuery(
          'SELECT COUNT(*) as c FROM invoices WHERE warehouse_id = ?',
          [_warehouse!.id]);
      final count = (invCount.first['c'] as num).toInt();
      if (count == 0 && !_isEdit) {
        setState(() {
          _warehouseError =
              'لا توجد فواتير لهذا المستودع. أدخل فاتورة من قسم الحسابات أولاً.';
        });
        return;
      }

      // منع تجاوز الرصيد الموحد (مع السماح بقيمة الدفعة الحالية عند التعديل)
      final invCur = _invoiceCurrency;
      if (invCur != null) {
        int allowed = _remaining[invCur] ?? 0;
        if (_isEdit && widget.existing!.type == TransactionType.payment) {
          final e = widget.existing!;
          // أضف قيمة الدفعة القديمة للسماح بتعديلها
          final oldPays = await services.db.rawQuery(
              'SELECT amount_minor, currency_paid, exchange_rate FROM invoice_payments WHERE transaction_id = ?',
              [e.id]);
          if (oldPays.isNotEmpty) {
            final o = oldPays.first;
            final oc = o['currency_paid'] as String;
            final oa = o['amount_minor'] as int;
            final orate = (o['exchange_rate'] as num?)?.toDouble();
            allowed += oc == invCur ? oa : (orate != null && orate > 0 ? (oa / orate).round() : 0);
          } else {
            allowed += e.amountMinor;
          }
        }
        final equivalent = _needsRate
            ? (rateValue != null && rateValue > 0 ? (minor / rateValue).round() : minor)
            : minor;
        if (equivalent > allowed) {
          setState(() {
            _amountError =
                'الدفعة (${Money.format(equivalent, Currency.fromCode(invCur))}) '
                'تتجاوز الرصيد المتبقي (${Money.format(allowed, Currency.fromCode(invCur))})';
          });
          return;
        }
      }
    }

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
        final tx = LedgerTransaction.newPayment(
          amountMinor: minor,
          currency: _currency!,
          warehouseId: _warehouse!.id!,
          invoiceNumber: _invoice.text,
          note: _note.text,
          day: _day,
          now: now,
        );
        final txId = await repo.insert(tx);
        await services.settings.setLastPaymentCurrency(_currency!);

        // [نهائي] صف دفع واحد مربوط بالفاتورة الأولى المفتوحة + بالـ transaction
        final invId = await InvoiceMath.firstOpenInvoice(services.db, _warehouse!.id!);
        if (invId != null) {
          final ts = DateTime.now();
          String two(int v) => v.toString().padLeft(2, '0');
          await services.db.insert('invoice_payments', {
            'invoice_id': invId,
            'transaction_id': txId,
            'amount_minor': minor,
            'currency_paid': _currency!.code,
            'exchange_rate': rateValue,
            'note': _note.text.isEmpty ? 'دفعة على فاتورة' : _note.text,
            'payment_date': Dates.key(_day),
            'payment_time': '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
        }
      }

      if (!mounted) return;
      showMessage(context, _isEdit ? 'تم حفظ التغييرات.' : (_isSale ? 'تم حفظ البيع.' : 'تم حفظ الدفعة.'));
      Navigator.pop(context);
    } on ValidationException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, 'تعذّر الحفظ. لم تتغير بياناتك. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _isEdit
        ? (_isSale ? 'تعديل بيع' : 'تعديل دفعة')
        : (_isSale ? 'إضافة بيع' : 'إضافة دفعة');
    final isToday = Dates.isSameDay(_day, DateTime.now());
    final remText = _remaining.entries
        .map((e) => Money.format(e.value, Currency.fromCode(e.key)))
        .join(' + ');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_isSale) ...[
                const _FieldLabel('المستودع'),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickWarehouse,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.warehouse_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      errorText: _warehouseError,
                      hintText: 'اختر مستودعاً',
                    ),
                    isEmpty: _warehouse == null,
                    child: _warehouse == null
                        ? null
                        : Text(
                            _warehouse!.isActive
                                ? _warehouse!.name
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
                        _loadBalance(w.id!);
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة مستودع جديد'),
                  ),
                ),
                if (_loadingWarehouse)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator())
                else if (_remaining.isNotEmpty && _warehouse != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            color: Theme.of(context).colorScheme.onPrimaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'الرصيد المتبقي على ${_warehouse!.name}: $remText',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
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
                  errorText: _amountError,
                ),
                validator: Validators.amount,
                onFieldSubmitted: (_) => _isSale ? _save() : null,
              ),
              const SizedBox(height: 16),
              const _FieldLabel('العملة'),
              if (_isSale)
                InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline),
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
              if (!_isSale && _needsRate) ...[
                const SizedBox(height: 16),
                const _FieldLabel('قيمة الصرف'),
                TextFormField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'مثال: 34.5',
                    helperText: 'كم ${_currency?.code ?? ''} مقابل 1 ${_invoiceCurrency ?? ''}',
                    errorText: _rateError,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const _FieldLabel('التاريخ'),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDay,
                child: InputDecorator(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.event_outlined),
                    helperText: _isEdit
                        ? 'الوقت: ${Dates.shortTime(widget.existing!.time)}'
                        : 'يُسجَّل الوقت تلقائياً عند الحفظ.',
                  ),
                  child: Text(isToday
                      ? 'اليوم · ${Dates.mediumDate(_day)}'
                      : Dates.fullDate(_day)),
                ),
              ),
              if (!_isSale) ...[
                const SizedBox(height: 16),
                const _FieldLabel('رقم الفاتورة (اختياري)'),
                TextFormField(
                  controller: _invoice,
                  maxLength: Validators.maxInvoice,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.tag)),
                ),
              ],
              const SizedBox(height: 8),
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

class _DecimalCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.');
    final firstDot = text.indexOf('.');
    if (firstDot != -1) {
      if (text.indexOf('.', firstDot + 1) != -1) return oldValue;
      if (text.length - firstDot - 1 > 2) return oldValue;
    }
    return newValue.copyWith(text: text);
  }
}