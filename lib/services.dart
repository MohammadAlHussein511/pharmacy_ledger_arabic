import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'backup/backup_service.dart';
import 'data/database.dart';
import 'data/ledger_store.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/repositories/warehouse_repository.dart';
import 'domain/report_service.dart';
import 'security/app_lock_controller.dart';
import 'security/biometric_service.dart';
import 'security/pin_service.dart';
import 'ui/theme_controller.dart';

/// Composition root: wires database, repositories and services together.
class AppServices {
  AppServices._({
    required this.db,
    required this.store,
    required this.settings,
    required this.warehouses,
    required this.transactions,
    required this.reports,
    required this.backup,
    required this.lock,
    required this.theme,
  });

  final Database db;
  final LedgerStore store;
  final SettingsRepository settings;
  final WarehouseRepository warehouses;
  final TransactionRepository transactions;
  final ReportService reports;
  final BackupService backup;
  final AppLockController lock;
  final ThemeController theme;

  static Future<AppServices> create() async {
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open();
    final store = LedgerStore();
    final settings = SettingsRepository(prefs, secure);
    final lock = AppLockController(
      settings: settings,
      pins: PinService(SecureSecretStore(secure)),
      biometrics: PlatformBiometricService(),
    );
    await lock.init();
    return AppServices._(
      db: db,
      store: store,
      settings: settings,
      warehouses: WarehouseRepository(db, onChanged: store.changed),
      transactions: TransactionRepository(db, onChanged: store.changed),
      reports: ReportService(db),
      backup: BackupService(db),
      lock: lock,
      theme: ThemeController(settings),
    );
  }
}
