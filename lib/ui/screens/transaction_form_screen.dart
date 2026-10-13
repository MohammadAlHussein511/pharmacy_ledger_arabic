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

  // [جديد] رصيد المستودع (إجمالي الفواتير - الدفعات)
  int _warehouseRemainingMinor = 0;
  String? _warehouseInvoiceCurrency;
  bool _loadingWarehouse = false;

  bool get _isSale => widget.type == TransactionType.sale;
  bool get _isEdit => widget.existing != null;

  // هل نحتاج قيمة صرف؟
  bool get _needsRate {
    if (_isSale || _warehouseInvoiceCurrency == null || _currency == null) return false;
    return _warehouseInvoiceCurrency != _currency!.code;
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
            _loadWarehouseBalance(whId);
          }
        });
      }
    }
  }

  // [جديد] حساب رصيد المستودع الموحد
  Future<void> _loadWarehouseBalance(int warehouseId) async {
    if (_isSale) return;
    setState(() => _loadingWarehouse = true);
    try {
      final services = context.read<AppServices>();
      
      // إجمالي الفواتير للمستودع
      final invoicesResult = await services.db.rawQuery('''
        SELECT currency, SUM(amount_minor) as total
        FROM invoices
        WHERE warehouse_id = ?
        GROUP BY currency
      ''', [warehouseId]);

      // إجمالي الدفعات للمستودع (مع تحويل العملات)
      final paymentsResult = await services.db.rawQuery('''
        SELECT 
          i.currency as invoice_currency,
          ip.currency_paid,
          SUM(ip.amount_minor) as paid_amount,
          ip.exchange_rate
        FROM invoice_payments ip
        JOIN invoices i ON ip.invoice_id = i.id
        WHERE i.warehouse_id = ?
        GROUP BY i.currency, ip.currency_paid, ip.exchange_rate
      ''', [warehouseId]);

      // حساب الرصيد
      Map<String, int> invoiceTotals = {};
      for (final r in invoicesResult) {
        final cur = r['currency'] as String;
        final total = (r['total'] as num).toInt();
        invoiceTotals[cur] = total;
      }

      Map<String, int> paidTotals = {};
      for (final r in paymentsResult) {
        final invCur = r['invoice_currency'] as String;
        final paidCur = r['currency_paid'] as String;
        final paidAmount = (r['paid_amount'] as num).toInt();
        final rate = r['exchange_rate'] as double?;

        int equivalent;
        if (paidCur == invCur) {
          equivalent = paidAmount;
        } else if (rate != null && rate > 0) {
          equivalent = (paidAmount / rate).round();
        } else {
          equivalent = paidAmount;
        }
        paidTotals[invCur] = (paidTotals[invCur] ?? 0) + equivalent;
      }

      // الرصيد المتبقي
      int remaining = 0;
      String? invoiceCurrency;
      if (invoiceTotals.isNotEmpty) {
        invoiceCurrency = invoiceTotals.keys.first;
        final totalInvoices = invoiceTotals[invoiceCurrency] ?? 0;
        final totalPaid = paidTotals[invoiceCurrency] ?? 0;
        remaining = totalInvoices - totalPaid;
      }

      if (!mounted) return;
      setState(() {
        _warehouseRemainingMinor = remaining;
        _warehouseInvoiceCurrency = invoiceCurrency;
        _loadingWarehouse = false;
      });
    } catch (e) {
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
      _loadWarehouseBalance(w.id!);
    }
  }

  // [جديد] ربط الدفع بالفواتير تلقائياً (FIFO)
  Future<void> _autoLinkToFIFOInvoices({
    required int amountMinor,
    required String currency,
    required int warehouseId,
    required double? exchangeRate,
  }) async {
    final services = context.read<AppServices>();
    final db = services.db;

    // جلب الفواتير غير المدفوعة بالكامل
    final invoices = await db.rawQuery('''
      SELECT i.id, i.currency, i.amount_minor,
        COALESCE((
          SELECT SUM(
            CASE
              WHEN ip.currency_paid = i.currency THEN ip.amount_minor
              WHEN ip.exchange_rate IS NOT NULL AND ip.exchange_rate > 0
                THEN CAST(ROUND(ip.amount_minor * 1.0 / ip.exchange_rate) AS INTEGER)
              ELSE 0
            END
          ) FROM invoice_payments ip WHERE ip.invoice_id = i.id
        ), 0) as paid_minor
      FROM invoices i
      WHERE i.warehouse_id = ?
      ORDER BY i.invoice_date ASC, i.id ASC
    ''', [warehouseId]);

    final list = <Map<String, dynamic>>[];
    for (final r in invoices) {
      final amount = r['amount_minor'] as int;
      final paid = (r['paid_minor'] as num).toInt();
      if (paid < amount) {
        list.add({
          'id': r['id'],
          'currency': r['currency'],
          'amount': amount,
          'paid': paid,
          'remaining': amount - paid,
        });
      }
    }

    int remainingToApply = amountMinor;
    final now = DateTime.now().toIso8601String();
    final today = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final paymentDate = '${today.year}-${two(today.month)}-${two(today.day)}';
    final paymentTime = '${two(today.hour)}:${two(today.minute)}';

    for (final inv in list) {
      if (remainingToApply <= 0) break;
      final invRemaining = inv['remaining'] as int;
      final invCurrency = inv['currency'] as String;

      int paymentAmount;
      double? rateToUse;

      if (currency == invCurrency) {
        paymentAmount = remainingToApply < invRemaining ? remainingToApply : invRemaining;
      } else {
        if (exchangeRate == null || exchangeRate <= 0) continue;
        rateToUse = exchangeRate;
        final maxInPaidCurrency = (invRemaining * exchangeRate).round();
        paymentAmount = remainingToApply < maxInPaidCurrency ? remainingToApply : maxInPaidCurrency;
      }

      if (paymentAmount <= 0) continue;

      await db.insert('invoice_payments', {
        'invoice_id': inv['id'],
        'amount_minor': paymentAmount,
        'currency_paid': currency,
        'exchange_rate': rateToUse,
        'note': 'خصم تلقائي من دفعة',
        'payment_date': paymentDate,
        'payment_time': paymentTime,
        'created_at': now,
        'updated_at': now,
      });

      remainingToApply -= paymentAmount;
    }
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

    // [جديد] التحقق من قيمة الصرف
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

    // [جديد] منع التجاوز: التحقق من أن الدفعة لا تتجاوز الرصيد المتبقي
    if (!_isSale && _warehouseRemainingMinor > 0) {
      int equivalentMinor = minor;
      if (_needsRate && rateValue != null && rateValue > 0) {
        equivalentMinor = (minor / rateValue).round();
      }
      
      if (equivalentMinor > _warehouseRemainingMinor) {
        setState(() {
          _amountError = 'الدفعة (${Money.format(equivalentMinor, _warehouseInvoiceCurrency ?? 'USD')}) '
              'تتجاوز الرصيد المتبقي (${Money.format(_warehouseRemainingMinor, _warehouseInvoiceCurrency ?? 'USD')})';
        });
        return;
      }
    }

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
        final tx = LedgerTransaction.newPayment(
          amountMinor: minor,
          currency: _currency!,
          warehouseId: _warehouse!.id!,
          invoiceNumber: _invoice.text,
          note: _note.text,
          day: _day,
          now: now,
        );
        await repo.insert(tx);
        await services.settings.setLastPaymentCurrency(_currency!);

        // ربط FIFO بالفواتير تلقائياً
        if (_warehouseRemainingMinor > 0) {
          try {
            await _autoLinkToFIFOInvoices(
              amountMinor: minor,
              currency: _currency!.code,
              warehouseId: _warehouse!.id!,
              exchangeRate: rateValue,
            );
          } catch (e) {
            debugPrint('[FIFO] error: $e');
          }
        }
      }

      if (!mounted) return;
      String msg;
      if (_isEdit) {
        msg = 'تم حفظ التغييرات.';
      } else if (_isSale) {
        msg = 'تم حفظ البيع.';
      } else {
        msg = _warehouseRemainingMinor > 0
            ? 'تم حفظ الدفعة وخصمها من الفواتير تلقائياً.'
            : 'تم حفظ الدفعة.';
      }
      showMessage(context, msg);
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
                        _loadWarehouseBalance(w.id!);
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة مستودع جديد'),
                  ),
                ),
                // [جديد] بطاقة معلومات الرصيد الموحد
                if (_loadingWarehouse)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_warehouseRemainingMinor > 0 && _warehouse != null) ...[
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
                            'الرصيد المتبقي على ${_warehouse!.name}: '
                            '${Money.format(_warehouseRemainingMinor, _warehouseInvoiceCurrency ?? 'USD')}',
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
              // [جديد] حقل الصرف - يظهر عند الحاجة
              if (!_isSale && _needsRate) ...[
                const SizedBox(height: 16),
                const _FieldLabel('قيمة الصرف'),
                TextFormField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'مثال: 34.5',
                    helperText:
                        'كم ${_currency?.code ?? ''} مقابل 1 ${_warehouseInvoiceCurrency ?? ''}',
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
                  child: Text(isToday ? 'اليوم · ${Dates.mediumDate(_day)}' : Dates.fullDate(_day)),
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