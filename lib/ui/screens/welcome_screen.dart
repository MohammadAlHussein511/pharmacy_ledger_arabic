import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../security/app_lock_controller.dart';
import '../widgets/common.dart';
import 'pin_entry_screen.dart';

/// First launch. No account, no registration.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _securityStep = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                      color: cs.primaryContainer, borderRadius: BorderRadius.circular(28)),
                  child: Icon(_securityStep ? Icons.lock_outline : Icons.menu_book_rounded,
                      size: 52, color: cs.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                // [تم التعديل] - ترجمة العناوين الرئيسية
                _securityStep ? 'احمِ دفترك' : 'مرحباً بك في دفتر الصيدلية',
                textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                // [تم التعديل] - ترجمة الوصف النصي
                _securityStep
                    ? 'عيّن رمز PIN للتطبيق حتى لا يتمكن سواك من فتح سجلك المالي. '
                        'يمكنك تفعيل فتح البصمة من الإعدادات لاحقاً.'
                    : AppInfo.tagline,
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(flex: 2),
              if (!_securityStep)
                FilledButton(
                  onPressed: () => setState(() => _securityStep = true),
                  // [تم التعديل] - ترجمة زر البدء
                  child: const Text('ابدأ الآن'),
                )
              else ...[
                FilledButton(
                  onPressed: () async {
                    final lock = context.read<AppLockController>();
                    final pin = await createNewPin(context);
                    if (pin == null || !context.mounted) return;
                    await lock.enableAppLock(pin);
                    // [تم التعديل] - ترجمة رسالة التفعيل
                    if (context.mounted) showMessage(context, 'تم تفعيل قفل التطبيق.');
                    await widget.onDone();
                  },
                  // [تم التعديل] - ترجمة زر إعداد PIN
                  child: const Text('إعداد رمز PIN للتطبيق'),
                ),
                const SizedBox(height: 8),
                // [تم التعديل] - ترجمة زر التخطي
                TextButton(onPressed: widget.onDone, child: const Text('تخطي الآن')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
