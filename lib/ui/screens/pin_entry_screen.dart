import 'package:flutter/material.dart';

import '../../security/pin_service.dart';
import '../widgets/pin_pad.dart';

// [تم التعديل] - ترجمة رسائل حالة PIN
String pinResultMessage(PinResult r) => switch (r) {
      PinOk() => '',
      PinWrong(:final attemptsBeforeLockout) => attemptsBeforeLockout > 0
          ? 'رمز PIN غير صحيح. تبقى $attemptsBeforeLockout ${attemptsBeforeLockout == 1 ? 'محاولة' : 'محاولات'} قبل القفل المؤقت.'
          : 'رمز PIN غير صحيح.',
      PinLockedOut(:final until) => lockoutMessage(until),
    };

// [تم التعديل] - ترجمة رسالة القفل المؤقت مع الأرقام الغربية
String lockoutMessage(DateTime until) {
  final raw = until.difference(DateTime.now()).inSeconds;
  final secs = raw < 1 ? 1 : raw;
  final text = secs >= 60 ? '${(secs / 60).ceil()} دقيقة' : '$secs ثانية';
  return 'محاولات خاطئة كثيرة. حاول مرة أخرى بعد $text.';
}

/// Asks for the current PIN. Returns the verified PIN, or null if cancelled.
Future<String?> askCurrentPin(
  BuildContext context, {
  required PinService pins,
  // [تم التعديل] - ترجمة العنوان الافتراضي
  String title = 'أدخل رمز PIN',
}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _VerifyPinScreen(pins: pins, title: title),
  ));
}

class _VerifyPinScreen extends StatefulWidget {
  const _VerifyPinScreen({required this.pins, required this.title});
  final PinService pins;
  final String title;

  @override
  State<_VerifyPinScreen> createState() => _VerifyPinScreenState();
}

class _VerifyPinScreenState extends State<_VerifyPinScreen> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 12),
                Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: Text(_error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                PinPad(onSubmit: (pin) async {
                  final r = await widget.pins.verify(pin);
                  if (!mounted) return true;
                  if (r is PinOk) {
                    Navigator.pop(context, pin);
                    return false;
                  }
                  setState(() => _error = pinResultMessage(r));
                  return true;
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Create a new PIN (enter + confirm). Returns the new PIN or null.
Future<String?> createNewPin(BuildContext context, {
  // [تم التعديل] - ترجمة العنوان الافتراضي
  String title = 'إنشاء رمز PIN للتطبيق'
}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _CreatePinScreen(title: title),
  ));
}

class _CreatePinScreen extends StatefulWidget {
  const _CreatePinScreen({required this.title});
  final String title;

  @override
  State<_CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<_CreatePinScreen> {
  String? _first;
  String? _error;
  final _padKey = GlobalKey<PinPadState>();

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.pin_outlined, size: 40),
                const SizedBox(height: 12),
                // [تم التعديل] - ترجمة عناوين شاشة إنشاء PIN
                Text(confirming ? 'تأكيد رمز PIN' : 'اختر رمز PIN مكون من 4 إلى 8 أرقام',
                    style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                // [تم التعديل] - ترجمة النص التوضيحي
                const Text('ستستخدم رمز PIN هذا إذا لم يكن فتح البصمة متاحاً.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: Text(_error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                PinPad(
                  key: _padKey,
                  onSubmit: (pin) async {
                    if (_first == null) {
                      setState(() {
                        _first = pin;
                        _error = null;
                      });
                      return true;
                    }
                    if (pin != _first) {
                      setState(() {
                        _first = null;
                        // [تم التعديل] - ترجمة رسالة عدم تطابق PIN
                        _error = 'رموز PIN غير متطابقة. يرجى المحاولة مرة أخرى.';
                      });
                      return true;
                    }
                    Navigator.pop(context, pin);
                    return false;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
