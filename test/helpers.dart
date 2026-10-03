import 'package:pharmacy_ledger/data/database.dart';
import 'package:pharmacy_ledger/security/pin_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fresh in-memory SQLite database with the real production schema.
Future<Database> openTestDb() async {
  sqfliteFfiInit();
  return AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}
