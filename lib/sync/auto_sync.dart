import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_service.dart';
import '../services.dart';

/// محرك المزامنة v8 — قاعدة "المحلي هو السيد":
/// التنزيل يضيف الجديد ويطبق الحذف الصريح فقط، ولا يستبدل أي صف محلي موجود.
/// الرفع يعكس المحلي على السحابة عبر بصمة محتوى لكل صف.
class AutoSync {
  AutoSync(this._services);

  static AutoSync? current;

  final AppServices _services;
  Timer? _timer;
  bool _running = false;
  bool _loaded = false;

  final Map<String, Map<String, String>> _map = {
    'warehouses': {},
    'transactions': {},
    'invoices': {},
    'invoice_payments': {},
    'pharmacy_debts': {},
    'pharmacy_debt_entries': {},
  };
  final Map<String, Map<String, String>> _snap = {
    'warehouses': {},
    'transactions': {},
    'invoices': {},
    'invoice_payments': {},
    'pharmacy_debts': {},
    'pharmacy_debt_entries': {},
  };

  String _lastSummary = 'لم تتم مزامنة بعد';

  int _gAdd = 0, _gDel = 0, _pAdd = 0, _pUpd = 0, _pDel = 0;

  void start() {
    current = this;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => syncCycle());
    Future.microtask(syncCycle);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  String summary() => _lastSummary;

  Future<String> syncNow() async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return 'غير مسجل الدخول!';
    if (_running) return 'المزامنة تعمل حالياً...';
    _running = true;
    try {
      await _loadState();
      await _pull(uid);
      await _push(uid);
      return 'تمت المزامنة بنجاح ✅\n$_lastSummary';
    } catch (e) {
      debugPrint('[sync] ERROR: $e');
      return 'فشل المزامنة ❌\n$e';
    } finally {
      _running = false;
    }
  }

  Future<void> syncCycle() async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || _running) return;
    _running = true;
    try {
      await _loadState();
      await _pull(uid);
      await _push(uid);
    } catch (e) {
      debugPrint('[sync] cycle error: $e');
    } finally {
      _running = false;
    }
  }

  // ================= حالة الخرائط =================

  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'sync_state_v8.json'));
  }

  Future<void> _loadState() async {
    if (_loaded) return;
    try {
      final f = await _stateFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        for (final k in _map.keys) {
          _map[k] = Map<String, String>.from(j['map_$k'] ?? {});
          _snap[k] = Map<String, String>.from(j['snap_$k'] ?? {});
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _saveState() async {
    try {
      final f = await _stateFile();
      final payload = <String, dynamic>{};
      for (final k in _map.keys) {
        payload['map_$k'] = _map[k];
        payload['snap_$k'] = _snap[k];
      }
      await f.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  // ================= أدوات =================

  List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map<Map<String, dynamic>>((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  bool _del(dynamic v) => v == true || v == 1 || v == '1';
  bool _act(dynamic v) => v == true || v == 1 || v == '1';
  String _fp(List<Object?> parts) => parts.map((e) => e ?? '').join('|');
  int _maxId(List<Map<String, dynamic>> list) {
    var m = 0;
    for (final r in list) {
      final id = r['id'];
      if (id is int && id > m) m = id;
    }
    return m;
  }

  Map<String, String> _rev(String table) =>
      {for (final e in _map[table]!.entries) e.value: e.key};

  Future<BackupPreview> _local() async {
    final bytes = await _services.backup.createBackup();
    final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (env['encrypted'] == true) return _services.backup.inspect(bytes);
    final data = env['data'] as Map<String, dynamic>;
    return BackupPreview(
      createdAt: null,
      appVersion: '',
      encrypted: false,
      warehouses: _rows(data['warehouses']),
      transactions: _rows(data['transactions']),
      invoices: _rows(data['invoices'] ?? []),
      invoicePayments: _rows(data['invoice_payments'] ?? []),
      pharmacyDebts: _rows(data['pharmacy_debts'] ?? []),
      pharmacyDebtEntries: _rows(data['pharmacy_debt_entries'] ?? []),
    );
  }

  String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    String hex(int n, int len) => n.toRadixString(16).padLeft(len, '0');
    return '${hex((now >> 48) & 0xFFFF, 4)}${hex((now >> 32) & 0xFFFF, 4)}-'
        '${hex((now >> 16) & 0xFFFF, 4)}-${hex(now & 0xFFFF, 4)}-'
        '${hex((now >> 16) & 0xFFFF, 4)}-'
        '${hex(now & 0xFFFF, 4)}${hex((now >> 32) & 0xFFFF, 4)}'
        '${hex((now >> 48) & 0xFFFF, 4)}';
  }

  // ================= التنزيل: إضافة الجديد + حذف صريح فقط =================

  Future<void> _pull(String uid) async {
    _gAdd = 0;
    _gDel = 0;
    final supabase = Supabase.instance.client;
    final local = await _local();
    var changed = false;

    final addWh = <Map<String, Object?>>[];
    final addTx = <Map<String, Object?>>[];
    final addInv = <Map<String, Object?>>[];
    final addInvP = <Map<String, Object?>>[];
    final addPd = <Map<String, Object?>>[];
    final addPde = <Map<String, Object?>>[];
    final delWh = <int>{};
    final delTx = <int>{};
    final delInv = <int>{};
    final delInvP = <int>{};
    final delPd = <int>{};
    final delPde = <int>{};

    // خرائط سحابي -> محلي الحالية
    final whC2L = <String, int>{
      for (final e in _map['warehouses']!.entries) e.value: int.parse(e.key)
    };
    final invC2L = <String, int>{
      for (final e in _map['invoices']!.entries) e.value: int.parse(e.key)
    };
    final pdC2L = <String, int>{
      for (final e in _map['pharmacy_debts']!.entries) e.value: int.parse(e.key)
    };

    var maxWh = _maxId(local.warehouses);
    var maxTx = _maxId(local.transactions);
    var maxInv = _maxId(local.invoices);
    var maxInvP = _maxId(local.invoicePayments);
    var maxPd = _maxId(local.pharmacyDebts);
    var maxPde = _maxId(local.pharmacyDebtEntries);

    final revWh = _rev('warehouses');
    final revTx = _rev('transactions');
    final revInv = _rev('invoices');
    final revInvP = _rev('invoice_payments');
    final revPd = _rev('pharmacy_debts');
    final revPde = _rev('pharmacy_debt_entries');

    // 1) المستودعات
    for (final c in _rows(await supabase.from('warehouses').select('*'))) {
      final cid = c['id'] as String;
      final lid = revWh[cid];
      if (_del(c['is_deleted'])) {
        if (lid != null) {
          delWh.add(int.parse(lid));
          _map['warehouses']!.remove(lid);
          _snap['warehouses']!.remove(lid);
          _gDel++;
          changed = true;
        }
        continue;
      }
      if (lid != null) {
        whC2L[cid] = int.parse(lid);
        continue;
      }
      final nameKey = (c['name_key'] as String? ?? '').toLowerCase().trim();
      final existing = local.warehouses.firstWhere(
          (w) => (w['name_key'] as String).toLowerCase().trim() == nameKey,
          orElse: () => <String, dynamic>{});
      if (existing.isNotEmpty) {
        _map['warehouses']![(existing['id'] as int).toString()] = cid;
        _snap['warehouses']![(existing['id'] as int).toString()] =
            _fp([c['name'], c['is_active']]);
        whC2L[cid] = existing['id'] as int;
        changed = true;
        continue;
      }
      final id = ++maxWh;
      addWh.add({
        'id': id,
        'name': c['name'] as String,
        'name_key': (c['name_key'] as String?) ?? nameKey,
        'is_active': _act(c['is_active']) ? 1 : 0,
        'created_at': '${c['created_at']}',
        'updated_at': '${c['updated_at']}',
      });
      _map['warehouses']![id.toString()] = cid;
      _snap['warehouses']![id.toString()] = _fp([c['name'], c['is_active']]);
      whC2L[cid] = id;
      _gAdd++;
      changed = true;
    }

    // 2) الفواتير
    for (final c in _rows(await supabase.from('invoices').select('*'))) {
      final cid = c['id'] as String;
      final lid = revInv[cid];
      if (_del(c['is_deleted'])) {
        if (lid != null) {
          delInv.add(int.parse(lid));
          _map['invoices']!.remove(lid);
          _snap['invoices']!.remove(lid);
          _gDel++;
          changed = true;
        }
        continue;
      }
      if (lid != null) {
        invC2L[cid] = int.parse(lid);
        continue;
      }
      final whLocal = whC2L[c['warehouse_id'] as String? ?? ''];
      if (whLocal == null) continue;
      final id = ++maxInv;
      addInv.add({
        'id': id,
        'warehouse_id': whLocal,
        'currency': c['currency'] as String,
        'amount_minor': c['amount_minor'] as int,
        'paid_minor': (c['paid_minor'] as int?) ?? 0,
        'exchange_rate': (c['exchange_rate'] as num?)?.toDouble(),
        'note': c['note'] as String?,
        'invoice_date': c['invoice_date'] as String,
        'created_at': '${c['created_at']}',
        'updated_at': '${c['updated_at']}',
      });
      _map['invoices']![id.toString()] = cid;
      _snap['invoices']![id.toString()] = _fp([
        whLocal,
        c['currency'],
        c['amount_minor'],
        c['paid_minor'],
        c['exchange_rate'],
        c['note'],
        c['invoice_date']
      ]);
      invC2L[cid] = id;
      _gAdd++;
      changed = true;
    }

    // 3) الصيدليات
    for (final c in _rows(await supabase.from('pharmacy_debts').select('*'))) {
      final cid = c['id'] as String;
      final lid = revPd[cid];
      if (_del(c['is_deleted'])) {
        if (lid != null) {
          delPd.add(int.parse(lid));
          _map['pharmacy_debts']!.remove(lid);
          _snap['pharmacy_debts']!.remove(lid);
          _gDel++;
          changed = true;
        }
        continue;
      }
      if (lid != null) {
        pdC2L[cid] = int.parse(lid);
        continue;
      }
      final nameKey = (c['name_key'] as String? ?? '').toLowerCase().trim();
      final existing = local.pharmacyDebts.firstWhere(
          (w) => (w['name_key'] as String).toLowerCase().trim() == nameKey,
          orElse: () => <String, dynamic>{});
      if (existing.isNotEmpty) {
        _map['pharmacy_debts']![(existing['id'] as int).toString()] = cid;
        _snap['pharmacy_debts']![(existing['id'] as int).toString()] = _fp([c['name']]);
        pdC2L[cid] = existing['id'] as int;
        changed = true;
        continue;
      }
      final id = ++maxPd;
      addPd.add({
        'id': id,
        'name': c['name'] as String,
        'name_key': (c['name_key'] as String?) ?? nameKey,
        'created_at': '${c['created_at']}',
        'updated_at': '${c['updated_at']}',
      });
      _map['pharmacy_debts']![id.toString()] = cid;
      _snap['pharmacy_debts']![id.toString()] = _fp([c['name']]);
      pdC2L[cid] = id;
      _gAdd++;
      changed = true;
    }

    // 4) العمليات
    for (final c in _rows(await supabase.from('transactions').select('*'))) {
      final cid = c['id'] as String;
      final lid = revTx[cid];
      if (_del(c['is_deleted'])) {
        if (lid != null) {
          delTx.add(int.parse(lid));
          _map['transactions']!.remove(lid);
          _snap['transactions']!.remove(lid);
          _gDel++;
          changed = true;
        }
        continue;
      }
      if (lid != null) continue;
      final type = c['type'] as String?;
      final cwid = c['warehouse_id'] as String?;
      final whLocal = cwid == null ? null : whC2L[cwid];
      if (type == 'PAYMENT' && whLocal == null) continue;
      final id = ++maxTx;
      addTx.add({
        'id': id,
        'type': type,
        'amount_minor': c['amount_minor'] as int,
        'currency': c['currency'] as String,
        'warehouse_id': type == 'SALE' ? null : whLocal,
        'invoice_number': c['invoice_number'] as String?,
        'note': c['note'] as String?,
        'transaction_date': c['transaction_date'] as String,
        'transaction_time': c['transaction_time'] as String,
        'created_at': '${c['created_at']}',
        'updated_at': '${c['updated_at']}',
      });
      _map['transactions']![id.toString()] = cid;
      _snap['transactions']![id.toString()] = _fp([
        type,
        c['amount_minor'],
        c['currency'],
        whLocal,
        c['invoice_number'],
        c['note'],
        c['transaction_date'],
        c['transaction_time']
      ]);
      _gAdd++;
      changed = true;
    }

    // 5) دفعات الفواتير
    for (final c in _rows(await supabase.from('invoice_payments').select('*'))) {
      final cid = c['id'] as String;
      final lid = revInvP[cid];
      if (_del(c['is_deleted'])) {
        if (lid != null) {
          delInvP.add(int.parse(lid));
          _map['invoice_payments']!.remove(lid);
          _snap['invoice_payments']!.remove(lid);
          _gDel++;
          changed = true;
        }
        continue;
      }
      if (lid != null) continue;
      final invLocal = invC2L[c['invoice_id'] as String? ?? ''];
      if (invLocal == null) continue;
      final id = ++maxInvP;
      addInvP.add({
        'id': id,
        'invoice_id': invLocal,
        'transaction_id': null,
        'amount_minor': c['amount_minor'] as int,
        'currency_paid': c['currency_paid'] as String,
        'exchange_rate': (c['exchange_rate'] as num?)?.toDouble(),
        'note': c['note'] as String?,
        'payment_date': c['payment_date'] as String,
        'payment_time': c['payment_time'] as String,
        'created_at': '${c['created_at']}',
        'updated_at': '${c['updated_at']}',
      });
      _map['invoice_payments']![id.toString()] = cid;
      _snap['invoice_payments']![id.toString()] = _fp([
        invLocal,
        c['amount_minor'],
        c['currency_paid'],
        c['exchange_rate'],
        c['note'],
        c['payment_date'],
        c['payment_time']
      ]);
      _gAdd++;
      changed = true;
    }

    // 6) حركات الديون
    for (final c in _rows(await supabase.from('pharmacy_debt_entries').select('*'))) {
      final cid = c['id'] as String;
      final lid = revPde[cid];
      if (_del(c['is_deleted'])) {
        if (lid != null) {
          delPde.add(int.parse(lid));
          _map['pharmacy_debt_entries']!.remove(lid);
          _snap['pharmacy_debt_entries']!.remove(lid);
          _gDel++;
          changed = true;
        }
        continue;
      }
      if (lid != null) continue;
      final pdLocal = pdC2L[c['pharmacy_id'] as String? ?? ''];
      if (pdLocal == null) continue;
      final id = ++maxPde;
      addPde.add({
        'id': id,
        'pharmacy_id': pdLocal,
        'direction': c['direction'] as String,
        'amount_minor': c['amount_minor'] as int,
        'currency': c['currency'] as String,
        'note': c['note'] as String?,
        'entry_date': c['entry_date'] as String,
        'entry_time': c['entry_time'] as String,
        'created_at': '${c['created_at']}',
        'updated_at': '${c['updated_at']}',
      });
      _map['pharmacy_debt_entries']![id.toString()] = cid;
      _snap['pharmacy_debt_entries']![id.toString()] = _fp([
        pdLocal,
        c['direction'],
        c['amount_minor'],
        c['currency'],
        c['note'],
        c['entry_date'],
        c['entry_time']
      ]);
      _gAdd++;
      changed = true;
    }

    if (!changed) {
      await _saveState();
      return;
    }

    // حذف تتابعي محلي: فاتورة محذوفة -> دفعاتها -> عملياتها
    for (final p in local.invoicePayments) {
      if (delInv.contains(p['invoice_id'])) delInvP.add(p['id'] as int);
    }
    for (final p in local.invoicePayments) {
      final tx = p['transaction_id'];
      if (tx is int && delInvP.contains(p['id'])) delTx.add(tx);
    }
    for (final e in local.pharmacyDebtEntries) {
      if (delPd.contains(e['pharmacy_id'])) delPde.add(e['id'] as int);
    }

    List<Map<String, Object?>> keep(List<Map<String, dynamic>> src, Set<int> del) =>
        src.where((r) => !del.contains(r['id'] as int)).toList();

    try {
      await _services.backup.restore(BackupPreview(
        createdAt: DateTime.now(),
        appVersion: 'sync',
        encrypted: false,
        warehouses: [...keep(local.warehouses, delWh), ...addWh],
        transactions: [...keep(local.transactions, delTx), ...addTx],
        invoices: [...keep(local.invoices, delInv), ...addInv],
        invoicePayments: [...keep(local.invoicePayments, delInvP), ...addInvP],
        pharmacyDebts: [...keep(local.pharmacyDebts, delPd), ...addPd],
        pharmacyDebtEntries: [...keep(local.pharmacyDebtEntries, delPde), ...addPde],
      ));
      _services.store.changed();
    } catch (e) {
      debugPrint('[sync] restore FAILED: $e');
    }
    await _saveState();
  }

  // ================= الرفع: عكس المحلي على السحابة =================

  Future<void> _push(String uid) async {
    _pAdd = 0;
    _pUpd = 0;
    _pDel = 0;
    final supabase = Supabase.instance.client;
    final local = await _local();
    final now = DateTime.now().toIso8601String();

    // 1) المستودعات
    final whL2C = <int, String>{};
    for (final w in local.warehouses) {
      final lid = (w['id'] as int).toString();
      final f = _fp([w['name'], w['is_active']]);
      var cid = _map['warehouses']![lid];
      if (cid == null) {
        cid = _uuid();
        await supabase.from('warehouses').insert({
          'id': cid,
          'name': w['name'] as String,
          'name_key': (w['name'] as String).toLowerCase().trim(),
          'is_active': _act(w['is_active']),
          'created_by': uid,
          'updated_by': uid,
          'created_at': now,
          'updated_at': now,
          'is_deleted': false,
        });
        _map['warehouses']![lid] = cid;
        _snap['warehouses']![lid] = f;
        _pAdd++;
      } else if (_snap['warehouses']![lid] != f) {
        await supabase.from('warehouses').update({
          'name': w['name'] as String,
          'is_active': _act(w['is_active']),
          'updated_by': uid,
          'updated_at': now,
        }).eq('id', cid);
        _snap['warehouses']![lid] = f;
        _pUpd++;
      }
      whL2C[w['id'] as int] = cid;
    }
    _pDel += await _pushDeletes('warehouses',
        {for (final w in local.warehouses) (w['id'] as int).toString()}, uid, now);

    // 2) الفواتير
    final invL2C = <int, String>{};
    for (final i in local.invoices) {
      final lid = (i['id'] as int).toString();
      final whCid = whL2C[i['warehouse_id'] as int];
      if (whCid == null) continue;
      final f = _fp([
        whCid,
        i['currency'],
        i['amount_minor'],
        i['paid_minor'],
        i['exchange_rate'],
        i['note'],
        i['invoice_date']
      ]);
      var cid = _map['invoices']![lid];
      if (cid == null) {
        cid = _uuid();
        await supabase.from('invoices').insert({
          'id': cid,
          'warehouse_id': whCid,
          'currency': i['currency'],
          'amount_minor': i['amount_minor'],
          'paid_minor': i['paid_minor'] ?? 0,
          'exchange_rate': i['exchange_rate'],
          'note': i['note'],
          'invoice_date': i['invoice_date'],
          'created_by': uid,
          'updated_by': uid,
          'created_at': now,
          'updated_at': now,
          'is_deleted': false,
        });
        _map['invoices']![lid] = cid;
        _snap['invoices']![lid] = f;
        _pAdd++;
      } else if (_snap['invoices']![lid] != f) {
        await supabase.from('invoices').update({
          'warehouse_id': whCid,
          'currency': i['currency'],
          'amount_minor': i['amount_minor'],
          'paid_minor': i['paid_minor'] ?? 0,
          'exchange_rate': i['exchange_rate'],
          'note': i['note'],
          'invoice_date': i['invoice_date'],
          'updated_by': uid,
          'updated_at': now,
        }).eq('id', cid);
        _snap['invoices']![lid] = f;
        _pUpd++;
      }
      invL2C[i['id'] as int] = cid;
    }
    _pDel += await _pushDeletes('invoices',
        {for (final i in local.invoices) (i['id'] as int).toString()}, uid, now);

    // 3) الصيدليات
    final pdL2C = <int, String>{};
    for (final d in local.pharmacyDebts) {
      final lid = (d['id'] as int).toString();
      final f = _fp([d['name']]);
      var cid = _map['pharmacy_debts']![lid];
      if (cid == null) {
        cid = _uuid();
        await supabase.from('pharmacy_debts').insert({
          'id': cid,
          'name': d['name'] as String,
          'name_key': (d['name'] as String).toLowerCase().trim(),
          'created_by': uid,
          'updated_by': uid,
          'created_at': now,
          'updated_at': now,
          'is_deleted': false,
        });
        _map['pharmacy_debts']![lid] = cid;
        _snap['pharmacy_debts']![lid] = f;
        _pAdd++;
      } else if (_snap['pharmacy_debts']![lid] != f) {
        await supabase.from('pharmacy_debts').update({
          'name': d['name'] as String,
          'updated_by': uid,
          'updated_at': now,
        }).eq('id', cid);
        _snap['pharmacy_debts']![lid] = f;
        _pUpd++;
      }
      pdL2C[d['id'] as int] = cid;
    }
    _pDel += await _pushDeletes('pharmacy_debts',
        {for (final d in local.pharmacyDebts) (d['id'] as int).toString()}, uid, now);

    // 4) العمليات
    for (final t in local.transactions) {
      final lid = (t['id'] as int).toString();
      final whCid = t['warehouse_id'] == null ? null : whL2C[t['warehouse_id'] as int];
      if (t['type'] == 'PAYMENT' && whCid == null) continue;
      final f = _fp([
        t['type'],
        t['amount_minor'],
        t['currency'],
        whCid,
        t['invoice_number'],
        t['note'],
        t['transaction_date'],
        t['transaction_time']
      ]);
      var cid = _map['transactions']![lid];
      if (cid == null) {
        cid = _uuid();
        await supabase.from('transactions').insert({
          'id': cid,
          'type': t['type'],
          'amount_minor': t['amount_minor'],
          'currency': t['currency'],
          'warehouse_id': whCid,
          'invoice_number': t['invoice_number'],
          'note': t['note'],
          'transaction_date': t['transaction_date'],
          'transaction_time': t['transaction_time'],
          'created_by': uid,
          'updated_by': uid,
          'created_at': now,
          'updated_at': now,
          'is_deleted': false,
        });
        _map['transactions']![lid] = cid;
        _snap['transactions']![lid] = f;
        _pAdd++;
      } else if (_snap['transactions']![lid] != f) {
        await supabase.from('transactions').update({
          'type': t['type'],
          'amount_minor': t['amount_minor'],
          'currency': t['currency'],
          'warehouse_id': whCid,
          'invoice_number': t['invoice_number'],
          'note': t['note'],
          'transaction_date': t['transaction_date'],
          'transaction_time': t['transaction_time'],
          'updated_by': uid,
          'updated_at': now,
        }).eq('id', cid);
        _snap['transactions']![lid] = f;
        _pUpd++;
      }
    }
    _pDel += await _pushDeletes('transactions',
        {for (final t in local.transactions) (t['id'] as int).toString()}, uid, now);

    // 5) دفعات الفواتير
    for (final q in local.invoicePayments) {
      final lid = (q['id'] as int).toString();
      final invCid = invL2C[q['invoice_id'] as int];
      if (invCid == null) continue;
      final f = _fp([
        invCid,
        q['amount_minor'],
        q['currency_paid'],
        q['exchange_rate'],
        q['note'],
        q['payment_date'],
        q['payment_time']
      ]);
      var cid = _map['invoice_payments']![lid];
      if (cid == null) {
        cid = _uuid();
        await supabase.from('invoice_payments').insert({
          'id': cid,
          'invoice_id': invCid,
          'amount_minor': q['amount_minor'],
          'currency_paid': q['currency_paid'],
          'exchange_rate': q['exchange_rate'],
          'note': q['note'],
          'payment_date': q['payment_date'],
          'payment_time': q['payment_time'],
          'created_by': uid,
          'updated_by': uid,
          'created_at': now,
          'updated_at': now,
          'is_deleted': false,
        });
        _map['invoice_payments']![lid] = cid;
        _snap['invoice_payments']![lid] = f;
        _pAdd++;
      } else if (_snap['invoice_payments']![lid] != f) {
        await supabase.from('invoice_payments').update({
          'invoice_id': invCid,
          'amount_minor': q['amount_minor'],
          'currency_paid': q['currency_paid'],
          'exchange_rate': q['exchange_rate'],
          'note': q['note'],
          'payment_date': q['payment_date'],
          'payment_time': q['payment_time'],
          'updated_by': uid,
          'updated_at': now,
        }).eq('id', cid);
        _snap['invoice_payments']![lid] = f;
        _pUpd++;
      }
    }
    _pDel += await _pushDeletes(
        'invoice_payments',
        {for (final q in local.invoicePayments) (q['id'] as int).toString()},
        uid,
        now);

    // 6) حركات الديون
    for (final e in local.pharmacyDebtEntries) {
      final lid = (e['id'] as int).toString();
      final pdCid = pdL2C[e['pharmacy_id'] as int];
      if (pdCid == null) continue;
      final f = _fp([
        pdCid,
        e['direction'],
        e['amount_minor'],
        e['currency'],
        e['note'],
        e['entry_date'],
        e['entry_time']
      ]);
      var cid = _map['pharmacy_debt_entries']![lid];
      if (cid == null) {
        cid = _uuid();
        await supabase.from('pharmacy_debt_entries').insert({
          'id': cid,
          'pharmacy_id': pdCid,
          'direction': e['direction'],
          'amount_minor': e['amount_minor'],
          'currency': e['currency'],
          'note': e['note'],
          'entry_date': e['entry_date'],
          'entry_time': e['entry_time'],
          'created_by': uid,
          'updated_by': uid,
          'created_at': now,
          'updated_at': now,
          'is_deleted': false,
        });
        _map['pharmacy_debt_entries']![lid] = cid;
        _snap['pharmacy_debt_entries']![lid] = f;
        _pAdd++;
      } else if (_snap['pharmacy_debt_entries']![lid] != f) {
        await supabase.from('pharmacy_debt_entries').update({
          'pharmacy_id': pdCid,
          'direction': e['direction'],
          'amount_minor': e['amount_minor'],
          'currency': e['currency'],
          'note': e['note'],
          'entry_date': e['entry_date'],
          'entry_time': e['entry_time'],
          'updated_by': uid,
          'updated_at': now,
        }).eq('id', cid);
        _snap['pharmacy_debt_entries']![lid] = f;
        _pUpd++;
      }
    }
    _pDel += await _pushDeletes(
        'pharmacy_debt_entries',
        {for (final e in local.pharmacyDebtEntries) (e['id'] as int).toString()},
        uid,
        now);

    await _saveState();
    _lastSummary = 'تنزيل: +$_gAdd جديد / -$_gDel محذوف\n'
        'رفع: +$_pAdd جديد / ~$_pUpd معدّل / -$_pDel محذوف';
  }

  Future<int> _pushDeletes(
      String table, Set<String> liveLocalIds, String uid, String now) async {
    if (liveLocalIds.isEmpty) return 0; // حماية من مسح السحابة عند قائمة محلية فارغة
    final supabase = Supabase.instance.client;
    var n = 0;
    for (final e in _map[table]!.entries.toList()) {
      if (liveLocalIds.contains(e.key)) continue;
      await supabase.from(table).update({
        'is_deleted': true,
        'deleted_by': uid,
        'deleted_at': now,
      }).eq('id', e.value);
      _map[table]!.remove(e.key);
      _snap[table]!.remove(e.key);
      n++;
    }
    return n;
  }
}