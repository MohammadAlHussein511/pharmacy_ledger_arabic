import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';
import 'debt_entry_form_screen.dart';

class PharmacyDebtDetailScreen extends StatefulWidget {
  const PharmacyDebtDetailScreen({super.key, required this.pharmacyId});
  final int pharmacyId;

  @override
  State<PharmacyDebtDetailScreen> createState() => _PharmacyDebtDetailScreenState();
}

class _Entry {
  _Entry({
    required this.id,
    required this.direction,
    required this.item,
    required this.date,
    required this.time,
    required this.raw,
  });
  final int id;
  final String direction;
  final String item;
  final String date;
  final String time;
  final Map<String, Object?> raw;
}

class _PharmacyDebtDetailScreenState extends State<PharmacyDebtDetailScreen> {
  String? _pharmacyName;
  List<_Entry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = context.read<AppServices>();
      final bytes = await services.backup.createBackup();
      final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = env['data'] as Map<String, dynamic>;
      final phs = (data['pharmacy_debts'] as List? ?? []).cast<Map<String, dynamic>>();
      final entries = (data['pharmacy_debt_entries'] as List? ?? []).cast<Map<String, dynamic>>();

      final ph = phs.firstWhere((p) => p['id'] == widget.pharmacyId, orElse: () => <String, Object?>{});
      if (ph.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final myEntries = entries
          .where((e) => e['pharmacy_id'] == widget.pharmacyId)
          .map((e) => _Entry(
                id: e['id'] as int,
                direction: e['direction'] as String,
                item: (e['note'] as String?) ?? '—',
                date: e['entry_date'] as String,
                time: e['entry_time'] as String,
                raw: e.cast<String, Object?>(),
              ))
          .toList()
        ..sort((a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'));

      if (!mounted) return;
      setState(() {
        _pharmacyName = ph['name'] as String;
        _entries = myEntries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _toUs => _entries.where((e) => e.direction == 'OWED_TO_US').length;
  int get _byUs => _entries.where((e) => e.direction == 'OWED_BY_US').length;

  Future<void> _editEntry(_Entry e) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DebtEntryFormScreen(pharmacyId: widget.pharmacyId, existing: e.raw)),
    );
    if (result == true) _load();
  }

  Future<void> _deleteEntry(_Entry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحركة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final services = context.read<AppServices>();
    await services.db.delete('pharmacy_debt_entries', where: 'id = ?', whereArgs: [e.id]);
    services.store.changed();
    _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصيدلية؟'),
        content: const Text('سيتم حذف الصيدلية وكل حركاتها نهائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final services = context.read<AppServices>();
    await services.db.delete('pharmacy_debt_entries', where: 'pharmacy_id = ?', whereArgs: [widget.pharmacyId]);
    await services.db.delete('pharmacy_debts', where: 'id = ?', whereArgs: [widget.pharmacyId]);
    services.store.changed();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (_pharmacyName == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('لم تعد موجودة')));
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pharmacyName!),
        actions: [IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('لنا عندهم', style: t.bodySmall?.copyWith(color: Colors.green.shade700)),
                      const SizedBox(height: 4),
                      Text('$_toUs صنف', style: t.titleMedium?.copyWith(color: Colors.green.shade900)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('علينا لهم', style: t.bodySmall?.copyWith(color: Colors.red.shade700)),
                      const SizedBox(height: 4),
                      Text('$_byUs صنف', style: t.titleMedium?.copyWith(color: Colors.red.shade900)),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Text('سجل الحركات (${_entries.length})', style: t.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DebtEntryFormScreen(pharmacyId: widget.pharmacyId)),
                  );
                  _load();
                },
                icon: const Icon(Icons.add),
                label: const Text('حركة'),
              ),
            ]),
            const SizedBox(height: 8),
            if (_entries.isEmpty)
              const Card(child: ListTile(title: Text('لا توجد حركات بعد')))
            else
              ..._entries.map((e) {
                final isToUs = e.direction == 'OWED_TO_US';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isToUs ? Colors.green.shade50 : Colors.red.shade50,
                      child: Icon(isToUs ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isToUs ? Colors.green : Colors.red),
                    ),
                    title: Text(e.item),
                    subtitle: Text('${isToUs ? 'لنا عندهم' : 'علينا لهم'} · ${e.date} ${e.time}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editEntry(e)),
                        IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _deleteEntry(e)),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}