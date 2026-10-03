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
          const ListTile(title: Text('Where do you want to save the backup?')),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Save to device'),
            subtitle: const Text('Choose a folder on this phone'),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            subtitle: const Text('Google Drive, email, or another app'),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (destination == null || !context.mounted) return;

  _showProgress(context, 'Creating backup...');
  Uint8List bytes;
  try {
    bytes = await services.backup.createBackup(password: password.isEmpty ? null : password);
  } catch (_) {
    if (context.mounted) {
      Navigator.pop(context);
      showMessage(context, 'Could not create the backup. Please try again.');
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.pop(context); // progress

  final name = services.backup.suggestedFileName();
  try {
    if (destination == 'save') {
      final path = await lock.runWithoutLocking(() => FilePicker.platform.saveFile(
            dialogTitle: 'Save backup',
            fileName: name,
            bytes: bytes,
          ));
      if (context.mounted) {
        showMessage(context, path == null ? 'Backup was not saved.' : 'Backup saved successfully.');
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      final result = await lock.runWithoutLocking(() => Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/json', name: name)],
            subject: 'Pharmacy Ledger backup',
          ));
      if (context.mounted && result.status == ShareResultStatus.success) {
        showMessage(context, 'Backup shared successfully.');
      }
    }
  } catch (_) {
    if (context.mounted) showMessage(context, 'Could not save the backup file. Please try again.');
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
      title: const Text('Create Backup'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Protect with a password'),
                subtitle: const Text('Recommended. The backup is encrypted and cannot be read without it.'),
                value: _protect,
                onChanged: (v) => setState(() => _protect = v),
              ),
              if (_protect) ...[
                TextFormField(
                  controller: _pwd,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Backup password'),
                  validator: (v) =>
                      (v ?? '').length < 6 ? 'Use at least 6 characters.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) => v != _pwd.text ? 'Passwords do not match.' : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Keep this password safe. Without it the backup cannot be restored.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () {
            if (_protect && !_formKey.currentState!.validate()) return;
            Navigator.pop(context, _protect ? _pwd.text : '');
          },
          child: const Text('Continue'),
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
    if (context.mounted) showMessage(context, 'Could not open the file.');
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
    _showProgress(context, 'Checking backup...');
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
  final created = preview.createdAt == null ? 'unknown date' : Dates.mediumDate(preview.createdAt!);
  final ok = await confirmDialog(
    context,
    title: 'Restore Backup',
    message: 'Backup from $created\n'
        '${preview.transactionCount} transactions · ${preview.warehouseCount} warehouses\n\n'
        'Restoring this backup will replace the current application data. Do you want to continue?',
    confirmLabel: 'Restore',
    destructive: true,
  );
  if (!ok || !context.mounted) return;

  // 3) Safety snapshot of current data, then atomic replace.
  _showProgress(context, 'Restoring...');
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
      showMessage(context, 'Backup restored successfully.');
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
      title: const Text('Backup password'),
      content: TextField(
        controller: c,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Enter the password for this backup',
          errorText: error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}

Future<void> _showError(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup'),
        content: Text(message),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
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
