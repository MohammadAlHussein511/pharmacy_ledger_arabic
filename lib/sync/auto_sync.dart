import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_service.dart';
import '../services.dart';

/// محرك المزامنة v6: يدعم الفواتير وديون الصيدليات + بصمات بدل الساعات + 15 ثانية.
class AutoSync {
  AutoSync(this._services);

  static AutoSync? current;

  final AppServices _services;
  Timer? _timer;
  bool _running = false;
  bool _mapLoaded = false;
  Map<String, Map<String, String>> _map = {
    'warehouses': {},
    'transactions': {},
    'invoices': {},
    'invoice_payments': {},
    'pharmacy_debts': {},
    'pharmacy_debt_entries': {},
  };
  Map<String, Map<String, String>> _seen = {
    'wh': {}, 'tx': {}, 'inv': {}, 'invp': {}, 'pd': {}, 'pde': {},
  };

  int gWhAdd = 0, gWhUpd = 0, gWhDel = 0, gTxAdd = 0, gTxUpd = 0, gTxDel = 0;
  int gInvAdd = 0, gInvUpd = 0, gInvDel = 0;
  int gInvPAdd = 0, gInvPUpd = 0, gInvPDel = 0;
  int gPdAdd = 0, gPdUpd = 0, gPdDel = 0;
  int gPdeAdd = 0, gPdeUpd = 0, gPdeDel = 0;
  int pWhAdd = 0, pWhUpd = 0, pWhDel = 0, pTxAdd = 0, pTxUpd = 0, pTxDel = 0;
  int pInvAdd = 0, pInvUpd = 0, pInvDel = 0;
  int pInvPAdd = 0, pInvPUpd = 0, pInvPDel = 0;
  int pPdAdd = 0, pPdUpd = 0, pPdDel = 0;
  int pPdeAdd = 0, pPdeUpd = 0, pPdeDel = 0;

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

  String summary() {
    final pulls = [
      if (gWhAdd + gWhUpd + gWhDel > 0) 'مستودعات: +$gWhAdd/~$gWhUpd/-$gWhDel',
      if (gTxAdd + gTxUpd + gTxDel > 0) 'عمليات: +$gTxAdd/~$gTxUpd/-$gTxDel',
      if (gInvAdd + gInvUpd + gInvDel > 0) 'فواتير: +$gInvAdd/~$gInvUpd/-$gInvDel',
      if (gInvPAdd + gInvPUpd + gInvPDel > 0) 'دفعات فواتير: +$gInvPAdd/~$gInvPUpd/-$gInvPDel',
      if (gPdAdd + gPdUpd + gPdDel > 0) 'صيدليات: +$gPdAdd/~$gPdUpd/-$gPdDel',
      if (gPdeAdd + gPdeUpd + gPdeDel > 0) 'حركات ديون: +$gPdeAdd/~$gPdeUpd/-$gPdeDel',
    ];
    final pushes = [
      if (pWhAdd + pWhUpd + pWhDel > 0) 'مستودعات: +$pWhAdd/~$pWhUpd/-$pWhDel',
      if (pTxAdd + pTxUpd + pTxDel > 0) 'عمليات: +$pTxAdd/~$pTxUpd/-$pTxDel',
      if (pInvAdd + pInvUpd + pInvDel > 0) 'فواتير: +$pInvAdd/~$pInvUpd/-$pInvDel',
      if (pInvPAdd + pInvPUpd + pInvPDel > 0) 'دفعات فواتير: +$pInvPAdd/~$pInvPUpd/-$pInvPDel',
      if (pPdAdd + pPdUpd + pPdDel > 0) 'صيدليات: +$pPdAdd/~$pPdUpd/-$pPdDel',
      if (pPdeAdd + pPdeUpd + pPdeDel > 0) 'حركات ديون: +$pPdeAdd/~$pPdeUpd/-$pPdeDel',
    ];
    final pl = pulls.isEmpty ? 'لا شيء' : pulls.join('، ');
    final ps = pushes.isEmpty ? 'لا شيء' : pushes.join('، ');
    return 'تنزيل: $pl\nرفع: $ps';
  }

  Future<String> syncNow() async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return 'غير مسجل الدخول! سجّل الدخول من الإعدادات أولاً.';
    if (_running) return 'المزامنة تعمل حالياً... انتظر لحظة.';
    _running = true;
    try {
      await _loadMap();
      await _pullMerge(uid);
      await _pushDiff(uid);
      return 'تمت المزامنة بنجاح ✅\n${summary()}';
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
      await _loadMap();
      await _pullMerge(uid);
      await _pushDiff(uid);
    } catch (e) {
      debugPrint('[sync] cycle error: $e');
    } finally {
      _running = false;
    }
  }

  Future<File> _mapFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'sync_mapping.json'));
  }

  Future<void> _loadMap() async {
    if (_mapLoaded) return;
    try {
      final f = await _mapFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        for (final k in _map.keys) {
          _map[k] = Map<String, String>.from(j[k] ?? {});
        }
        for (final k in _seen.keys) {
          _seen[k] = Map<String, String>.from(j['seen_$k'] ?? {});
        }
      }
    } catch (_) {}
    _mapLoaded = true;
  }

  Future<void> _saveMap() async {
    try {
      final f = await _mapFile();
      final payload = <String, dynamic>{..._map};
      for (final k in _seen.keys) {
        payload['seen_$k'] = _seen[k];
      }
      await f.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  bool _same(dynamic a, dynamic b) => '$a' == '$b';
  bool _active(dynamic v) => v == true || v == 1 || v == '1';
  bool _deleted(dynamic v) => v == true;

  List<Map<String, dynamic>> _asRows(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map<Map<String, dynamic>>(
            (m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<BackupPreview> _local() async {
    final bytes = await _services.backup.createBackup();
    final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (env['encrypted'] == true) {
      return _services.backup.inspect(bytes);
    }
    final data = env['data'] as Map<String, dynamic>;
    return BackupPreview(
      createdAt: null,
      appVersion: '',
      encrypted: false,
      warehouses: _asRows(data['warehouses']),
      transactions: _asRows(data['transactions']),
      invoices: _asRows(data['invoices'] ?? []),
      invoicePayments: _asRows(data['invoice_payments'] ?? []),
      pharmacyDebts: _asRows(data['pharmacy_debts'] ?? []),
      pharmacyDebtEntries: _asRows(data['pharmacy_debt_entries'] ?? []),
    );
  }

  // ================= التنزيل والدمج =================
  Future<void> _pullMerge(String uid) async {
    _resetCounters();
    final supabase = Supabase.instance.client;
    final local = await _local();

    // جلب كل الجداول السحابية
    final cloudWh = _asRows(await supabase.from('warehouses').select('*'))
        .where((w) => w['name'] is String && w['name_key'] is String).toList();
    final cloudTx = _asRows(await supabase.from('transactions').select('*'))
        .where((t) =>
            t['type'] is String && t['amount_minor'] is int &&
            t['currency'] is String && t['transaction_date'] is String &&
            t['transaction_time'] is String).toList();
    final cloudInv = _asRows(await supabase.from('invoices').select('*'))
        .where((i) => i['currency'] is String && i['amount_minor'] is int &&
            i['invoice_date'] is String).toList();
    final cloudInvP = _asRows(await supabase.from('invoice_payments').select('*'))
        .where((p) => p['amount_minor'] is int && p['currency_paid'] is String &&
            p['payment_date'] is String && p['payment_time'] is String).toList();
    final cloudPd = _asRows(await supabase.from('pharmacy_debts').select('*'))
        .where((p) => p['name'] is String && p['name_key'] is String).toList();
    final cloudPde = _asRows(await supabase.from('pharmacy_debt_entries').select('*'))
        .where((e) => e['direction'] is String && e['amount_minor'] is int &&
            e['currency'] is String && e['entry_date'] is String &&
            e['entry_time'] is String).toList();

    // جداول البحث السريع
    final whByCloud = {for (final w in cloudWh) w['id'] as String: w};
    final txByCloud = {for (final t in cloudTx) t['id'] as String: t};
    final invByCloud = {for (final i in cloudInv) i['id'] as String: i};
    final invPByCloud = {for (final p in cloudInvP) p['id'] as String: p};
    final pdByCloud = {for (final p in cloudPd) p['id'] as String: p};
    final pdeByCloud = {for (final e in cloudPde) e['id'] as String: e};

    final mapW = _map['warehouses']!;
    final mapT = _map['transactions']!;
    final mapI = _map['invoices']!;
    final mapIP = _map['invoice_payments']!;
    final mapPd = _map['pharmacy_debts']!;
    final mapPde = _map['pharmacy_debt_entries']!;
    final revW = {for (final e in mapW.entries) e.value: e.key};
    final revT = {for (final e in mapT.entries) e.value: e.key};
    final revI = {for (final e in mapI.entries) e.value: e.key};
    final revIP = {for (final e in mapIP.entries) e.value: e.key};
    final revPd = {for (final e in mapPd.entries) e.value: e.key};
    final revPde = {for (final e in mapPde.entries) e.value: e.key};

    final localWhByKey = {for (final w in local.warehouses)
        (w['name_key'] as String).toLowerCase().trim(): (w['id'] as int).toString()};
    final localTxKeys = {for (final t in local.transactions)
        '${t['invoice_number']}_${t['transaction_date']}_'
        '${t['amount_minor']}_${t['currency']}': (t['id'] as int).toString()};
    final localPdByKey = {for (final p in local.pharmacyDebts)
        (p['name_key'] as String).toLowerCase().trim(): (p['id'] as int).toString()};

    final mergedWh = <Map<String, Object?>>[];
    final mergedTx = <Map<String, Object?>>[];
    final mergedInv = <Map<String, Object?>>[];
    final mergedInvP = <Map<String, Object?>>[];
    final mergedPd = <Map<String, Object?>>[];
    final mergedPde = <Map<String, Object?>>[];
    final whCloudToLocal = <String, int>{};
    final invCloudToLocal = <String, int>{};
    final pdCloudToLocal = <String, int>{};
    var changed = false;

    var maxWhId = 0, maxTxId = 0, maxInvId = 0, maxInvPId = 0, maxPdId = 0, maxPdeId = 0;
    for (final w in local.warehouses) {
      if ((w['id'] as int) > maxWhId) maxWhId = w['id'] as int;
    }
    for (final t in local.transactions) {
      if ((t['id'] as int) > maxTxId) maxTxId = t['id'] as int;
    }
    for (final i in local.invoices) {
      if ((i['id'] as int) > maxInvId) maxInvId = i['id'] as int;
    }
    for (final p in local.invoicePayments) {
      if ((p['id'] as int) > maxInvPId) maxInvPId = p['id'] as int;
    }
    for (final p in local.pharmacyDebts) {
      if ((p['id'] as int) > maxPdId) maxPdId = p['id'] as int;
    }
    for (final e in local.pharmacyDebtEntries) {
      if ((e['id'] as int) > maxPdeId) maxPdeId = e['id'] as int;
    }

    // 1) المستودعات المحلية
    for (final w in local.warehouses) {
      final lid = (w['id'] as int).toString();
      final cid = mapW[lid];
      if (cid == null) { mergedWh.add(w); continue; }
      final crow = whByCloud[cid];
      if (crow == null || _deleted(crow['is_deleted'])) {
        mapW.remove(lid); _seen['wh']!.remove(cid); gWhDel++; changed = true; continue;
      }
      whCloudToLocal[cid] = int.parse(lid);
      final cupd = '${crow['updated_at']}';
      if (_seen['wh']![cid] != cupd) {
        mergedWh.add(_whRow(crow, int.parse(lid)) ?? w);
        _seen['wh']![cid] = cupd; gWhUpd++; changed = true;
      } else {
        mergedWh.add(w);
      }
    }

    // 2) المستودعات السحابية الجديدة
    for (final crow in cloudWh) {
      final cid = crow['id'] as String;
      if (_deleted(crow['is_deleted']) || revW.containsKey(cid)) continue;
      final nameKey = (crow['name_key'] as String).toLowerCase().trim();
      final existingLocal = localWhByKey[nameKey];
      if (existingLocal != null) {
        if (!mapW.containsKey(existingLocal)) {
          mapW[existingLocal] = cid;
          _seen['wh']![cid] = '${crow['updated_at']}';
          whCloudToLocal[cid] = int.parse(existingLocal);
        }
        continue;
      }
      final lid = ++maxWhId;
      final row = _whRow(crow, lid);
      if (row == null) continue;
      mergedWh.add(row);
      mapW[lid.toString()] = cid;
      _seen['wh']![cid] = '${crow['updated_at']}';
      whCloudToLocal[cid] = lid;
      gWhAdd++; changed = true;
    }

    // 3) العمليات المحلية
    for (final t in local.transactions) {
      final lid = (t['id'] as int).toString();
      final cid = mapT[lid];
      if (cid == null) { mergedTx.add(t); continue; }
      final crow = txByCloud[cid];
      if (crow == null || _deleted(crow['is_deleted'])) {
        mapT.remove(lid); _seen['tx']!.remove(cid); gTxDel++; changed = true; continue;
      }
      final cupd = '${crow['updated_at']}';
      if (_seen['tx']![cid] != cupd) {
        final row = _txRow(crow, int.parse(lid), whCloudToLocal);
        if (row == null) {
          mapT.remove(lid); _seen['tx']!.remove(cid); gTxDel++;
        } else {
          mergedTx.add(row); _seen['tx']![cid] = cupd; gTxUpd++;
        }
        changed = true;
      } else {
        mergedTx.add(t);
      }
    }

    // 4) العمليات السحابية الجديدة
    for (final crow in cloudTx) {
      final cid = crow['id'] as String;
      if (_deleted(crow['is_deleted']) || revT.containsKey(cid)) continue;
      final key = '${crow['invoice_number']}_${crow['transaction_date']}_'
          '${crow['amount_minor']}_${crow['currency']}';
      final existingLocal = localTxKeys[key];
      if (existingLocal != null) {
        if (!mapT.containsKey(existingLocal)) {
          mapT[existingLocal] = cid;
          _seen['tx']![cid] = '${crow['updated_at']}';
        }
        continue;
      }
      final lid = ++maxTxId;
      final row = _txRow(crow, lid, whCloudToLocal);
      if (row == null) continue;
      mergedTx.add(row);
      mapT[lid.toString()] = cid;
      _seen['tx']![cid] = '${crow['updated_at']}';
      gTxAdd++; changed = true;
    }

    // 5) الفواتير المحلية
    for (final i in local.invoices) {
      final lid = (i['id'] as int).toString();
      final cid = mapI[lid];
      if (cid == null) { mergedInv.add(i); continue; }
      final crow = invByCloud[cid];
      if (crow == null || _deleted(crow['is_deleted'])) {
        mapI.remove(lid); _seen['inv']!.remove(cid); gInvDel++; changed = true; continue;
      }
      final localWh = crow['warehouse_id'] as String?;
      final lidWh = localWh == null ? null : whCloudToLocal[localWh];
      if (lidWh == null) {
        mapI.remove(lid); _seen['inv']!.remove(cid); gInvDel++; changed = true; continue;
      }
      invCloudToLocal[cid] = int.parse(lid);
      final cupd = '${crow['updated_at']}';
      if (_seen['inv']![cid] != cupd) {
        mergedInv.add(_invRow(crow, int.parse(lid), whCloudToLocal) ?? i);
        _seen['inv']![cid] = cupd; gInvUpd++; changed = true;
      } else {
        mergedInv.add(i);
      }
    }

    // 6) الفواتير السحابية الجديدة
    for (final crow in cloudInv) {
      final cid = crow['id'] as String;
      if (_deleted(crow['is_deleted']) || revI.containsKey(cid)) continue;
      final lid = ++maxInvId;
      final row = _invRow(crow, lid, whCloudToLocal);
      if (row == null) continue;
      mergedInv.add(row);
      mapI[lid.toString()] = cid;
      _seen['inv']![cid] = '${crow['updated_at']}';
      invCloudToLocal[cid] = lid;
      gInvAdd++; changed = true;
    }

    // 7) دفعات الفواتير المحلية
    for (final p in local.invoicePayments) {
      final lid = (p['id'] as int).toString();
      final cid = mapIP[lid];
      if (cid == null) { mergedInvP.add(p); continue; }
      final crow = invPByCloud[cid];
      if (crow == null || _deleted(crow['is_deleted'])) {
        mapIP.remove(lid); _seen['invp']!.remove(cid); gInvPDel++; changed = true; continue;
      }
      final cupd = '${crow['updated_at']}';
      if (_seen['invp']![cid] != cupd) {
        mergedInvP.add(_invPRow(crow, int.parse(lid), invCloudToLocal) ?? p);
        _seen['invp']![cid] = cupd; gInvPUpd++; changed = true;
      } else {
        mergedInvP.add(p);
      }
    }

    // 8) دفعات الفواتير السحابية الجديدة
    for (final crow in cloudInvP) {
      final cid = crow['id'] as String;
      if (_deleted(crow['is_deleted']) || revIP.containsKey(cid)) continue;
      final lid = ++maxInvPId;
      final row = _invPRow(crow, lid, invCloudToLocal);
      if (row == null) continue;
      mergedInvP.add(row);
      mapIP[lid.toString()] = cid;
      _seen['invp']![cid] = '${crow['updated_at']}';
      gInvPAdd++; changed = true;
    }

    // 9) الصيدليات المحلية
    for (final pd in local.pharmacyDebts) {
      final lid = (pd['id'] as int).toString();
      final cid = mapPd[lid];
      if (cid == null) { mergedPd.add(pd); continue; }
      final crow = pdByCloud[cid];
      if (crow == null || _deleted(crow['is_deleted'])) {
        mapPd.remove(lid); _seen['pd']!.remove(cid); gPdDel++; changed = true; continue;
      }
      pdCloudToLocal[cid] = int.parse(lid);
      final cupd = '${crow['updated_at']}';
      if (_seen['pd']![cid] != cupd) {
        mergedPd.add(_pdRow(crow, int.parse(lid)) ?? pd);
        _seen['pd']![cid] = cupd; gPdUpd++; changed = true;
      } else {
        mergedPd.add(pd);
      }
    }

    // 10) الصيدليات السحابية الجديدة
    for (final crow in cloudPd) {
      final cid = crow['id'] as String;
      if (_deleted(crow['is_deleted']) || revPd.containsKey(cid)) continue;
      final nameKey = (crow['name_key'] as String).toLowerCase().trim();
      final existingLocal = localPdByKey[nameKey];
      if (existingLocal != null) {
        if (!mapPd.containsKey(existingLocal)) {
          mapPd[existingLocal] = cid;
          _seen['pd']![cid] = '${crow['updated_at']}';
          pdCloudToLocal[cid] = int.parse(existingLocal);
        }
        continue;
      }
      final lid = ++maxPdId;
      final row = _pdRow(crow, lid);
      if (row == null) continue;
      mergedPd.add(row);
      mapPd[lid.toString()] = cid;
      _seen['pd']![cid] = '${crow['updated_at']}';
      pdCloudToLocal[cid] = lid;
      gPdAdd++; changed = true;
    }

    // 11) حركات الديون المحلية
    for (final e in local.pharmacyDebtEntries) {
      final lid = (e['id'] as int).toString();
      final cid = mapPde[lid];
      if (cid == null) { mergedPde.add(e); continue; }
      final crow = pdeByCloud[cid];
      if (crow == null || _deleted(crow['is_deleted'])) {
        mapPde.remove(lid); _seen['pde']!.remove(cid); gPdeDel++; changed = true; continue;
      }
      final cupd = '${crow['updated_at']}';
      if (_seen['pde']![cid] != cupd) {
        mergedPde.add(_pdeRow(crow, int.parse(lid), pdCloudToLocal) ?? e);
        _seen['pde']![cid] = cupd; gPdeUpd++; changed = true;
      } else {
        mergedPde.add(e);
      }
    }

    // 12) حركات الديون السحابية الجديدة
    for (final crow in cloudPde) {
      final cid = crow['id'] as String;
      if (_deleted(crow['is_deleted']) || revPde.containsKey(cid)) continue;
      final lid = ++maxPdeId;
      final row = _pdeRow(crow, lid, pdCloudToLocal);
      if (row == null) continue;
      mergedPde.add(row);
      mapPde[lid.toString()] = cid;
      _seen['pde']![cid] = '${crow['updated_at']}';
      gPdeAdd++; changed = true;
    }

    // 13) تمرير أمان على العمليات
    final whIds = {for (final w in mergedWh) w['id'] as int};
    mergedTx.removeWhere((t) {
      final type = t['type']; final wh = t['warehouse_id'];
      if (type == 'SALE') return wh != null || t['currency'] != 'TRY';
      if (type == 'PAYMENT') return wh is! int || !whIds.contains(wh);
      return true;
    });

    // 14) تمرير أمان على الفواتير (يجب أن ترتبط بمستودع موجود)
    final validWhIds = {for (final w in mergedWh) w['id'] as int};
    mergedInv.removeWhere((i) {
      final wh = i['warehouse_id'];
      return wh is! int || !validWhIds.contains(wh);
    });
    final validInvIds = {for (final i in mergedInv) i['id'] as int};
    mergedInvP.removeWhere((p) {
      final inv = p['invoice_id'];
      return inv is! int || !validInvIds.contains(inv);
    });

    // 15) تمرير أمان على الصيدليات وحركات الديون
    final validPdIds = {for (final p in mergedPd) p['id'] as int};
    mergedPde.removeWhere((e) {
      final ph = e['pharmacy_id'];
      return ph is! int || !validPdIds.contains(ph);
    });

    if (changed) {
      try {
        await _services.backup.restore(BackupPreview(
          createdAt: DateTime.now(),
          appVersion: 'sync',
          encrypted: false,
          warehouses: mergedWh,
          transactions: mergedTx,
          invoices: mergedInv,
          invoicePayments: mergedInvP,
          pharmacyDebts: mergedPd,
          pharmacyDebtEntries: mergedPde,
        ));
        _services.store.changed();
      } catch (e) {
        debugPrint('[sync] restore FAILED: $e');
      }
    }
    await _saveMap();
  }

  // ---------- محولات السحابي -> محلي ----------
  Map<String, Object?>? _whRow(Map<String, dynamic> crow, int localId) {
    try {
      final name = crow['name'] as String?;
      final nameKey = crow['name_key'] as String?;
      if (name == null || nameKey == null) return null;
      return {
        'id': localId, 'name': name, 'name_key': nameKey,
        'is_active': _active(crow['is_active']) ? 1 : 0,
        'created_at': '${crow['created_at']}',
        'updated_at': '${crow['updated_at']}',
      };
    } catch (_) { return null; }
  }

  Map<String, Object?>? _txRow(Map<String, dynamic> crow, int localId,
      Map<String, int> whCloudToLocal) {
    try {
      final type = crow['type'] as String?;
      final amount = crow['amount_minor'] as int?;
      final currency = crow['currency'] as String?;
      final date = crow['transaction_date'] as String?;
      final time = crow['transaction_time'] as String?;
      if (type == null || amount == null || currency == null) return null;
      if (date == null || time == null) return null;
      final cwid = crow['warehouse_id'] as String?;
      final localWh = cwid == null ? null : whCloudToLocal[cwid];
      if (type == 'PAYMENT' && localWh == null) return null;
      return {
        'id': localId, 'type': type,
        'amount_minor': amount, 'currency': currency,
        'warehouse_id': type == 'SALE' ? null : localWh,
        'invoice_number': crow['invoice_number'] as String?,
        'note': crow['note'] as String?,
        'transaction_date': date, 'transaction_time': time,
        'created_at': '${crow['created_at']}',
        'updated_at': '${crow['updated_at']}',
      };
    } catch (_) { return null; }
  }

  Map<String, Object?>? _invRow(Map<String, dynamic> crow, int localId,
      Map<String, int> whCloudToLocal) {
    try {
      final whIdCloud = crow['warehouse_id'] as String?;
      final localWh = whIdCloud == null ? null : whCloudToLocal[whIdCloud];
      if (localWh == null) return null;
      return {
        'id': localId, 'warehouse_id': localWh,
        'currency': crow['currency'] as String,
        'amount_minor': crow['amount_minor'] as int,
        'paid_minor': (crow['paid_minor'] as int?) ?? 0,
        'exchange_rate': crow['exchange_rate'] as double?,
        'note': crow['note'] as String?,
        'invoice_date': crow['invoice_date'] as String,
        'created_at': '${crow['created_at']}',
        'updated_at': '${crow['updated_at']}',
      };
    } catch (_) { return null; }
  }

  Map<String, Object?>? _invPRow(Map<String, dynamic> crow, int localId,
      Map<String, int> invCloudToLocal) {
    try {
      final invIdCloud = crow['invoice_id'] as String?;
      final localInv = invIdCloud == null ? null : invCloudToLocal[invIdCloud];
      if (localInv == null) return null;
      return {
        'id': localId, 'invoice_id': localInv,
        'amount_minor': crow['amount_minor'] as int,
        'currency_paid': crow['currency_paid'] as String,
        'exchange_rate': crow['exchange_rate'] as double?,
        'note': crow['note'] as String?,
        'payment_date': crow['payment_date'] as String,
        'payment_time': crow['payment_time'] as String,
        'created_at': '${crow['created_at']}',
        'updated_at': '${crow['updated_at']}',
      };
    } catch (_) { return null; }
  }

  Map<String, Object?>? _pdRow(Map<String, dynamic> crow, int localId) {
    try {
      final name = crow['name'] as String?;
      final nameKey = crow['name_key'] as String?;
      if (name == null || nameKey == null) return null;
      return {
        'id': localId, 'name': name, 'name_key': nameKey,
        'created_at': '${crow['created_at']}',
        'updated_at': '${crow['updated_at']}',
      };
    } catch (_) { return null; }
  }

  Map<String, Object?>? _pdeRow(Map<String, dynamic> crow, int localId,
      Map<String, int> pdCloudToLocal) {
    try {
      final pdIdCloud = crow['pharmacy_id'] as String?;
      final localPd = pdIdCloud == null ? null : pdCloudToLocal[pdIdCloud];
      if (localPd == null) return null;
      return {
        'id': localId, 'pharmacy_id': localPd,
        'direction': crow['direction'] as String,
        'amount_minor': crow['amount_minor'] as int,
        'currency': crow['currency'] as String,
        'note': crow['note'] as String?,
        'entry_date': crow['entry_date'] as String,
        'entry_time': crow['entry_time'] as String,
        'created_at': '${crow['created_at']}',
        'updated_at': '${crow['updated_at']}',
      };
    } catch (_) { return null; }
  }

  // ================= الرفع =================
  Future<void> _pushDiff(String uid) async {
    _resetPushCounters();
    final details = <String>[];
    final supabase = Supabase.instance.client;
    final preview = await _local();
    final now = DateTime.now().toIso8601String();

    // 1) المستودعات
    final cloudWh = _asRows(await supabase.from('warehouses')
        .select('id, name_key, name, is_active')
        .or('is_deleted.is.null,is_deleted.eq.false'))
        .where((w) => w['name'] is String && w['name_key'] is String).toList();
    final whRows = {for (final w in cloudWh) w['id'] as String: w};
    final whByKey = {for (final w in cloudWh) (w['name_key'] as String): w['id'] as String};

    final mapW = _map['warehouses']!;
    final whMapping = <int, String>{};
    final localWhIds = <String>{};

    for (final wh in preview.warehouses) {
      final localId = (wh['id'] as int).toString();
      localWhIds.add(localId);
      final nameKey = (wh['name'] as String).toLowerCase().trim();
      var cloudId = mapW[localId] ?? whByKey[nameKey];
      if (cloudId == null) {
        cloudId = _uuid();
        await supabase.from('warehouses').insert({
          'id': cloudId, 'name': wh['name'] as String, 'name_key': nameKey,
          'is_active': _active(wh['is_active']),
          'created_by': uid, 'updated_by': uid,
          'created_at': now, 'updated_at': now, 'is_deleted': false,
        });
        _seen['wh']![cloudId] = now;
        details.add('➕ مستودع جديد: ${wh['name']}');
        pWhAdd++;
      } else {
        final row = whRows[cloudId];
        final changed = row == null ||
            !_same(row['name'], wh['name']) ||
            _active(row['is_active']) != _active(wh['is_active']);
        if (changed) {
          await supabase.from('warehouses').update({
            'name': wh['name'] as String,
            'is_active': _active(wh['is_active']),
            'updated_by': uid, 'updated_at': now,
          }).eq('id', cloudId);
          _seen['wh']![cloudId] = now;
          details.add('✏️ تعديل مستودع: ${wh['name']}');
          pWhUpd++;
        } else if (row != null) {
          _seen['wh']![cloudId] = '${row['updated_at']}';
        }
      }
      mapW[localId] = cloudId;
      whMapping[int.parse(localId)] = cloudId;
    }

    final whKnown = mapW.keys.where(localWhIds.contains).length;
    if (whKnown > 0) {
      for (final e in mapW.entries.toList()) {
        if (!localWhIds.contains(e.key)) {
          final name = whRows[e.value]?['name'] ?? 'مستودع';
          await supabase.from('warehouses').update({
            'is_deleted': true, 'deleted_by': uid, 'deleted_at': now,
          }).eq('id', e.value);
          mapW.remove(e.key); _seen['wh']!.remove(e.value);
          details.add('🗑️ حذف مستودع: $name');
          pWhDel++;
        }
      }
    }

    // 2) العمليات
    final cloudTx = _asRows(await supabase.from('transactions')
        .select('id, invoice_number, transaction_date, amount_minor, '
            'currency, type, warehouse_id, note, transaction_time')
        .or('is_deleted.is.null,is_deleted.eq.false'))
        .where((t) => t['type'] is String && t['amount_minor'] is int &&
            t['currency'] is String && t['transaction_date'] is String &&
            t['transaction_time'] is String).toList();
    final txRows = {for (final t in cloudTx) t['id'] as String: t};
    final txByKey = {for (final t in cloudTx)
        '${t['invoice_number']}_${t['transaction_date']}_'
        '${t['amount_minor']}_${t['currency']}': t['id'] as String};

    String txLabel(Map tx) =>
        '${tx['type'] == 'SALE' ? 'بيع' : 'دفعة'} ${_money(tx['amount_minor'], tx['currency'])}'
        '${tx['invoice_number'] != null ? ' (فاتورة ${tx['invoice_number']})' : ''}';

    final mapT = _map['transactions']!;
    final localTxIds = <String>{};

    for (final tx in preview.transactions) {
      final key = '${tx['invoice_number']}_${tx['transaction_date']}_'
          '${tx['amount_minor']}_${tx['currency']}';
      final localId = (tx['id'] as int).toString();
      localTxIds.add(localId);
      final oldWh = tx['warehouse_id'] as int?;
      final cloudWhId = oldWh == null ? null : whMapping[oldWh];
      var cloudId = mapT[localId] ?? txByKey[key];

      if (cloudId == null) {
        cloudId = _uuid();
        await supabase.from('transactions').insert({
          'id': cloudId, 'type': tx['type'] as String,
          'amount_minor': tx['amount_minor'] as int,
          'currency': tx['currency'] as String,
          'warehouse_id': cloudWhId,
          'invoice_number': tx['invoice_number'] as String?,
          'note': tx['note'] as String?,
          'transaction_date': tx['transaction_date'] as String,
          'transaction_time': tx['transaction_time'] as String,
          'created_by': uid, 'updated_by': uid,
          'created_at': now, 'updated_at': now, 'is_deleted': false,
        });
        _seen['tx']![cloudId] = now;
        details.add('➕ ${txLabel(tx)}');
        pTxAdd++;
      } else {
        final row = txRows[cloudId];
        final changed = row == null ||
            !_same(row['type'], tx['type']) ||
            !_same(row['amount_minor'], tx['amount_minor']) ||
            !_same(row['currency'], tx['currency']) ||
            !_same(row['warehouse_id'], cloudWhId) ||
            !_same(row['invoice_number'], tx['invoice_number']) ||
            !_same(row['note'], tx['note']) ||
            !_same(row['transaction_date'], tx['transaction_date']) ||
            !_same(row['transaction_time'], tx['transaction_time']);
        if (changed) {
          await supabase.from('transactions').update({
            'type': tx['type'] as String,
            'amount_minor': tx['amount_minor'] as int,
            'currency': tx['currency'] as String,
            'warehouse_id': cloudWhId,
            'invoice_number': tx['invoice_number'] as String?,
            'note': tx['note'] as String?,
            'transaction_date': tx['transaction_date'] as String,
            'transaction_time': tx['transaction_time'] as String,
            'updated_by': uid, 'updated_at': now,
          }).eq('id', cloudId);
          _seen['tx']![cloudId] = now;
          details.add('✏️ تعديل ${txLabel(tx)}');
          pTxUpd++;
        } else if (row != null) {
          _seen['tx']![cloudId] = '${row['updated_at']}';
        }
      }
      mapT[localId] = cloudId;
    }

    final txKnown = mapT.keys.where(localTxIds.contains).length;
    if (txKnown > 0) {
      for (final e in mapT.entries.toList()) {
        if (!localTxIds.contains(e.key)) {
          final row = txRows[e.value];
          await supabase.from('transactions').update({
            'is_deleted': true, 'deleted_by': uid, 'deleted_at': now,
          }).eq('id', e.value);
          mapT.remove(e.key); _seen['tx']!.remove(e.value);
          details.add(row == null ? '🗑️ حذف عملية' : '🗑️ حذف ${txLabel(row)}');
          pTxDel++;
        }
      }
    }

    // 3) الفواتير
    final invMapping = await _pushTable(
      table: 'invoices',
      items: preview.invoices,
      map: _map['invoices']!,
      seenKey: 'inv',
      toInsert: (i) => {
        'warehouse_id': whMapping[i['warehouse_id'] as int],
        'currency': i['currency'], 'amount_minor': i['amount_minor'],
        'paid_minor': i['paid_minor'] ?? 0,
        'exchange_rate': i['exchange_rate'],
        'note': i['note'], 'invoice_date': i['invoice_date'],
      },
      toUpdate: (i) => {
        'warehouse_id': whMapping[i['warehouse_id'] as int],
        'currency': i['currency'], 'amount_minor': i['amount_minor'],
        'paid_minor': i['paid_minor'] ?? 0,
        'exchange_rate': i['exchange_rate'],
        'note': i['note'], 'invoice_date': i['invoice_date'],
      },
      label: (i) => 'فاتورة ${i['invoice_date']} ${_money(i['amount_minor'], i['currency'])}',
      details: details,
      counter: (a, u, d) { pInvAdd = a; pInvUpd = u; pInvDel = d; },
      uid: uid, now: now,
    );

    // 4) دفعات الفواتير
    await _pushTable(
      table: 'invoice_payments',
      items: preview.invoicePayments,
      map: _map['invoice_payments']!,
      seenKey: 'invp',
      toInsert: (p) => {
        'invoice_id': invMapping[p['invoice_id'] as int],
        'amount_minor': p['amount_minor'],
        'currency_paid': p['currency_paid'],
        'exchange_rate': p['exchange_rate'],
        'note': p['note'],
        'payment_date': p['payment_date'],
        'payment_time': p['payment_time'],
      },
      toUpdate: (p) => {
        'invoice_id': invMapping[p['invoice_id'] as int],
        'amount_minor': p['amount_minor'],
        'currency_paid': p['currency_paid'],
        'exchange_rate': p['exchange_rate'],
        'note': p['note'],
        'payment_date': p['payment_date'],
        'payment_time': p['payment_time'],
      },
      label: (p) => 'دفعة فاتورة ${_money(p['amount_minor'], p['currency_paid'])}',
      details: details,
      counter: (a, u, d) { pInvPAdd = a; pInvPUpd = u; pInvPDel = d; },
      uid: uid, now: now,
    );

    // 5) الصيدليات
    final pdMapping = await _pushTable(
      table: 'pharmacy_debts',
      items: preview.pharmacyDebts,
      map: _map['pharmacy_debts']!,
      seenKey: 'pd',
      toInsert: (p) => {
        'name': p['name'],
        'name_key': (p['name'] as String).toLowerCase().trim(),
      },
      toUpdate: (p) => {'name': p['name']},
      label: (p) => 'صيدلية ${p['name']}',
      details: details,
      counter: (a, u, d) { pPdAdd = a; pPdUpd = u; pPdDel = d; },
      uid: uid, now: now,
    );

    // 6) حركات الديون
    await _pushTable(
      table: 'pharmacy_debt_entries',
      items: preview.pharmacyDebtEntries,
      map: _map['pharmacy_debt_entries']!,
      seenKey: 'pde',
      toInsert: (e) => {
        'pharmacy_id': pdMapping[e['pharmacy_id'] as int],
        'direction': e['direction'],
        'amount_minor': e['amount_minor'],
        'currency': e['currency'],
        'note': e['note'],
        'entry_date': e['entry_date'],
        'entry_time': e['entry_time'],
      },
      toUpdate: (e) => {
        'pharmacy_id': pdMapping[e['pharmacy_id'] as int],
        'direction': e['direction'],
        'amount_minor': e['amount_minor'],
        'currency': e['currency'],
        'note': e['note'],
        'entry_date': e['entry_date'],
        'entry_time': e['entry_time'],
      },
      label: (e) => '${e['direction'] == 'OWED_TO_US' ? 'ما لنا' : 'ما علينا'} ${_money(e['amount_minor'], e['currency'])}',
      details: details,
      counter: (a, u, d) { pPdeAdd = a; pPdeUpd = u; pPdeDel = d; },
      uid: uid, now: now,
    );

    await _saveMap();
    if (details.isNotEmpty) await _notifyOthers(uid, details);
  }

  /// دالة عامة لرفع أي جدول (مستودعات، عمليات، فواتير، صيدليات...)
  /// تُعيد خريطة <localId, cloudId> لاستخدامها في الجداول التابعة.
  Future<Map<int, String>> _pushTable({
    required String table,
    required List<Map<String, Object?>> items,
    required Map<String, String> map,
    required String seenKey,
    required Map<String, Object?> Function(Map<String, Object?>) toInsert,
    required Map<String, Object?> Function(Map<String, Object?>) toUpdate,
    required String Function(Map<String, Object?>) label,
    required List<String> details,
    required void Function(int add, int upd, int del) counter,
    required String uid,
    required String now,
  }) async {
    final supabase = Supabase.instance.client;
    final cloudRaw = await supabase.from(table)
        .select('id, updated_at')
        .or('is_deleted.is.null,is_deleted.eq.false');
    final cloud = _asRows(cloudRaw);
    final cloudById = {for (final r in cloud) r['id'] as String: r};

    var add = 0, upd = 0, del = 0;
    final localIds = <String>{};
    final mapping = <int, String>{};

    for (final item in items) {
      final localId = (item['id'] as int).toString();
      localIds.add(localId);
      var cloudId = map[localId];

      if (cloudId == null) {
        cloudId = _uuid();
        final data = toInsert(item);
        await supabase.from(table).insert({
          'id': cloudId,
          ...data,
          'created_by': uid, 'updated_by': uid,
          'created_at': now, 'updated_at': now, 'is_deleted': false,
        });
        _seen[seenKey]![cloudId] = now;
        details.add('➕ ${label(item)}');
        add++;
      } else {
        final row = cloudById[cloudId];
        final cupd = row?['updated_at']?.toString();
        final data = toUpdate(item);
        final localSeen = _seen[seenKey]![cloudId];
        final needsUpdate = cupd == null || (localSeen != null && localSeen != cupd);
        if (needsUpdate) {
          await supabase.from(table).update({
            ...data,
            'updated_by': uid, 'updated_at': now,
          }).eq('id', cloudId);
          _seen[seenKey]![cloudId] = now;
          details.add('✏️ تعديل ${label(item)}');
          upd++;
        }
      }
      map[localId] = cloudId;
      mapping[int.parse(localId)] = cloudId;
    }

    final known = map.keys.where(localIds.contains).length;
    if (known > 0) {
      for (final e in map.entries.toList()) {
        if (!localIds.contains(e.key)) {
          await supabase.from(table).update({
            'is_deleted': true, 'deleted_by': uid, 'deleted_at': now,
          }).eq('id', e.value);
          map.remove(e.key);
          _seen[seenKey]!.remove(e.value);
          details.add('🗑️ حذف ${table}');
          del++;
        }
      }
    }
    counter(add, upd, del);
    return mapping;
  }

  String _money(dynamic minor, dynamic cur) =>
      '${((minor as int) / 100).toStringAsFixed(2)} $cur';

  void _resetCounters() {
    gWhAdd = 0; gWhUpd = 0; gWhDel = 0;
    gTxAdd = 0; gTxUpd = 0; gTxDel = 0;
    gInvAdd = 0; gInvUpd = 0; gInvDel = 0;
    gInvPAdd = 0; gInvPUpd = 0; gInvPDel = 0;
    gPdAdd = 0; gPdUpd = 0; gPdDel = 0;
    gPdeAdd = 0; gPdeUpd = 0; gPdeDel = 0;
  }

  void _resetPushCounters() {
    pWhAdd = 0; pWhUpd = 0; pWhDel = 0;
    pTxAdd = 0; pTxUpd = 0; pTxDel = 0;
    pInvAdd = 0; pInvUpd = 0; pInvDel = 0;
    pInvPAdd = 0; pInvPUpd = 0; pInvPDel = 0;
    pPdAdd = 0; pPdUpd = 0; pPdDel = 0;
    pPdeAdd = 0; pPdeUpd = 0; pPdeDel = 0;
  }

  Future<void> _notifyOthers(String uid, List<String> details) async {
    final supabase = Supabase.instance.client;
    final me = await supabase.from('profiles').select('display_name')
        .eq('id', uid).maybeSingle();
    final actorName = (me?['display_name'] as String?) ?? 'مستخدم';
    final others = await supabase.from('profiles').select('id')
        .neq('id', uid).eq('is_active', true);
    final body = details.take(8).join('\n') +
        (details.length > 8 ? '\n+${details.length - 8} تغييرات أخرى' : '');
    for (final o in others) {
      await supabase.from('notifications').insert({
        'recipient_id': o['id'] as String, 'actor_id': uid,
        'actor_name': actorName, 'kind': 'sync_change',
        'title': 'تحديثات جديدة في الدفتر',
        'body': body, 'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}

String _uuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rand = now ^ (DateTime.now().millisecondsSinceEpoch << 16);
  String hex(int n, int len) => n.toRadixString(16).padLeft(len, '0');
  return '${hex((rand >> 48) & 0xFFFF, 4)}${hex((rand >> 32) & 0xFFFF, 4)}-'
      '${hex((rand >> 16) & 0xFFFF, 4)}-'
      '${hex(rand & 0xFFFF, 4)}-'
      '${hex((now >> 16) & 0xFFFF, 4)}-'
      '${hex(now & 0xFFFF, 4)}${hex((now >> 32) & 0xFFFF, 4)}'
      '${hex((now >> 48) & 0xFFFF, 4)}';
}