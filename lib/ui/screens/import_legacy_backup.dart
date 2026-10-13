import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../backup/backup_service.dart';
import '../../security/app_lock_controller.dart';
import '../../services.dart';
import '../widgets/common.dart';

/// يعرض شاشة استيراد النسخة الاحتياطية القديمة من تطبيق المدير.
Future<void> showImportLegacyBackupDialog(BuildContext context) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const _ImportLegacyScreen()),
  );
}

class _ImportLegacyScreen extends StatefulWidget {
  const _ImportLegacyScreen();

  @override
  State<_ImportLegacyScreen> createState() => _ImportLegacyScreenState();
}

class _ImportLegacyScreenState extends State<_ImportLegacyScreen> {
  final _pwdController = TextEditingController();
  String? _filePath;
  String? _fileName;
  BackupPreview? _preview;
  String? _error;
  bool _busy = false;
  int _imported = 0;

  Future<void> _pickFile() async {
    final lock = context.read<AppLockController>();
    FilePickerResult? result;
    try {
      result = await lock.runWithoutLocking(
        () => FilePicker.platform.pickFiles(type: FileType.any),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذّر فتح منتقي الملفات: $e');
      return;
    }
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _filePath = result!.files.single.path;
      _fileName = result!.files.single.name;
      _preview = null;
      _error = null;
    });
  }

  Future<void> _inspect() async {
    if (_filePath == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await File(_filePath!).readAsBytes();
      final services = context.read<AppServices>();
      final password =
          _pwdController.text.isEmpty ? null : _pwdController.text;
      final preview = await services.backup.inspect(bytes, password: password);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } on BackupPasswordRequired {
      if (!mounted) return;
      setState(() {
        _error = 'هذه النسخة محمية بكلمة مرور. أدخلها ثم اضغط "فحص".';
        _busy = false;
      });
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر قراءة الملف: $e';
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    if (_filePath == null || _preview == null) return;
    final ok = await confirmDialog(
      context,
      title: 'تأكيد الاستيراد',
      message:
          'سيتم استيراد ${_preview!.transactionCount} عملية '
          'و ${_preview!.warehouseCount} مستودع إلى التطبيق والسحابة.\n\n'
          'السجلات المتطابقة مع الموجودة حالياً لن تُكرر.',
      confirmLabel: 'استيراد',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _imported = 0;
    });

    try {
      final bytes = await File(_filePath!).readAsBytes();
      final services = context.read<AppServices>();
      final password =
          _pwdController.text.isEmpty ? null : _pwdController.text;
      final preview = await services.backup.inspect(bytes, password: password);
      if (!mounted) return;

      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;

      // جلب المستودعات الموجودة لتجنب التكرار
      final existingWarehouses = await supabase
          .from('warehouses')
          .select('name_key, id')
          .eq('is_deleted', false);
      final existingWhMap = <String, String>{
        for (final w in existingWarehouses) w['name_key'] as String: w['id'] as String
      };

      // جلب العمليات الموجودة لتجنب التكرار
      final existingTx = await supabase
          .from('transactions')
          .select('invoice_number, transaction_date, amount_minor, currency, warehouse_id')
          .eq('is_deleted', false);
      final existingTxKeys = <String>{
        for (final t in existingTx)
          '${t['invoice_number']}_${t['transaction_date']}_'
              '${t['amount_minor']}_${t['currency']}_${t['warehouse_id']}'
      };

      // استيراد المستودعات
      final warehouseMapping = <int, String>{}; // old_id -> new_id
      for (final wh in preview.warehouses) {
        final nameKey = (wh['name'] as String).toLowerCase().trim();
        if (existingWhMap.containsKey(nameKey)) {
          warehouseMapping[wh['id'] as int] = existingWhMap[nameKey]!;
        } else {
          final newId = const Uuid().v4();
          await supabase.from('warehouses').insert({
            'id': newId,
            'name': wh['name'] as String,
            'name_key': nameKey,
            'is_active': true,
            'created_by': currentUserId,
            'updated_by': currentUserId,
            'is_deleted': false,
          });
          warehouseMapping[wh['id'] as int] = newId;
          existingWhMap[nameKey] = newId;
          _imported++;
        }
      }

      // استيراد العمليات
      for (final tx in preview.transactions) {
        final key = '${tx['invoice_number']}_${tx['transaction_date']}_'
            '${tx['amount_minor']}_${tx['currency']}_${tx['warehouse_id']}';
        if (existingTxKeys.contains(key)) continue;

        final newWhId = tx['warehouse_id'] != null
            ? warehouseMapping[tx['warehouse_id'] as int]
            : null;

        await supabase.from('transactions').insert({
          'id': const Uuid().v4(),
          'type': tx['type'] as String,
          'amount_minor': tx['amount_minor'] as int,
          'currency': tx['currency'] as String,
          'warehouse_id': newWhId,
          'invoice_number': tx['invoice_number'] as String?,
          'note': tx['note'] as String?,
          'transaction_date': tx['transaction_date'] as String,
          'transaction_time': tx['transaction_time'] as String,
          'created_by': currentUserId,
          'updated_by': currentUserId,
          'is_deleted': false,
        });
        existingTxKeys.add(key);
        _imported++;
      }

      if (!mounted) return;
       services.store.changed();

      if (!mounted) return;
      showMessage(context, 'تم استيراد $_imported سجل بنجاح.');
      Navigator.pop(context);
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'فشل الاستيراد: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد بيانات المدير')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'استيراد نسخة احتياطية من التطبيق القديم',
                style: t.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'استخدم هذه الأداة لدمج البيانات التي أدخلها المدير في التطبيق القديم.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(_fileName ?? 'اختيار ملف النسخة الاحتياطية'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwdController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور (إذا كانت محمية)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    (_busy || _filePath == null) ? null : _inspect,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: const Text('فحص الملف'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_preview != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('محتويات النسخة الاحتياطية',
                            style: t.titleMedium),
                        const SizedBox(height: 8),
                        Text('المستودعات: ${_preview!.warehouseCount}'),
                        Text('العمليات: ${_preview!.transactionCount}'),
                        if (_preview!.createdAt != null)
                          Text('تاريخ الإنشاء: ${_preview!.createdAt}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.upload),
                  label: const Text('بدء الاستيراد'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pwdController.dispose();
    super.dispose();
  }
}

/// مولّد UUID بسيط (مضمن لتجنب الاعتماد على حزمة إضافية).
class Uuid {
  const Uuid();
  String v4() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = now ^ (DateTime.now().millisecondsSinceEpoch << 16);
    String hex(int n, int len) =>
        n.toRadixString(16).padLeft(len, '0');
    final s = StringBuffer()
      ..write(hex((rand >> 48) & 0xFFFF, 4))
      ..write(hex((rand >> 32) & 0xFFFF, 4))
      ..write('-')
      ..write(hex((rand >> 16) & 0xFFFF, 4))
      ..write('-')
      ..write(hex(rand & 0xFFFF, 4))
      ..write('-')
      ..write(hex((now >> 16) & 0xFFFF, 4))
      ..write('-')
      ..write(hex(now & 0xFFFF, 4))
      ..write(hex((now >> 32) & 0xFFFF, 4))
      ..write(hex((now >> 48) & 0xFFFF, 4));
    return s.toString();
  }
}