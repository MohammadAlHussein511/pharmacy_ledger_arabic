import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. Single source of truth for all financial data.
/// Totals are never stored; every report is aggregated from `transactions`.
class AppDatabase {
  AppDatabase._();

  static const int schemaVersion = 1;
  static const String fileName = 'pharmacy_ledger.db';

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final statement in createStatements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Future migrations go here, e.g. if (oldVersion < 2) {...}
        },
      ),
    );
  }

  static const List<String> createStatements = [
    '''
    CREATE TABLE warehouses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      name_key TEXT NOT NULL UNIQUE,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL CHECK (type IN ('SALE', 'PAYMENT')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency TEXT NOT NULL CHECK (currency IN ('TRY', 'USD', 'SYP')),
      warehouse_id INTEGER REFERENCES warehouses(id) ON DELETE RESTRICT,
      invoice_number TEXT,
      note TEXT,
      transaction_date TEXT NOT NULL,
      transaction_time TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (
        (type = 'SALE' AND currency = 'TRY' AND warehouse_id IS NULL)
        OR (type = 'PAYMENT' AND warehouse_id IS NOT NULL)
      )
    )
    ''',
    'CREATE INDEX idx_tx_date_type ON transactions (transaction_date, type, currency)',
    'CREATE INDEX idx_tx_warehouse_date ON transactions (warehouse_id, transaction_date)',
    'CREATE INDEX idx_tx_invoice ON transactions (invoice_number)',
    'CREATE INDEX idx_wh_active_name ON warehouses (is_active, name_key)',
  ];
}
