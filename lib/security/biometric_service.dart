import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

enum BiometricAvailability { available, noHardware, notEnrolled, temporarilyUnavailable }

enum BiometricOutcome {
  success,
  cancelled,
  failed,
  notAvailable,
  notEnrolled,
  lockedOut,
  permanentlyLockedOut,
  noDeviceCredential,
  enrollmentChanged,
  error,
}

/// Status of the Keystore "guard" key that is invalidated by Android as soon
/// as fingerprints are added/removed or the screen lock is reset.
enum BiometricKeyStatus { valid, invalidated, missing, error }

abstract class BiometricService {
  Future<BiometricAvailability> availability();
  Future<BiometricOutcome> authenticate({required String reason});
  Future<BiometricKeyStatus> keyStatus();
  Future<bool> createKey();
  Future<void> deleteKey();
}

/// Uses the official Android BiometricPrompt (through local_auth). The app
/// never sees or stores fingerprint data.
class PlatformBiometricService implements BiometricService {
  PlatformBiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;
  static const _channel = MethodChannel('com.pharmacy.ledger/biometric_key');

  @override
  Future<BiometricAvailability> availability() async {
    try {
      final hasHardware = await _auth.canCheckBiometrics;
      if (!hasHardware) return BiometricAvailability.noHardware;
      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) return BiometricAvailability.notEnrolled;
      return BiometricAvailability.available;
    } on PlatformException {
      return BiometricAvailability.temporarilyUnavailable;
    } catch (_) {
      return BiometricAvailability.temporarilyUnavailable;
    }
  }

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Unlock Pharmacy Ledger',
            biometricHint: '',
            cancelButton: 'Use PIN',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: false,
          useErrorDialogs: false,
        ),
      );
      return ok ? BiometricOutcome.success : BiometricOutcome.cancelled;
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.notAvailable:
          return BiometricOutcome.notAvailable;
        case auth_error.notEnrolled:
          return BiometricOutcome.notEnrolled;
        case auth_error.lockedOut:
          return BiometricOutcome.lockedOut;
        case auth_error.permanentlyLockedOut:
          return BiometricOutcome.permanentlyLockedOut;
        case auth_error.passcodeNotSet:
          return BiometricOutcome.noDeviceCredential;
        default:
          return BiometricOutcome.error;
      }
    } catch (_) {
      return BiometricOutcome.error;
    }
  }

  @override
  Future<BiometricKeyStatus> keyStatus() async {
    try {
      final s = await _channel.invokeMethod<String>('keyStatus');
      return switch (s) {
        'valid' => BiometricKeyStatus.valid,
        'invalidated' => BiometricKeyStatus.invalidated,
        'missing' => BiometricKeyStatus.missing,
        _ => BiometricKeyStatus.error,
      };
    } catch (_) {
      return BiometricKeyStatus.error;
    }
  }

  @override
  Future<bool> createKey() async {
    try {
      return await _channel.invokeMethod<bool>('createKey') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteKey() async {
    try {
      await _channel.invokeMethod<bool>('deleteKey');
    } catch (_) {}
  }
}
