import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_ledger/data/repositories/settings_repository.dart';
import 'package:pharmacy_ledger/security/app_lock_controller.dart';
import 'package:pharmacy_ledger/security/biometric_service.dart';
import 'package:pharmacy_ledger/security/pin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

class FakeBiometrics implements BiometricService {
  BiometricAvailability availabilityValue = BiometricAvailability.available;
  BiometricOutcome nextOutcome = BiometricOutcome.success;
  BiometricKeyStatus status = BiometricKeyStatus.valid;
  int prompts = 0;
  bool keyCreated = false;

  @override
  Future<BiometricAvailability> availability() async => availabilityValue;
  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    prompts++;
    return nextOutcome;
  }

  @override
  Future<BiometricKeyStatus> keyStatus() async => status;
  @override
  Future<bool> createKey() async {
    keyCreated = true;
    status = BiometricKeyStatus.valid;
    return true;
  }

  @override
  Future<void> deleteKey() async {
    keyCreated = false;
    status = BiometricKeyStatus.missing;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySecretStore secrets;
  late FakeBiometrics bio;
  late SettingsRepository settings;
  late DateTime clock;

  Future<AppLockController> newController() async {
    final c = AppLockController(
      settings: settings,
      pins: PinService(secrets, iterations: 1000, clock: () => clock),
      biometrics: bio,
      clock: () => clock,
    );
    await c.init();
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    settings = SettingsRepository(await SharedPreferences.getInstance(), const FlutterSecureStorage());
    secrets = MemorySecretStore();
    bio = FakeBiometrics();
    clock = DateTime(2026, 9, 29, 10);
  });

  group('PIN', () {
    test('stored only as a salted hash', () async {
      final pins = PinService(secrets, iterations: 1000);
      await pins.setPin('4821');
      expect(secrets.data.values.any((v) => v.contains('4821')), isFalse);
      expect(await pins.verify('4821'), isA<PinOk>());
      expect(await pins.verify('0000'), isA<PinWrong>());
    });

    test('lockout after repeated failures, then recovers', () async {
      final pins = PinService(secrets, iterations: 1000, clock: () => clock);
      await pins.setPin('4821');
      for (var i = 0; i < PinService.freeAttempts - 1; i++) {
        expect(await pins.verify('1111'), isA<PinWrong>());
      }
      expect(await pins.verify('1111'), isA<PinLockedOut>());
      expect(await pins.verify('4821'), isA<PinLockedOut>(), reason: 'even correct PIN waits');
      clock = clock.add(const Duration(seconds: 31));
      expect(await pins.verify('4821'), isA<PinOk>());
    });

    test('format rules', () {
      expect(PinService.isValidFormat('123'), isFalse);
      expect(PinService.isValidFormat('1234'), isTrue);
      expect(PinService.isValidFormat('12345678'), isTrue);
      expect(PinService.isValidFormat('123456789'), isFalse);
      expect(PinService.isValidFormat('12a4'), isFalse);
    });
  });

  group('App lock', () {
    Future<AppLockController> lockedWithBiometric() async {
      final c = await newController();
      await c.enableAppLock('4821');
      expect(await c.enableBiometric(), isNull);
      return newController(); // simulate relaunch
    }

    test('relaunch is locked when App Lock is on', () async {
      final c = await newController();
      expect(c.locked, isFalse);
      await c.enableAppLock('4821');
      final relaunched = await newController();
      expect(relaunched.locked, isTrue);
    });

    test('fingerprint success unlocks', () async {
      final c = await lockedWithBiometric();
      bio.nextOutcome = BiometricOutcome.success;
      final r = await c.unlockWithBiometric();
      expect(r.success, isTrue);
      expect(c.locked, isFalse);
    });

    test('fingerprint failure and cancellation keep the app locked', () async {
      final c = await lockedWithBiometric();
      bio.nextOutcome = BiometricOutcome.failed;
      expect((await c.unlockWithBiometric()).message, SecurityMessages.failed);
      bio.nextOutcome = BiometricOutcome.cancelled;
      expect((await c.unlockWithBiometric()).message, SecurityMessages.cancelled);
      bio.nextOutcome = BiometricOutcome.lockedOut;
      expect((await c.unlockWithBiometric()).message, SecurityMessages.lockedOut);
      expect(c.locked, isTrue);
    });

    test('PIN fallback unlocks', () async {
      final c = await lockedWithBiometric();
      expect(await c.unlockWithPin('0000'), isA<PinWrong>());
      expect(c.locked, isTrue);
      expect(await c.unlockWithPin('4821'), isA<PinOk>());
      expect(c.locked, isFalse);
    });

    test('device without biometric hardware cannot enable it; PIN still works', () async {
      bio.availabilityValue = BiometricAvailability.noHardware;
      final c = await newController();
      await c.enableAppLock('4821');
      expect(await c.enableBiometric(), SecurityMessages.noHardware);
      expect(c.biometricEnabled, isFalse);
    });

    test('no fingerprint enrolled', () async {
      bio.availabilityValue = BiometricAvailability.notEnrolled;
      final c = await newController();
      await c.enableAppLock('4821');
      expect(await c.enableBiometric(), SecurityMessages.notEnrolled);
    });

    test('biometric enrollment change disables biometric and requires PIN', () async {
      final c0 = await newController();
      await c0.enableAppLock('4821');
      await c0.enableBiometric();
      bio.status = BiometricKeyStatus.invalidated; // fingerprints added/removed
      final c = await newController();
      expect(c.biometricEnabled, isFalse);
      expect(c.takePendingMessage(), SecurityMessages.enrollmentChanged);
      expect(c.locked, isTrue);
      expect(bio.prompts, 1, reason: 'no prompt after invalidation');
      expect(await c.unlockWithPin('4821'), isA<PinOk>());
    });

    test('all fingerprints removed while app open', () async {
      final c = await lockedWithBiometric();
      bio.availabilityValue = BiometricAvailability.notEnrolled;
      final r = await c.unlockWithBiometric();
      expect(r.success, isFalse);
      expect(r.message, SecurityMessages.notEnrolled);
    });

    test('background lock respects timeout', () async {
      final c = await newController();
      await c.enableAppLock('4821');
      await c.setTimeout(LockTimeout.minute1);

      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 20));
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(c.locked, isFalse, reason: 'short switch: no repeated authentication');

      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 2));
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(c.locked, isTrue);
    });

    test('lock immediately', () async {
      final c = await newController();
      await c.enableAppLock('4821');
      await c.setTimeout(LockTimeout.immediately);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(c.locked, isTrue);
    });

    test('system dialogs opened by the app do not trigger a lock', () async {
      final c = await newController();
      await c.enableAppLock('4821');
      await c.setTimeout(LockTimeout.immediately);
      await c.runWithoutLocking(() async {
        c.didChangeAppLifecycleState(AppLifecycleState.paused);
        c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      });
      expect(c.locked, isFalse);
    });

    test('disabling App Lock requires the PIN', () async {
      final c = await newController();
      await c.enableAppLock('4821');
      expect(await c.disableAppLock('0000'), isA<PinWrong>());
      expect(c.lockEnabled, isTrue);
      expect(await c.disableAppLock('4821'), isA<PinOk>());
      expect(c.lockEnabled, isFalse);
      expect((await newController()).locked, isFalse);
    });
  });
}
