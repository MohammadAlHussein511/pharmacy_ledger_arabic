import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sync/initial_upload.dart';
import '../../sync/auto_sync.dart';
import '../../data/repositories/settings_repository.dart';
import '../../security/app_lock_controller.dart';
import '../../security/pin_service.dart';
import '../theme_controller.dart';
import '../widgets/common.dart';
import 'import_legacy_backup.dart';
import 'backup_actions.dart';
import 'pin_entry_screen.dart';
import 'warehouses_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  Future<void> _importLegacyBackup(BuildContext context) async {
    await showImportLegacyBackupDialog(context);
  }
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final lock = context.watch<AppLockController>();
    final t = Theme.of(context).textTheme;

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(text,
              style: t.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            header('الحساب'),
            const _AccountCard(),
            header('الأمان'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.lock_outline),
                    title: const Text('قفل التطبيق'),
                    subtitle: const Text('يتطلب رمز PIN لفتح التطبيق'),
                    value: lock.lockEnabled,
                    onChanged: (v) =>
                        v ? _enableLock(context) : _disableLock(context),
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
                    subtitle: Text(
                        'القفل عند العمل في الخلفية: ${_timeoutLabel(lock.timeout)}'),
                    enabled: lock.lockEnabled,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickTimeout(context),
                  ),
                ],
              ),
            ),
            header('النسخ الاحتياطي'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.sync_outlined),
                    title: const Text('مزامنة الآن'),
                    subtitle: const Text('تنزيل ورفع فوري مع السحابة'),
                    onTap: () async {
                      final sync = AutoSync.current;
                      if (sync == null) {
                        showMessage(context, 'المزامنة غير مفعلة بعد.');
                        return;
                      }
                      showMessage(context, 'جارٍ المزامنة...');
                      final msg = await sync.syncNow();
                      if (context.mounted) showMessage(context, msg);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('إنشاء نسخة احتياطية'),
                    subtitle: const Text('احفظ ملف النسخة الاحتياطية'),
                    onTap: () => createBackupFlow(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: const Text('استعادة نسخة احتياطية'),
                    subtitle: const Text('استبدال البيانات الحالية'),
                    onTap: () => restoreBackupFlow(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('رفع البيانات للسحابة'),
                    subtitle:
                        const Text('رفع كل البيانات المحلية إلى Supabase'),
                    onTap: () => runInitialUpload(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('استيراد بيانات المدير'),
                    subtitle:
                        const Text('دمج البيانات من نسخة احتياطية قديمة'),
                    onTap: () => _importLegacyBackup(context),
                  ),
                ],
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
        return t.label;
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
    final pin =
        await askCurrentPin(context, pins: lock.pins, title: 'تأكيد رمز PIN');
    if (pin == null) return;
    final r = await lock.disableAppLock(pin);
    if (context.mounted && r is PinOk) {
      showMessage(context, 'تم إيقاف قفل التطبيق.');
    }
  }

  Future<void> _changePin(BuildContext context) async {
    final lock = context.read<AppLockController>();
    final current = await askCurrentPin(context,
        pins: lock.pins, title: 'أدخل رمز PIN الحالي');
    if (current == null || !context.mounted) return;
    final next = await createNewPin(context, title: 'رمز PIN الجديد');
    if (next == null) return;
    final r = await lock.changePin(current, next);
    if (context.mounted) {
      showMessage(
          context, r is PinOk ? 'تم تغيير رمز PIN.' : pinResultMessage(r));
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
                  Icon(
                      t == lock.timeout
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20),
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

// ======================================================================
// بطاقة الحساب
// ======================================================================
class _AccountCard extends StatefulWidget {
  const _AccountCard();

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  bool _signedIn = Supabase.instance.client.auth.currentSession != null;
  String? _displayName;
  String? _email;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() => _signedIn = state.session != null);
      _loadUserInfo();
    });
  }

  void _loadUserInfo() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final meta = user.userMetadata ?? {};
    setState(() {
      _displayName = (meta['full_name'] ?? meta['name'] ?? '') as String?;
      _email = user.email;
      _avatarUrl = (meta['avatar_url'] ?? meta['picture']) as String?;
    });
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text(
          'يمكنك الاستمرار في استخدام التطبيق بدون اتصال، '
          'لكن أي تعديلات أو إضافات جديدة لن تُرفع إلى جهاز المدير.\n\n'
          'بياناتك الحالية محفوظة على هذا الجهاز، وعند تسجيل الدخول مرة أخرى '
          'سيُعرض عليك دمج التعديلات التي أجريتها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) showMessage(context, 'تم تسجيل الخروج بنجاح.');
    } catch (e) {
      if (context.mounted) showMessage(context, 'تعذّر تسجيل الخروج: $e');
    }
  }

  Future<void> _signIn(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'pharmacyledger://auth-callback',
      );
    } catch (e) {
      if (context.mounted) {
        showMessage(context, 'تعذّر بدء تسجيل الدخول: $e');
      }
    }
  }

  Widget _buildAvatar(ColorScheme cs) {
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(_avatarUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    final initial = (_displayName ?? 'م').characters.first;
    return CircleAvatar(
      radius: 22,
      backgroundColor: cs.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w700,
            fontSize: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_signedIn) {
      return Card(
        child: ListTile(
          leading: _buildAvatar(cs),
          title: Text(_displayName ?? 'مستخدم'),
          subtitle: Text(_email ?? ''),
          trailing: TextButton.icon(
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('خروج'),
            onPressed: () => _signOut(context),
          ),
        ),
      );
    } else {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: cs.errorContainer,
            child: Icon(Icons.person_off, color: cs.onErrorContainer),
          ),
          title: const Text('غير مسجل الدخول'),
          subtitle: const Text('سجّل الدخول لمزامنة بياناتك مع المدير'),
          trailing: FilledButton.tonalIcon(
            icon: const Icon(Icons.login, size: 18),
            label: const Text('دخول'),
            onPressed: () => _signIn(context),
          ),
        ),
      );
    }
  }
}