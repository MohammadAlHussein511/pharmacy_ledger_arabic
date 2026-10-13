import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services.dart';
import 'pharmacy_debt_detail_screen.dart';
import 'pharmacy_debt_form_screen.dart';

class PharmacyDebtsScreen extends StatefulWidget {
  const PharmacyDebtsScreen({super.key});

  @override
  State<PharmacyDebtsScreen> createState() => _PharmacyDebtsScreenState();
}

class _PhRow {
  _PhRow({required this.id, required this.name});

  final int id;
  final String name;
  int toUs = 0;
  int byUs = 0;
}

class _PharmacyDebtsScreenState extends State<PharmacyDebtsScreen> {
  List<_PhRow> _rows = [];
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
      
      // إضافة حقل settled_at إذا لم يكن موجوداً
      try {
        await services.db.execute('ALTER TABLE pharmacy_debt_entries ADD COLUMN settled_at TEXT');
      } catch (e) {
        // الحقل موجود مسبقاً
      }

      final bytes = await services.backup.createBackup();
      final env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = env['data'] as Map<String, dynamic>;
      final phs = (data['pharmacy_debts'] as List? ?? []).cast<Map<String, dynamic>>();
      final entries = (data['pharmacy_debt_entries'] as List? ?? []).cast<Map<String, dynamic>>();

      final map = <int, _PhRow>{};
      for (final p in phs) {
        map[p['id'] as int] = _PhRow(id: p['id'] as int, name: p['name'] as String);
      }

      for (final e in entries) {
        // استثناء الحركات المسددة
        final settledAt = e['settled_at'] as String?;
        if (settledAt != null) continue;

        final ph = map[e['pharmacy_id'] as int];
        if (ph == null) continue;
        if (e['direction'] == 'OWED_TO_US') {
          ph.toUs++;
        } else {
          ph.byUs++;
        }
      }

      final list = map.values.toList()..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _totalToUs => _rows.fold(0, (s, r) => s + r.toUs);
  int get _totalByUs => _rows.fold(0, (s, r) => s + r.byUs);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('لنا عند الصيدليات',
                                  style: t.bodySmall?.copyWith(color: Colors.green.shade700)),
                              const SizedBox(height: 4),
                              Text('$_totalToUs صنف',
                                  style: t.titleMedium?.copyWith(color: Colors.green.shade900)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('علينا للصيدليات',
                                  style: t.bodySmall?.copyWith(color: Colors.red.shade700)),
                              const SizedBox(height: 4),
                              Text('$_totalByUs صنف',
                                  style: t.titleMedium?.copyWith(color: Colors.red.shade900)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('${_rows.length} صيدلية', style: t.bodySmall),
                  const SizedBox(height: 8),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('لا توجد صيدليات مسجلة')),
                    )
                  else
                    ..._rows.map((r) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.local_pharmacy_outlined)),
                            title: Text(r.name),
                            subtitle: Text('لنا: ${r.toUs} صنف · علينا: ${r.byUs} صنف'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => PharmacyDebtDetailScreen(pharmacyId: r.id)),
                              );
                              _load();
                            },
                          ),
                        )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PharmacyDebtFormScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('صيدلية جديدة'),
      ),
    );
  }
}