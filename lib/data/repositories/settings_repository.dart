import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/currency.dart';

/// How long the app may stay in the background before it locks again.
enum LockTimeout {
  immediately(0, 'Immediately'),
  seconds30(30, 'After 30 seconds'),
  minute1(60, 'After 1 minute'),
  minutes5(300, 'After 5 minutes');

  const LockTimeout(this.seconds, this.label);
  final int seconds;
  final String label;

  static LockTimeout fromSeconds(int? s) =>
      LockTimeout.values.firstWhere((t) => t.seconds == s, orElse: () => LockTimeout.minute1);
}

/// Non-sensitive preferences live in SharedPreferences; security flags live
/// in encrypted secure storage (Android Keystore backed) so they cannot be
/// flipped by editing a plain preferences file.
class SettingsRepository {
  SettingsRepository(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const _kTheme = 'theme_mode';
  static const _kOnboarded = 'onboarding_done';
  static const _kLastCurrency = 'last_payment_currency';
  static const _kLockEnabled = 'sec_app_lock_enabled';
  static const _kBiometric = 'sec_biometric_enabled';
  static const _kTimeout = 'sec_lock_timeout';

  ThemeMode get themeMode => switch (_prefs.getString(_kTheme)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode m) => _prefs.setString(_kTheme, m.name);

  bool get onboardingDone => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboarded, true);

  Currency? get lastPaymentCurrency => Currency.tryFromCode(_prefs.getString(_kLastCurrency));
  Future<void> setLastPaymentCurrency(Currency c) => _prefs.setString(_kLastCurrency, c.code);

  Future<bool> appLockEnabled() async => (await _read(_kLockEnabled)) == 'true';
  Future<void> setAppLockEnabled(bool v) => _secure.write(key: _kLockEnabled, value: '$v');

  Future<bool> biometricEnabled() async => (await _read(_kBiometric)) == 'true';
  Future<void> setBiometricEnabled(bool v) => _secure.write(key: _kBiometric, value: '$v');

  Future<LockTimeout> lockTimeout() async =>
      LockTimeout.fromSeconds(int.tryParse(await _read(_kTimeout) ?? ''));
  Future<void> setLockTimeout(LockTimeout t) =>
      _secure.write(key: _kTimeout, value: '${t.seconds}');

  Future<String?> _read(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      // Secure storage can become unreadable if device credentials were reset.
      // Fail safe: the caller treats a missing value as "off" and the lock
      // controller forces PIN re-setup where needed.
      return null;
    }
  }
}
