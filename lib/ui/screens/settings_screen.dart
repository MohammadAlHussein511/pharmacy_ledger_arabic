import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repository.dart';
import '../../security/app_lock_controller.dart';
import '../../security/pin_service.dart';
import '../theme_controller.dart';
import '../widgets/common.dart';
import 'backup_actions.dart';
import 'pin_entry_screen.dart';
import 'warehouses_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final lock = context.watch<AppLockController>();
    final t = Theme.of(context).textTheme;

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(text,
              style: t.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            // ------------------------------------------------------ appearance
            header('المظهر'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_outlined)),
                  ButtonSegment(value: ThemeMode.system, label: Text('النظام'), icon: Icon(Icons.brightness_auto_outlined)),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
              ),
            ),
            // -------------------------------------------------------- security
            header('الأمان'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.lock_outline),
                    title: const Text('قفل التطبيق'),
                    subtitle: const Text('يتطلب رمز PIN لفتح التطبيق'),
                    value: lock.lockEnabled,
                    onChanged: (v) => v ? _enableLock(context) : _disableLock(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('تغيير رمز PIN'),
                    enabled: lock.lockEnabled,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePin(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('توقيت القفل'),
                    subtitle: Text('القفل عند العمل في الخلفية: ${_timeoutLabel(lock.timeout)}'),
                    enabled: lock.lockEnabled,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickTimeout(context),
                  ),
                ],
              ),
            ),
            // ---------------------------------------------------------- backup
            header('النسخ الاحتياطي'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('إنشاء نسخة احتياطية'),
                    subtitle: const Text('احفظ ملف النسخ الاحتياطي على هاتفك أو Google Drive أو أي مكان آخر'),
                    onTap: () => createBackupFlow(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: const Text('استعادة نسخة احتياطية'),
                    subtitle: const Text('استبدال البيانات الحالية بملف النسخ الاحتياطي'),
                    onTap: () => restoreBackupFlow(context),
                  ),
                ],
              ),
            ),
            // ------------------------------------------------------ warehouses
            header('المستودعات'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.warehouse_outlined),
                title: const Text('إدارة المستودعات'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const WarehousesScreen(standalone: true)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeoutLabel(LockTimeout t) {
  switch (t.seconds) {
    case 0:
      return 'فوراً';
    case 30:
      return 'بعد 30 ثانية';
    case 60:
      return 'بعد دقيقة واحدة';
    case 300:
      return 'بعد 5 دقائق';
    default:
      return t.label; // احتياطي
  }
}

  Future<void> _enableLock(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final pin = await createNewPin(context);
    if (pin == null) return;
    await lock.enableAppLock(pin);
    if (context.mounted) showMessage(context, 'تم تفعيل قفل التطبيق.');
  }

  Future<void> _disableLock(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final ok = await confirmDialog(
      context,
      title: 'إيقاف قفل التطبيق؟',
      message: 'سيتمكن أي شخص لديه الوصول إلى هذا الهاتف من فتح الدفتر.',
      confirmLabel: 'إيقاف',
    );
    if (!ok || !context.mounted) return;
    final pin = await askCurrentPin(context, pins: lock.pins, title: 'تأكيد رمز PIN');
    if (pin == null) return;
    final r = await lock.disableAppLock(pin);
    if (context.mounted && r is PinOk) showMessage(context, 'تم إيقاف قفل التطبيق.');
  }

  Future<void> _changePin(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final current = await askCurrentPin(context, pins: lock.pins, title: 'أدخل رمز PIN الحالي');
    if (current == null || !context.mounted) return;
    final next = await createNewPin(context, title: 'رمز PIN الجديد');
    if (next == null) return;
    final r = await lock.changePin(current, next);
    if (context.mounted) {
      showMessage(context, r is PinOk ? 'تم تغيير رمز PIN.' : pinResultMessage(r));
    }
  }

  Future<void> _pickTimeout(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final picked = await showDialog<LockTimeout>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('القفل عند العمل في الخلفية'),
        children: [
          for (final t in LockTimeout.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(
                children: [
                  Icon(t == lock.timeout ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                  const SizedBox(width: 12),
                  Text(_timeoutLabel(t)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await lock.setTimeout(picked);
  }
}
