import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pbkdf2.dart';

sealed class PinResult {
  const PinResult();
}

class PinOk extends PinResult {
  const PinOk();
}

class PinWrong extends PinResult {
  const PinWrong(this.attemptsBeforeLockout);
  final int attemptsBeforeLockout;
}

class PinLockedOut extends PinResult {
  const PinLockedOut(this.until);
  final DateTime until;
}

/// Minimal key-value abstraction so tests can use an in-memory store.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore(this._s);
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// The PIN is never stored. Only a salted PBKDF2-HMAC-SHA256 hash is kept,
/// inside Android Keystore-encrypted secure storage. Repeated failures
/// trigger an escalating lockout.
class PinService {
  PinService(this._store, {this.iterations = 120000, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SecretStore _store;
  final int iterations;
  final DateTime Function() _clock;

  static const int minLength = 4;
  static const int maxLength = 8;
  static const int freeAttempts = 5;

  static const _kHash = 'pin_hash_v1';
  static const _kFails = 'pin_failed_attempts';
  static const _kLockUntil = 'pin_lock_until';

  static bool isValidFormat(String pin) =>
      RegExp('^\\d{$minLength,$maxLength}\$').hasMatch(pin);

  Future<bool> hasPin() async => (await _safeRead(_kHash)) != null;

  Future<void> setPin(String pin) async {
    if (!isValidFormat(pin)) {
      // [تم التعديل] - ترجمة رسالة خطأ تنسيق PIN
      throw ArgumentError('يجب أن يتكون رمز PIN من $minLength إلى $maxLength أرقام.');
    }
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hash = await _derive(pin, salt, iterations);
    final record = jsonEncode({
      'alg': 'pbkdf2-sha256',
      'it': iterations,
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
    });
    await _store.write(_kHash, record);
    await _resetFailures();
  }

  Future<void> clearPin() async {
    await _store.delete(_kHash);
    await _resetFailures();
  }

  Future<DateTime?> lockedUntil() async {
    final v = await _safeRead(_kLockUntil);
    final until = v == null ? null : DateTime.tryParse(v);
    if (until == null || !until.isAfter(_clock())) return null;
    return until;
  }

  Future<PinResult> verify(String pin) async {
    final until = await lockedUntil();
    if (until != null) return PinLockedOut(until);

    final raw = await _safeRead(_kHash);
    if (raw == null) return const PinWrong(0);
    final record = jsonDecode(raw) as Map<String, dynamic>;
    final salt = base64Decode(record['salt'] as String);
    final expected = base64Decode(record['hash'] as String);
    final actual = await _derive(pin, salt, record['it'] as int);

    if (constantTimeEquals(actual, expected)) {
      await _resetFailures();
      return const PinOk();
    }
    final fails = (int.tryParse(await _safeRead(_kFails) ?? '') ?? 0) + 1;
    await _store.write(_kFails, '$fails');
    if (fails >= freeAttempts) {
      final seconds = min(30 * pow(2, fails - freeAttempts).toInt(), 15 * 60);
      final lockUntil = _clock().add(Duration(seconds: seconds));
      await _store.write(_kLockUntil, lockUntil.toIso8601String());
      return PinLockedOut(lockUntil);
    }
    return PinWrong(freeAttempts - fails);
  }

  Future<void> _resetFailures() async {
    await _store.delete(_kFails);
    await _store.delete(_kLockUntil);
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _derive(String pin, List<int> salt, int iterations) {
    final pwd = utf8.encode(pin);
    return Isolate.run(() => pbkdf2Sha256(pwd, salt, iterations, 32));
  }
}
