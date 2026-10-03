import 'package:flutter/widgets.dart';

import '../data/repositories/settings_repository.dart';
import 'biometric_service.dart';
import 'pin_service.dart';

class UnlockResult {
  const UnlockResult.success()
      : success = true,
        message = null;
  const UnlockResult.failure(this.message) : success = false;

  final bool success;
  final String? message;
}

class SecurityMessages {
  SecurityMessages._();
  
  // [تم التعديل] - ترجمة جميع رسائل الأمان والبصمة
  static const noHardware =
      'هذا الجهاز لا يدعم مصادقة بصمة الإصبع. يرجى استخدام رمز PIN الخاص بك.';
  static const notEnrolled =
      'لا توجد بصمة مسجلة على هذا الجهاز. أضف واحدة من إعدادات Android، أو استخدم رمز PIN الخاص بك.';
  static const unavailable =
      'مصادقة البصمة غير متاحة مؤقتاً. يرجى استخدام رمز PIN الخاص بك.';
  static const cancelled = 'تم إلغاء المصادقة. يمكنك استخدام رمز PIN بدلاً من ذلك.';
  static const failed = 'لم يتم التعرف على البصمة. حاول مرة أخرى أو استخدم رمز PIN الخاص بك.';
  static const lockedOut =
      'محاولات كثيرة جداً. تم تعطيل البصمة مؤقتاً. يرجى استخدام رمز PIN الخاص بك.';
  static const permanentlyLockedOut =
      'البصمة مقفلة. افتح قفل هاتفك باستخدام قفل الشاشة أولاً، أو استخدم رمز PIN الخاص بك.';
  static const noDeviceCredential =
      'هاتفك لا يحتوي على قفل شاشة مُعيَّن. يرجى استخدام رمز PIN الخاص بك.';
  static const enrollmentChanged =
      'تم تغيير إعدادات بصمتك. لأمانك، تم إيقاف فتح البصمة. '
      'افتح باستخدام رمز PIN، ثم أعد تفعيلها من الإعدادات.';
  static const genericError = 'حدث خطأ ما في مصادقة البصمة. يرجى استخدام رمز PIN الخاص بك.';

  static String forOutcome(BiometricOutcome o) => switch (o) {
        BiometricOutcome.success => '',
        BiometricOutcome.cancelled => cancelled,
        BiometricOutcome.failed => failed,
        BiometricOutcome.notAvailable => unavailable,
        BiometricOutcome.notEnrolled => notEnrolled,
        BiometricOutcome.lockedOut => lockedOut,
        BiometricOutcome.permanentlyLockedOut => permanentlyLockedOut,
        BiometricOutcome.noDeviceCredential => noDeviceCredential,
        BiometricOutcome.enrollmentChanged => enrollmentChanged,
        BiometricOutcome.error => genericError,
      };

  static String forAvailability(BiometricAvailability a) => switch (a) {
        BiometricAvailability.available => '',
        BiometricAvailability.noHardware => noHardware,
        BiometricAvailability.notEnrolled => notEnrolled,
        BiometricAvailability.temporarilyUnavailable => unavailable,
      };
}

/// Owns the lock state of the app.
///  * Always locked after a cold start when App Lock is on.
///  * Locks again after being in the background longer than the chosen timeout.
///  * Ignores lifecycle changes caused by its own system dialogs
///    (biometric prompt, file picker, share sheet) so the user is not asked twice.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required SettingsRepository settings,
    required this.pins,
    required this.biometrics,
    DateTime Function()? clock,
  })  : _settings = settings,
        _clock = clock ?? DateTime.now;

  final SettingsRepository _settings;
  final PinService pins;
  final BiometricService biometrics;
  final DateTime Function() _clock;

  bool _ready = false;
  bool _locked = false;
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  LockTimeout _timeout = LockTimeout.minute1;
  DateTime? _backgroundedAt;
  int _suppressDepth = 0;
  String? _pendingMessage;

  bool get ready => _ready;
  bool get locked => _locked;
  bool get lockEnabled => _lockEnabled;
  bool get biometricEnabled => _biometricEnabled;
  LockTimeout get timeout => _timeout;

  /// A message to show on the lock screen (e.g. enrollment changed).
  String? takePendingMessage() {
    final m = _pendingMessage;
    _pendingMessage = null;
    return m;
  }

  Future<void> init() async {
    _lockEnabled = await _settings.appLockEnabled();
    _biometricEnabled = await _settings.biometricEnabled();
    _timeout = await _settings.lockTimeout();

    // Secure storage lost the PIN (e.g. device credentials reset) while the
    // lock flag survived: never lock the owner out of their own data.
    if (_lockEnabled && !await pins.hasPin()) {
      _lockEnabled = false;
      _biometricEnabled = false;
      await _settings.setAppLockEnabled(false);
      await _settings.setBiometricEnabled(false);
      _pendingMessage = null;
    }
    if (!_lockEnabled && _biometricEnabled) {
      _biometricEnabled = false;
      await _settings.setBiometricEnabled(false);
    }
    await _checkBiometricIntegrity();
    _locked = _lockEnabled;
    _ready = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockEnabled || _suppressDepth > 0) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= _clock();
        if (_timeout == LockTimeout.immediately && !_locked) {
          _locked = true;
          notifyListeners();
        }
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && !_locked && shouldLockAfter(_clock().difference(since))) {
          _locked = true;
          notifyListeners();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  bool shouldLockAfter(Duration away) => away.inSeconds >= _timeout.seconds;

  /// Run [action] (which may open a system UI) without triggering a lock.
  Future<T> runWithoutLocking<T>(Future<T> Function() action) async {
    _suppressDepth++;
    try {
      return await action();
    } finally {
      // Let the resume event that follows the system UI arrive first.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _suppressDepth--;
      _backgroundedAt = null;
    }
  }

  // ------------------------------------------------------------------ unlock

  Future<PinResult> unlockWithPin(String pin) async {
    final r = await pins.verify(pin);
    if (r is PinOk) _setUnlocked();
    return r;
  }

  Future<UnlockResult> unlockWithBiometric() async {
    if (!_biometricEnabled) return const UnlockResult.failure(null);
    if (!await _checkBiometricIntegrity()) {
      return UnlockResult.failure(takePendingMessage() ?? SecurityMessages.enrollmentChanged);
    }
    final availability = await biometrics.availability();
    if (availability != BiometricAvailability.available) {
      return UnlockResult.failure(SecurityMessages.forAvailability(availability));
    }
    final outcome = await runWithoutLocking(
        // [تم التعديل] - ترجمة رسالة مصادقة النظام
        () => biometrics.authenticate(reason: 'استخدم بصمتك للمتابعة.'));
    if (outcome == BiometricOutcome.success) {
      _setUnlocked();
      return const UnlockResult.success();
    }
    if (outcome == BiometricOutcome.notEnrolled) {
      await _disableBiometricInternal();
    }
    return UnlockResult.failure(SecurityMessages.forOutcome(outcome));
  }

  void _setUnlocked() {
    _locked = false;
    _backgroundedAt = null;
    notifyListeners();
  }

  /// Returns false (and turns biometric unlock off) if Android invalidated
  /// the guard key because fingerprints or the screen lock changed.
  Future<bool> _checkBiometricIntegrity() async {
    if (!_biometricEnabled) return true;
    final status = await biometrics.keyStatus();
    if (status == BiometricKeyStatus.invalidated || status == BiometricKeyStatus.missing) {
      await _disableBiometricInternal();
      _pendingMessage = SecurityMessages.enrollmentChanged;
      return false;
    }
    return true;
  }

  Future<void> _disableBiometricInternal() async {
    _biometricEnabled = false;
    await _settings.setBiometricEnabled(false);
    await biometrics.deleteKey();
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings

  /// Enables App Lock with a new PIN.
  Future<void> enableAppLock(String newPin) async {
    await pins.setPin(newPin);
    await _settings.setAppLockEnabled(true);
    _lockEnabled = true;
    notifyListeners();
  }

  /// Disabling requires the current PIN.
  Future<PinResult> disableAppLock(String currentPin) async {
    final r = await pins.verify(currentPin);
    if (r is PinOk) {
      await _disableBiometricInternal();
      await pins.clearPin();
      await _settings.setAppLockEnabled(false);
      _lockEnabled = false;
      _locked = false;
      notifyListeners();
    }
    return r;
  }

  Future<PinResult> changePin(String currentPin, String newPin) async {
    final r = await pins.verify(currentPin);
    if (r is PinOk) await pins.setPin(newPin);
    return r;
  }

  /// Enabling requires a successful biometric authentication through the
  /// system prompt. Returns null on success or a user-facing error message.
  Future<String?> enableBiometric() async {
    // [تم التعديل] - ترجمة رسالة الخطأ الأولى
    if (!_lockEnabled) return 'فعّل قفل التطبيق وعيّن رمز PIN أولاً.';
    final availability = await biometrics.availability();
    if (availability != BiometricAvailability.available) {
      return SecurityMessages.forAvailability(availability);
    }
    final outcome = await runWithoutLocking(
        // [تم التعديل] - ترجمة رسالة تأكيد البصمة
        () => biometrics.authenticate(reason: 'أكد بصمتك لتفعيل فتح البصمة.'));
    if (outcome != BiometricOutcome.success) {
      // [تم التعديل] - ترجمة رسائل فشل التفعيل
      return outcome == BiometricOutcome.cancelled
          ? 'لم يتم تفعيل فتح البصمة.'
          : SecurityMessages.forOutcome(outcome);
    }
    if (!await biometrics.createKey()) {
      // [تم التعديل] - ترجمة رسالة فشل إنشاء المفتاح
      return 'تعذّر تفعيل فتح البصمة على هذا الجهاز. يرجى المحاولة مرة أخرى.';
    }
    await _settings.setBiometricEnabled(true);
    _biometricEnabled = true;
    notifyListeners();
    return null;
  }

  /// Disabling requires the PIN.
  Future<PinResult> disableBiometric(String pin) async {
    final r = await pins.verify(pin);
    if (r is PinOk) await _disableBiometricInternal();
    return r;
  }

  Future<void> setTimeout(LockTimeout t) async {
    await _settings.setLockTimeout(t);
    _timeout = t;
    notifyListeners();
  }

  /// Manual "Lock now".
  void lockNow() {
    if (!_lockEnabled) return;
    _locked = true;
    notifyListeners();
  }
}
