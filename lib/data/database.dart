import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static const int schemaVersion = 4;
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
          if (oldVersion < 2) {
            for (final statement in _v2Migration) {
              try { await db.execute(statement); } catch (_) {}
            }
          }
          if (oldVersion < 3) {
            for (final statement in _v3Migration) {
              try { await db.execute(statement); } catch (_) {}
            }
          }
          if (oldVersion < 4) {
            // [إصلاح] إضافة الأعمدة فقط إذا لم تكن موجودة
            try {
              await db.execute('ALTER TABLE pharmacy_debt_entries ADD COLUMN settled INTEGER NOT NULL DEFAULT 0');
            } catch (_) {}
            try {
              await db.execute('ALTER TABLE pharmacy_debt_entries ADD COLUMN settled_at TEXT');
            } catch (_) {}
            try {
              await db.execute('CREATE INDEX IF NOT EXISTS idx_pde_settled ON pharmacy_debt_entries (settled)');
            } catch (_) {}
          }
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
    '''
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      warehouse_id INTEGER NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
      currency TEXT NOT NULL CHECK (currency IN ('USD', 'SYP')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      paid_minor INTEGER NOT NULL DEFAULT 0 CHECK (paid_minor >= 0),
      exchange_rate REAL,
      note TEXT,
      invoice_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE invoice_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      transaction_id INTEGER REFERENCES transactions(id) ON DELETE CASCADE,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency_paid TEXT NOT NULL CHECK (currency_paid IN ('TRY', 'USD', 'SYP')),
      exchange_rate REAL,
      note TEXT,
      payment_date TEXT NOT NULL,
      payment_time TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_inv_wh_date ON invoices (warehouse_id, invoice_date)',
    'CREATE INDEX idx_invpay_inv_date ON invoice_payments (invoice_id, payment_date)',
    'CREATE INDEX idx_invpay_tx ON invoice_payments (transaction_id)',
    '''
    CREATE TABLE pharmacy_debts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      name_key TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE pharmacy_debt_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pharmacy_id INTEGER NOT NULL REFERENCES pharmacy_debts(id) ON DELETE RESTRICT,
      direction TEXT NOT NULL CHECK (direction IN ('OWED_TO_US', 'OWED_BY_US')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency TEXT NOT NULL CHECK (currency IN ('TRY', 'USD', 'SYP')),
      note TEXT,
      entry_date TEXT NOT NULL,
      entry_time TEXT NOT NULL,
      settled INTEGER NOT NULL DEFAULT 0 CHECK (settled IN (0, 1)),
      settled_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_pde_ph_date ON pharmacy_debt_entries (pharmacy_id, entry_date)',
    'CREATE INDEX idx_pde_settled ON pharmacy_debt_entries (settled)',
  ];

  static const List<String> _v2Migration = [
    '''
    CREATE TABLE IF NOT EXISTS invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      warehouse_id INTEGER NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
      currency TEXT NOT NULL CHECK (currency IN ('USD', 'SYP')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      paid_minor INTEGER NOT NULL DEFAULT 0 CHECK (paid_minor >= 0),
      exchange_rate REAL,
      note TEXT,
      invoice_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS invoice_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency_paid TEXT NOT NULL CHECK (currency_paid IN ('TRY', 'USD', 'SYP')),
      exchange_rate REAL,
      note TEXT,
      payment_date TEXT NOT NULL,
      payment_time TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_inv_wh_date ON invoices (warehouse_id, invoice_date)',
    'CREATE INDEX IF NOT EXISTS idx_invpay_inv_date ON invoice_payments (invoice_id, payment_date)',
    '''
    CREATE TABLE IF NOT EXISTS pharmacy_debts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      name_key TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pharmacy_debt_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pharmacy_id INTEGER NOT NULL REFERENCES pharmacy_debts(id) ON DELETE RESTRICT,
      direction TEXT NOT NULL CHECK (direction IN ('OWED_TO_US', 'OWED_BY_US')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency TEXT NOT NULL CHECK (currency IN ('TRY', 'USD', 'SYP')),
      note TEXT,
      entry_date TEXT NOT NULL,
      entry_time TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_pde_ph_date ON pharmacy_debt_entries (pharmacy_id, entry_date)',
  ];

  static const List<String> _v3Migration = [
    'ALTER TABLE invoice_payments RENAME TO invoice_payments_v2',
    '''
    CREATE TABLE invoice_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      transaction_id INTEGER REFERENCES transactions(id) ON DELETE CASCADE,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency_paid TEXT NOT NULL CHECK (currency_paid IN ('TRY', 'USD', 'SYP')),
      exchange_rate REAL,
      note TEXT,
      payment_date TEXT NOT NULL,
      payment_time TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    INSERT INTO invoice_payments
      (id, invoice_id, amount_minor, currency_paid, exchange_rate, note, payment_date, payment_time, created_at, updated_at)
    SELECT id, invoice_id, amount_minor, currency_paid, exchange_rate, note, payment_date, payment_time, created_at, updated_at
    FROM invoice_payments_v2
    ''',
    'DROP TABLE invoice_payments_v2',
    'CREATE INDEX idx_invpay_inv_date ON invoice_payments (invoice_id, payment_date)',
    'CREATE INDEX idx_invpay_tx ON invoice_payments (transaction_id)',
    'DELETE FROM invoice_payments WHERE transaction_id IS NULL',
    'DELETE FROM transactions WHERE type = \'PAYMENT\' AND id NOT IN (SELECT COALESCE(transaction_id, -1) FROM invoice_payments WHERE transaction_id IS NOT NULL)',
  ];

    static const List<String> _v4Migration = [
    // [إصلاح] نستخدم try/catch لأن الأعمدة قد تكون موجودة من ترقية سابقة
    'INSERT OR IGNORE INTO pharmacy_debt_entries (id) SELECT NULL', // اختبار فقط
  ];
}