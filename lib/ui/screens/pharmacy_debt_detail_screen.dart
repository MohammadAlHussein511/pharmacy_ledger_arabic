import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';
import 'debt_entry_form_screen.dart';

class PharmacyDebtDetailScreen extends StatefulWidget {
  const PharmacyDebtDetailScreen({super.key, required this.pharmacyId});
  final int pharmacyId;

  @override
  State<PharmacyDebtDetailScreen> createState() =>
      _PharmacyDebtDetailScreenState();
}

class _Entry {
  _Entry({
    required this.id,
    required this.direction,
    required this.item,
    required this.date,
    required this.time,
    required this.settled,
    required this.settledAt,
    required this.raw,
  });
  final int id;
  final String direction;
  final String item;
  final String date;
  final String time;
  final int settled;
  final String? settledAt;
  final Map<String, Object?> raw;
}

class _PharmacyDebtDetailScreenState extends State<PharmacyDebtDetailScreen> {
  String? _pharmacyName;
  List<_Entry> _entries = [];
  bool _loading = true;
  String _filter = 'active'; // 'all' | 'active' | 'settled'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = context.read<AppServices>();
      final db = services.db;

      final phs = await db.query('pharmacy_debts',
          where: 'id = ?', whereArgs: [widget.pharmacyId]);
      if (phs.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final entries = await db.query('pharmacy_debt_entries',
          where: 'pharmacy_id = ?',
          whereArgs: [widget.pharmacyId],
          orderBy: 'entry_date DESC, entry_time DESC, id DESC');

      if (!mounted) return;
      setState(() {
        _pharmacyName = phs.first['name'] as String;
        _entries = [
          for (final e in entries)
            _Entry(
              id: e['id'] as int,
              direction: e['direction'] as String,
              item: (e['note'] as String?) ?? '—',
              date: e['entry_date'] as String,
              time: e['entry_time'] as String,
              settled: (e['settled'] as int?) ?? 0,
              settledAt: e['settled_at'] as String?,
              raw: e.cast<String, Object?>(),
            ),
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _toUs => _entries.where((e) => e.direction == 'OWED_TO_US' && e.settled == 0).length;
  int get _byUs => _entries.where((e) => e.direction == 'OWED_BY_US' && e.settled == 0).length;
  int get _settledCount => _entries.where((e) => e.settled == 1).length;

  List<_Entry> get _filtered {
    if (_filter == 'active') return _entries.where((e) => e.settled == 0).toList();
    if (_filter == 'settled') return _entries.where((e) => e.settled == 1).toList();
    return _entries;
  }

  Future<void> _toggleSettle(_Entry e) async {
    final services = context.read<AppServices>();
    final now = DateTime.now().toIso8601String();
    final newSettled = e.settled == 0 ? 1 : 0;
    await services.db.update(
      'pharmacy_debt_entries',
      {
        'settled': newSettled,
        'settled_at': newSettled == 1 ? now : null,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [e.id],
    );
    services.store.changed();
    _load();
  }

  Future<void> _editEntry(_Entry e) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              DebtEntryFormScreen(pharmacyId: widget.pharmacyId, existing: e.raw)),
    );
    if (result == true && mounted) _load();
  }

  Future<void> _deleteEntry(_Entry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحركة؟'),
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
    await services.db.delete('pharmacy_debt_entries',
        where: 'id = ?', whereArgs: [e.id]);
    services.store.changed();
    _load();
  }

  Future<void> _deletePharmacy() async {
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
    await services.db.transaction((txn) async {
      await txn.delete('pharmacy_debt_entries',
          where: 'pharmacy_id = ?', whereArgs: [widget.pharmacyId]);
      await txn.delete('pharmacy_debts',
          where: 'id = ?', whereArgs: [widget.pharmacyId]);
    });
    services.store.changed();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (_pharmacyName == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('لم تعد موجودة')));
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pharmacyName!),
        actions: [
          IconButton(
              tooltip: 'حذف الصيدلية',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deletePharmacy),
        ],
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
                      Text('لنا عندهم (غير مسدّدة)',
                          style: t.bodySmall?.copyWith(color: Colors.green.shade700)),
                      const SizedBox(height: 4),
                      Text('$_toUs صنف',
                          style: t.titleMedium?.copyWith(color: Colors.green.shade900)),
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
                      Text('علينا لهم (غير مسدّدة)',
                          style: t.bodySmall?.copyWith(color: Colors.red.shade700)),
                      const SizedBox(height: 4),
                      Text('$_byUs صنف',
                          style: t.titleMedium?.copyWith(color: Colors.red.shade900)),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'active', label: Text('نشطة')),
                ButtonSegment(value: 'settled', label: Text('مسدّدة')),
                ButtonSegment(value: 'all', label: Text('الكل')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('السجل (${_filtered.length})', style: t.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => DebtEntryFormScreen(pharmacyId: widget.pharmacyId)),
                  );
                  _load();
                },
                icon: const Icon(Icons.add),
                label: const Text('حركة'),
              ),
            ]),
            const SizedBox(height: 8),
            if (_filtered.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(_filter == 'settled'
                        ? 'لا توجد حركات مسدّدة'
                        : 'لا توجد حركات',
                        style: t.bodyLarge),
                  ),
                ),
              )
            else
              ..._filtered.map((e) {
                final isToUs = e.direction == 'OWED_TO_US';
                final isSettled = e.settled == 1;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: isSettled
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isToUs ? Colors.green.shade50 : Colors.red.shade50,
                      child: Icon(
                        isSettled ? Icons.check_circle_outline : (isToUs ? Icons.arrow_downward : Icons.arrow_upward),
                        color: isToUs ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(
                      e.item,
                      style: isSettled
                          ? const TextStyle(decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${isToUs ? 'لنا عندهم' : 'علينا لهم'} · ${e.date} ${e.time}',
                          style: isSettled
                              ? TextStyle(color: Theme.of(context).colorScheme.outline)
                              : null,
                        ),
                        if (isSettled && e.settledAt != null)
                          Text(
                            '✓ سُدّدت في ${e.settledAt!.substring(0, 16)}',
                            style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 11,
                                fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: isSettled ? 'إلغاء التسديد' : 'تسديد',
                          icon: Icon(
                            isSettled ? Icons.undo : Icons.check,
                            size: 20,
                            color: isSettled ? Colors.orange : Colors.green,
                          ),
                          onPressed: () => _toggleSettle(e),
                        ),
                        IconButton(
                            tooltip: 'تعديل',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _editEntry(e)),
                        IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _deleteEntry(e)),
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