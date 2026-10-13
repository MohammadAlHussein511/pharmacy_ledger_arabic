import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app_info.dart';
import '../core/dates.dart';
import '../data/database.dart';
import '../security/pbkdf2.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupPasswordRequired implements Exception {
  const BackupPasswordRequired();
}

class BackupMessages {
  BackupMessages._();
  static const notABackup = 'هذا الملف ليس نسخة احتياطية صالحة لدفتر الصيدلية.';
  static const corrupted = 'ملف النسخة الاحتياطية تالف أو تم تعديله ولا يمكن استعادته.';
  static const newerVersion =
      'هذه النسخة الاحتياطية أُنشئت بإصدار أحدث من دفتر الصيدلية. يرجى تحديث التطبيق أولاً.';
  static const wrongPassword = 'كلمة مرور النسخة الاحتياطية غير صحيحة.';
  static const tooLarge = 'هذا الملف كبير جداً ليكون نسخة احتياطية لدفتر الصيدلية.';
  static const restoreFailed =
      'تعذّرت استعادة النسخة الاحتياطية. لم يتم تغيير بياناتك الحالية.';
}

class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.appVersion,
    required this.encrypted,
    required this.warehouses,
    required this.transactions,
    this.invoices = const [],
    this.invoicePayments = const [],
    this.pharmacyDebts = const [],
    this.pharmacyDebtEntries = const [],
  });

  final DateTime? createdAt;
  final String appVersion;
  final bool encrypted;
  final List<Map<String, Object?>> warehouses;
  final List<Map<String, Object?>> transactions;
  final List<Map<String, Object?>> invoices;
  final List<Map<String, Object?>> invoicePayments;
  final List<Map<String, Object?>> pharmacyDebts;
  final List<Map<String, Object?>> pharmacyDebtEntries;

  int get warehouseCount => warehouses.length;
  int get transactionCount => transactions.length;
  int get invoiceCount => invoices.length;
  int get invoicePaymentCount => invoicePayments.length;
  int get pharmacyDebtCount => pharmacyDebts.length;
  int get pharmacyDebtEntryCount => pharmacyDebtEntries.length;
}

class BackupService {
  BackupService(this._db, {this.kdfIterations = 150000, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final int kdfIterations;
  final DateTime Function() _clock;

  static const String format = 'pharmacy-ledger-backup';
  static const int formatVersion = 2;  // [تم التحديث] من 1 إلى 2
  static const int maxBytes = 200 * 1024 * 1024;

  static const _whCols = ['id', 'name', 'name_key', 'is_active', 'created_at', 'updated_at'];
  static const _txCols = [
    'id', 'type', 'amount_minor', 'currency', 'warehouse_id', 'invoice_number', 'note',
    'transaction_date', 'transaction_time', 'created_at', 'updated_at',
  ];
  static const _invCols = [
    'id', 'warehouse_id', 'currency', 'amount_minor', 'paid_minor',
    'exchange_rate', 'note', 'invoice_date', 'created_at', 'updated_at',
  ];
  static const _invPayCols = [
    'id', 'invoice_id', 'transaction_id', 'amount_minor', 'currency_paid',
    'exchange_rate', 'note', 'payment_date', 'payment_time',
    'created_at', 'updated_at',
  ];
  static const _pdCols = ['id', 'name', 'name_key', 'created_at', 'updated_at'];
  static const _pdeCols = [
    'id', 'pharmacy_id', 'direction', 'amount_minor', 'currency',
    'note', 'entry_date', 'entry_time', 'created_at', 'updated_at',
  ];

  String suggestedFileName() {
    final n = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'pharmacy-ledger-backup-${Dates.key(n)}-${two(n.hour)}${two(n.minute)}.json';
  }

  Future<Uint8List> createBackup({String? password}) async {
    final warehouses = await _db.query('warehouses', columns: _whCols, orderBy: 'id');
    final transactions = await _db.query('transactions', columns: _txCols, orderBy: 'id');
    final invoices = await _db.query('invoices', columns: _invCols, orderBy: 'id');
    final invoicePayments = await _db.query('invoice_payments', columns: _invPayCols, orderBy: 'id');
    final pharmacyDebts = await _db.query('pharmacy_debts', columns: _pdCols, orderBy: 'id');
    final pharmacyDebtEntries = await _db.query('pharmacy_debt_entries', columns: _pdeCols, orderBy: 'id');

    final data = {
      'warehouses': warehouses,
      'transactions': transactions,
      'invoices': invoices,
      'invoice_payments': invoicePayments,
      'pharmacy_debts': pharmacyDebts,
      'pharmacy_debt_entries': pharmacyDebtEntries,
    };
    final dataJson = jsonEncode(data);
    final checksum = sha256.convert(utf8.encode(dataJson)).toString();

    final envelope = <String, Object?>{
      'format': format,
      'format_version': formatVersion,
      'schema_version': AppDatabase.schemaVersion,
      'app_version': AppInfo.version,
      'created_at': _clock().toIso8601String(),
      'counts': {
        'warehouses': warehouses.length,
        'transactions': transactions.length,
        'invoices': invoices.length,
        'invoice_payments': invoicePayments.length,
        'pharmacy_debts': pharmacyDebts.length,
        'pharmacy_debt_entries': pharmacyDebtEntries.length,
      },
      'checksum_sha256': checksum,
    };

    if (password == null || password.isEmpty) {
      envelope['encrypted'] = false;
      envelope['data'] = data;
    } else {
      final rnd = Random.secure();
      final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
      final key = await _deriveKey(password, salt, kdfIterations);
      final algo = AesGcm.with256bits();
      final nonce = algo.newNonce();
      final box = await algo.encrypt(utf8.encode(dataJson),
          secretKey: SecretKey(key), nonce: nonce);
      envelope['encrypted'] = true;
      envelope['encryption'] = {
        'cipher': 'AES-256-GCM',
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
      };
      envelope['payload'] = base64Encode(box.cipherText);
    }
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(envelope)));
  }

  Future<BackupPreview> inspect(List<int> bytes, {String? password}) async {
    if (bytes.length > maxBytes) throw const BackupException(BackupMessages.tooLarge);
    Map<String, dynamic> env;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      env = decoded;
    } catch (_) {
      throw const BackupException(BackupMessages.notABackup);
    }
    if (env['format'] != format) throw const BackupException(BackupMessages.notABackup);
    final version = env['format_version'];
    if (version is! int) throw const BackupException(BackupMessages.notABackup);
    if (version > formatVersion) throw const BackupException(BackupMessages.newerVersion);
    final checksum = env['checksum_sha256'];
    if (checksum is! String) throw const BackupException(BackupMessages.corrupted);

    final encrypted = env['encrypted'] == true;
    String dataJson;
    if (encrypted) {
      if (password == null || password.isEmpty) throw const BackupPasswordRequired();
      dataJson = await _decrypt(env, password);
    } else {
      final data = env['data'];
      if (data is! Map<String, dynamic>) throw const BackupException(BackupMessages.corrupted);
      dataJson = jsonEncode(data);
    }
    if (sha256.convert(utf8.encode(dataJson)).toString() != checksum) {
      throw const BackupException(BackupMessages.corrupted);
    }

    final data = jsonDecode(dataJson) as Map<String, dynamic>;
    final whs = _rows(data['warehouses'], _whCols);
    final txs = _rows(data['transactions'], _txCols);
    final invs = _rowsOpt(data['invoices'], _invCols);
    final invPays = _rowsOpt(data['invoice_payments'], _invPayCols);
    final pds = _rowsOpt(data['pharmacy_debts'], _pdCols);
    final pdes = _rowsOpt(data['pharmacy_debt_entries'], _pdeCols);
    _validateRows(whs, txs);

    return BackupPreview(
      createdAt: DateTime.tryParse('${env['created_at']}'),
      appVersion: '${env['app_version'] ?? ''}',
      encrypted: encrypted,
      warehouses: whs,
      transactions: txs,
      invoices: invs,
      invoicePayments: invPays,
      pharmacyDebts: pds,
      pharmacyDebtEntries: pdes,
    );
  }

  Future<String> _decrypt(Map<String, dynamic> env, String password) async {
    try {
      final enc = env['encryption'] as Map<String, dynamic>;
      final salt = base64Decode(enc['salt'] as String);
      final key = await _deriveKey(password, salt, enc['iterations'] as int);
      final box = SecretBox(
        base64Decode(env['payload'] as String),
        nonce: base64Decode(env['nonce'] as String),
        mac: Mac(base64Decode(env['mac'] as String)),
      );
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupException(BackupMessages.wrongPassword);
    } catch (_) {
      throw const BackupException(BackupMessages.corrupted);
    }
  }

  List<Map<String, Object?>> _rows(Object? list, List<String> cols) {
    if (list is! List) throw const BackupException(BackupMessages.corrupted);
    return [
      for (final r in list)
        if (r is Map<String, dynamic>)
          {for (final c in cols) c: r[c]}
        else
          throw const BackupException(BackupMessages.corrupted),
    ];
  }

  /// مثل _rows لكنها تُعيد قائمة فارغة إذا كان الحقل غير موجود (دعم النسخ القديمة)
  List<Map<String, Object?>> _rowsOpt(Object? list, List<String> cols) {
    if (list == null) return <Map<String, Object?>>[];
    if (list is! List) return <Map<String, Object?>>[];
    return [
      for (final r in list)
        if (r is Map<String, dynamic>) {for (final c in cols) c: r[c]},
    ];
  }

  void _validateRows(List<Map<String, Object?>> whs, List<Map<String, Object?>> txs) {
    Never bad() => throw const BackupException(BackupMessages.corrupted);
    bool isTs(Object? v) => v is String && DateTime.tryParse(v) != null;

    final whIds = <int>{};
    final keys = <String>{};
    for (final w in whs) {
      final id = w['id'];
      final name = w['name'];
      final key = w['name_key'];
      if (id is! int || !whIds.add(id)) bad();
      if (name is! String || name.trim().isEmpty || key is! String || !keys.add(key)) bad();
      if (w['is_active'] != 0 && w['is_active'] != 1) bad();
      if (!isTs(w['created_at']) || !isTs(w['updated_at'])) bad();
    }
    final txIds = <int>{};
    for (final t in txs) {
      final id = t['id'];
      if (id is! int || !txIds.add(id)) bad();
      final type = t['type'];
      final amount = t['amount_minor'];
      final currency = t['currency'];
      final wh = t['warehouse_id'];
      if (amount is! int || amount <= 0) bad();
      if (currency != 'TRY' && currency != 'USD' && currency != 'SYP') bad();
      if (type == 'SALE') {
        if (currency != 'TRY' || wh != null) bad();
      } else if (type == 'PAYMENT') {
        if (wh is! int || !whIds.contains(wh)) bad();
      } else {
        bad();
      }
      final d = t['transaction_date'];
      final tm = t['transaction_time'];
      if (d is! String || !Dates.isValidKey(d)) bad();
      if (tm is! String || !Dates.isValidTime(tm)) bad();
      final inv = t['invoice_number'];
      final note = t['note'];
      if (inv != null && inv is! String) bad();
      if (note != null && note is! String) bad();
      if (!isTs(t['created_at']) || !isTs(t['updated_at'])) bad();
    }
  }

  Future<void> restore(BackupPreview preview) async {
    try {
      await _db.transaction((txn) async {
        // ترتيب الحذف مهم بسبب foreign keys
        await txn.delete('pharmacy_debt_entries');
        await txn.delete('pharmacy_debts');
        await txn.delete('invoice_payments');
        await txn.delete('invoices');
        await txn.delete('transactions');
        await txn.delete('warehouses');

        final batch = txn.batch();
        for (final w in preview.warehouses) {
          batch.insert('warehouses', w, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final t in preview.transactions) {
          batch.insert('transactions', t, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final i in preview.invoices) {
          batch.insert('invoices', i, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final p in preview.invoicePayments) {
          batch.insert('invoice_payments', p, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final pd in preview.pharmacyDebts) {
          batch.insert('pharmacy_debts', pd, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        for (final pe in preview.pharmacyDebtEntries) {
          batch.insert('pharmacy_debt_entries', pe, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {
      throw const BackupException(BackupMessages.restoreFailed);
    }
  }

  static Future<List<int>> _deriveKey(String password, List<int> salt, int iterations) {
    final pwd = utf8.encode(password);
    return Isolate.run(() => pbkdf2Sha256(pwd, salt, iterations, 32));
  }
}