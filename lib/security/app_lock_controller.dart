import 'package:flutter/widgets.dart';

import '../data/repositories/settings_repository.dart';
import 'pin_service.dart';

/// Owns the lock state of the app.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required SettingsRepository settings,
    required this.pins,
    DateTime Function()? clock,
  })  : _settings = settings,
        _clock = clock ?? DateTime.now;

  final SettingsRepository _settings;
  final PinService pins;
  final DateTime Function() _clock;

  bool _ready = false;
  bool _locked = false;
  bool _lockEnabled = false;
  LockTimeout _timeout = LockTimeout.minute1;
  DateTime? _backgroundedAt;
  int _suppressDepth = 0;

  bool get ready => _ready;
  bool get locked => _locked;
  bool get lockEnabled => _lockEnabled;
  LockTimeout get timeout => _timeout;

  Future<void> init() async {
    _lockEnabled = await _settings.appLockEnabled();
    _timeout = await _settings.lockTimeout();

    if (_lockEnabled && !await pins.hasPin()) {
      _lockEnabled = false;
      await _settings.setAppLockEnabled(false);
    }
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

  /// Run [action] without triggering the app lock (for system dialogs).
  Future<T> runWithoutLocking<T>(Future<T> Function() action) async {
    _suppressDepth++;
    try {
      return await action();
    } finally {
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

  void _setUnlocked() {
    _locked = false;
    _backgroundedAt = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings

  Future<void> enableAppLock(String newPin) async {
    await pins.setPin(newPin);
    await _settings.setAppLockEnabled(true);
    _lockEnabled = true;
    notifyListeners();
  }

  Future<PinResult> disableAppLock(String currentPin) async {
    final r = await pins.verify(currentPin);
    if (r is PinOk) {
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

  Future<void> setTimeout(LockTimeout t) async {
    await _settings.setLockTimeout(t);
    _timeout = t;
    notifyListeners();
  }
}