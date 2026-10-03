import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
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
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('فتح ببصمة الإصبع'),
                    subtitle: Text(lock.lockEnabled
                        ? 'افتح ببصمة إصبعك'
                        : 'فعّل قفل التطبيق أولاً'),
                    value: lock.biometricEnabled,
                    onChanged: lock.lockEnabled
                        ? (v) => v ? _enableBiometric(context) : _disableBiometric(context)
                        : null,
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
                    subtitle: Text('القفل عند العمل في الخلفية: ${lock.timeout.label.toLowerCase()}'),
                    enabled: lock.lockEnabled,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickTimeout(context),
                  ),
                  if (lock.lockEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_clock_outlined),
                      title: const Text('قفل الآن'),
                      onTap: lock.lockNow,
                    ),
                  ],
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
            // ----------------------------------------------------------- about
            header('حول'),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.menu_book_rounded),
                    title: Text(AppInfo.name),
                    subtitle: Text('الإصدار ${AppInfo.version} (${AppInfo.buildNumber})'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text(AppInfo.description),
                    subtitle: const Text('يعمل بدون إنترنت تماماً. لا يتطلب حساباً.'),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppInfo.name,
                      applicationVersion: AppInfo.version,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _enableBiometric(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final ok = await confirmDialog(
      context,
      title: 'تفعيل فتح بصمة الإصبع؟',
      message: 'ستتمكن من فتح دفتر الصيدلية ببصمة إصبعك. '
          'سيظل رمز PIN يعمل كخيار احتياطي. لا تغادر بيانات البصمة هاتفك.',
      confirmLabel: 'تفعيل',
    );
    if (!ok) return;
    final error = await lock.enableBiometric();
    if (context.mounted) showMessage(context, error ?? 'تم تفعيل فتح بصمة الإصبع.');
  }

  Future<void> _disableBiometric(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final pin = await askCurrentPin(context, pins: lock.pins, title: 'تأكيد رمز PIN');
    if (pin == null) return;
    final r = await lock.disableBiometric(pin);
    if (context.mounted && r is PinOk) showMessage(context, 'تم إيقاف فتح بصمة الإصبع.');
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
                  Text(t.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await lock.setTimeout(picked);
  }
}
