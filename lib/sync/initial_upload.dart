import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_service.dart';
import '../services.dart';
import '../ui/widgets/common.dart';

/// يرفع كل البيانات المحلية إلى السحابة (استخدام لمرة واحدة).
Future<void> runInitialUpload(BuildContext context) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const _InitialUploadScreen()),
  );
}

class _InitialUploadScreen extends StatefulWidget {
  const _InitialUploadScreen();

  @override
  State<_InitialUploadScreen> createState() => _InitialUploadScreenState();
}

class _InitialUploadScreenState extends State<_InitialUploadScreen> {
  String _status = 'جاهز للرفع';
  int _warehousesTotal = 0;
  int _warehousesUploaded = 0;
  int _transactionsTotal = 0;
  int _transactionsUploaded = 0;
  int _skipped = 0;
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _status = 'جارٍ تجهيز البيانات المحلية...';
      _error = null;
    });

    try {
      final services = context.read<AppServices>();
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _error = 'يجب تسجيل الدخول أولاً';
          _busy = false;
        });
        return;
      }

      // 1) إنشاء نسخة احتياطية مؤقتة من البيانات المحلية
      setState(() => _status = 'قراءة البيانات المحلية...');
      final bytes = await services.backup.createBackup();
      final preview = await services.backup.inspect(bytes);

      final warehouses = preview.warehouses;
      final transactions = preview.transactions;

      if (!mounted) return;
      setState(() {
        _warehousesTotal = warehouses.length;
        _transactionsTotal = transactions.length;
        _status = 'فحص التكرار في السحابة...';
      });

      // 2) جلب السجلات الموجودة في السحابة لتجنب التكرار
      final existingWh = await supabase
          .from('warehouses')
          .select('name_key, id')
          .eq('is_deleted', false);
      final existingWhMap = <String, String>{
        for (final w in existingWh)
          (w['name_key'] as String): w['id'] as String,
      };

      final existingTx = await supabase
          .from('transactions')
          .select('invoice_number, transaction_date, amount_minor, currency')
          .eq('is_deleted', false);
      final existingTxKeys = <String>{
        for (final t in existingTx)
          '${t['invoice_number']}_${t['transaction_date']}_'
              '${t['amount_minor']}_${t['currency']}',
      };

      // 3) رفع المستودعات
      setState(() => _status = 'جارٍ رفع المستودعات...');
      final whMapping = <int, String>{};
      for (final wh in warehouses) {
        final name = wh['name'] as String;
        final nameKey = name.toLowerCase().trim();
        if (existingWhMap.containsKey(nameKey)) {
          whMapping[wh['id'] as int] = existingWhMap[nameKey]!;
          _skipped++;
        } else {
          final newId = _uuid();
          await supabase.from('warehouses').insert({
            'id': newId,
            'name': name,
            'name_key': nameKey,
            'is_active': wh['is_active'] ?? true,
            'created_by': userId,
            'updated_by': userId,
            'is_deleted': false,
          });
          whMapping[wh['id'] as int] = newId;
          existingWhMap[nameKey] = newId;
          _warehousesUploaded++;
        }
        if (mounted) setState(() {});
      }

      // 4) رفع العمليات
      setState(() => _status = 'جارٍ رفع العمليات...');
      for (final tx in transactions) {
        final key = '${tx['invoice_number']}_${tx['transaction_date']}_'
            '${tx['amount_minor']}_${tx['currency']}';
        if (existingTxKeys.contains(key)) {
          _skipped++;
          continue;
        }

        final oldWhId = tx['warehouse_id'] as int?;
        final newWhId = oldWhId != null ? whMapping[oldWhId] : null;

        await supabase.from('transactions').insert({
          'id': _uuid(),
          'type': tx['type'] as String,
          'amount_minor': tx['amount_minor'] as int,
          'currency': tx['currency'] as String,
          'warehouse_id': newWhId,
          'invoice_number': tx['invoice_number'] as String?,
          'note': tx['note'] as String?,
          'transaction_date': tx['transaction_date'] as String,
          'transaction_time': tx['transaction_time'] as String,
          'created_by': userId,
          'updated_by': userId,
          'is_deleted': false,
        });
        existingTxKeys.add(key);
        _transactionsUploaded++;
        if (mounted) setState(() {});
      }

      if (!mounted) return;
      setState(() {
        _status = 'تم الرفع بنجاح!';
        _busy = false;
      });
      showMessage(context,
          'تم الرفع: ${_warehousesUploaded} مستودع + $_transactionsUploaded عملية (تخطى $_skipped مكرر).');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'فشل الرفع: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الرفع الأولي للسحابة')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الرفع الأولي', style: t.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                        'سيتم رفع جميع بياناتك المحلية (بما فيها بيانات المدير المدمجة) '
                        'إلى قاعدة البيانات السحابية.\n\n'
                        'السجلات الموجودة مسبقاً لن تُكرر.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الحالة', style: t.titleSmall),
                      const SizedBox(height: 8),
                      Text(_status),
                      const SizedBox(height: 12),
                      _ProgressRow(
                          label: 'المستودعات',
                          done: _warehousesUploaded,
                          total: _warehousesTotal),
                      _ProgressRow(
                          label: 'العمليات',
                          done: _transactionsUploaded,
                          total: _transactionsTotal),
                      if (_skipped > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('تم تخطي $_skipped سجل مكرر',
                              style: t.bodySmall),
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy ? 'جارٍ الرفع...' : 'ابدأ الرفع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.done,
    required this.total,
  });
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : 0,
            ),
          ),
          const SizedBox(width: 8),
          Text('$done / $total'),
        ],
      ),
    );
  }
}

String _uuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rand = now ^ (DateTime.now().millisecondsSinceEpoch << 16);
  String hex(int n, int len) => n.toRadixString(16).padLeft(len, '0');
  return '${hex((rand >> 48) & 0xFFFF, 4)}${hex((rand >> 32) & 0xFFFF, 4)}-'
      '${hex((rand >> 16) & 0xFFFF, 4)}-'
      '${hex(rand & 0xFFFF, 4)}-'
      '${hex((now >> 16) & 0xFFFF, 4)}-'
      '${hex(now & 0xFFFF, 4)}${hex((now >> 32) & 0xFFFF, 4)}${hex((now >> 48) & 0xFFFF, 4)}';
}