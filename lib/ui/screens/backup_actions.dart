import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../backup/backup_service.dart';
import '../../core/dates.dart';
import '../../security/app_lock_controller.dart';
import '../../services.dart';
import '../widgets/common.dart';

// ------------------------------------------------------------------- create

Future<void> createBackupFlow(BuildContext context) async {
  final services = context.read<AppServices>();
  final lock = context.read<AppLockController>();

  final password = await _askBackupPassword(context);
  if (password == null || !context.mounted) return; // cancelled

  final destination = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('أين تريد حفظ النسخة الاحتياطية؟')),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('حفظ على الجهاز'),
            subtitle: const Text('اختر مجلداً على هذا الهاتف'),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('مشاركة'),
            subtitle: const Text('Google Drive أو البريد الإلكتروني أو تطبيق آخر'),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (destination == null || !context.mounted) return;

  _showProgress(context, 'جارٍ إنشاء النسخة الاحتياطية...');
  Uint8List bytes;
  try {
    bytes = await services.backup.createBackup(password: password.isEmpty ? null : password);
  } catch (_) {
    if (context.mounted) {
      Navigator.pop(context);
      showMessage(context, 'تعذّر إنشاء النسخة الاحتياطية. يرجى المحاولة مرة أخرى.');
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.pop(context); // progress

  final name = services.backup.suggestedFileName();
  try {
    if (destination == 'save') {
      final path = await lock.runWithoutLocking(() => FilePicker.platform.saveFile(
            dialogTitle: 'حفظ النسخة الاحتياطية',
            fileName: name,
            bytes: bytes,
          ));
      if (context.mounted) {
        showMessage(context, path == null ? 'لم يتم حفظ النسخة الاحتياطية.' : 'تم حفظ النسخة الاحتياطية بنجاح.');
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      final result = await lock.runWithoutLocking(() => Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/json', name: name)],
            subject: 'نسخة احتياطية لدفتر الصيدلية',
          ));
      if (context.mounted && result.status == ShareResultStatus.success) {
        showMessage(context, 'تمت مشاركة النسخة الاحتياطية بنجاح.');
      }
    }
  } catch (_) {
    if (context.mounted) showMessage(context, 'تعذّر حفظ ملف النسخة الاحتياطية. يرجى المحاولة مرة أخرى.');
  }
}

/// Returns '' for "no password", a password, or null when cancelled.
Future<String?> _askBackupPassword(BuildContext context) {
  return showDialog<String>(context: context, builder: (_) => const _BackupPasswordDialog());
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog();

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  bool _protect = true;
  final _pwd = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إنشاء نسخة احتياطية'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('حماية بكلمة مرور'),
                subtitle: const Text('موصى به. النسخة الاحتياطية مشفرة ولا يمكن قراءتها بدون كلمة المرور.'),
                value: _protect,
                onChanged: (v) => setState(() => _protect = v),
              ),
              if (_protect) ...[
                TextFormField(
                  controller: _pwd,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة مرور النسخة الاحتياطية'),
                  validator: (v) =>
                      (v ?? '').length < 6 ? 'استخدم 6 أحرف على الأقل.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                  validator: (v) => v != _pwd.text ? 'كلمتا المرور غير متطابقتين.' : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'احتفظ بكلمة المرور في مكان آمن. بدونها لا يمكن استعادة النسخة الاحتياطية.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () {
            if (_protect && !_formKey.currentState!.validate()) return;
            Navigator.pop(context, _protect ? _pwd.text : '');
          },
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ restore

Future<void> restoreBackupFlow(BuildContext context) async {
  final services = context.read<AppServices>();
  final lock = context.read<AppLockController>();

  FilePickerResult? picked;
  try {
    picked = await lock.runWithoutLocking(
        () => FilePicker.platform.pickFiles(type: FileType.any, withData: true));
  } catch (_) {
    if (context.mounted) showMessage(context, 'تعذّر فتح الملف.');
    return;
  }
  final file = picked?.files.single;
  if (file == null || !context.mounted) return;
  Uint8List? bytes = file.bytes;
  if (bytes == null && file.path != null) bytes = await File(file.path!).readAsBytes();
  if (bytes == null || !context.mounted) {
    if (context.mounted) showMessage(context, BackupMessages.notABackup);
    return;
  }

  // 1) Validate before touching anything.
  BackupPreview? preview;
  String? password;
  while (preview == null) {
    if (!context.mounted) return;
    _showProgress(context, 'جارٍ فحص النسخة الاحتياطية...');
    try {
      preview = await services.backup.inspect(bytes, password: password);
      if (context.mounted) Navigator.pop(context);
    } on BackupPasswordRequired {
      if (!context.mounted) return;
      Navigator.pop(context);
      password = await _askRestorePassword(context, null);
      if (password == null) return;
    } on BackupException catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      if (e.message == BackupMessages.wrongPassword) {
        password = await _askRestorePassword(context, e.message);
        if (password == null) return;
      } else {
        await _showError(context, e.message);
        return;
      }
    }
  }
  if (!context.mounted) return;

  // 2) Explicit confirmation. Never overwrite silently.
  final created = preview.createdAt == null ? 'تاريخ غير معروف' : Dates.mediumDate(preview.createdAt!);
  final ok = await confirmDialog(
    context,
    title: 'استعادة نسخة احتياطية',
    message: 'نسخة احتياطية من $created\n'
        '${preview.transactionCount} عملية · ${preview.warehouseCount} مستودع\n\n'
        'استعادة هذه النسخة ستستبدل بيانات التطبيق الحالية. هل تريد المتابعة؟',
    confirmLabel: 'استعادة',
    destructive: true,
  );
  if (!ok || !context.mounted) return;

  // 3) Safety snapshot of current data, then atomic replace.
  _showProgress(context, 'جارٍ الاستعادة...');
  try {
    final dir = await getApplicationDocumentsDirectory();
    final safety = Directory(p.join(dir.path, 'safety_backups'));
    await safety.create(recursive: true);
    final snapshot = await services.backup.createBackup();
    await File(p.join(safety.path, 'before-restore-${services.backup.suggestedFileName()}'))
        .writeAsBytes(snapshot, flush: true);
    await _pruneSafetyBackups(safety);

    await services.backup.restore(preview);
    services.store.changed();
    if (context.mounted) {
      Navigator.pop(context);
      showMessage(context, 'تمت استعادة النسخة الاحتياطية بنجاح.');
    }
  } on BackupException catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      await _showError(context, e.message);
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.pop(context);
      await _showError(context, BackupMessages.restoreFailed);
    }
  }
}

Future<void> _pruneSafetyBackups(Directory dir) async {
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final f in files.skip(3)) {
    try {
      await f.delete();
    } catch (_) {}
  }
}

Future<String?> _askRestorePassword(BuildContext context, String? error) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('كلمة مرور النسخة الاحتياطية'),
      content: TextField(
        controller: c,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'أدخل كلمة المرور لهذه النسخة',
          errorText: error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('متابعة'),
        ),
      ],
    ),
  );
}

Future<void> _showError(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Text(message),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );

void _showProgress(BuildContext context, String text) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
}
