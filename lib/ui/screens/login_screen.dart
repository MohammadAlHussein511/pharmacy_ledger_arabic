import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await _supabase
          .from('notifications')
          .select('*')
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
      final unreadIds = _items
          .where((e) => e['is_read'] == false)
          .map((e) => e['id'])
          .toList();
      if (unreadIds.isNotEmpty) {
        await _supabase
            .from('notifications')
            .update({'is_read': true})
            .inFilter('id', unreadIds);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    return 'قبل ${diff.inDays} يوم';
  }

  IconData _iconForKind(String? kind) => switch (kind) {
        'transaction_created' => Icons.receipt_long,
        'transaction_updated' => Icons.edit_note,
        'transaction_deleted' => Icons.delete_outline,
        'warehouse_created' => Icons.warehouse,
        'sync_change' => Icons.cloud_sync,
        _ => Icons.notifications_outlined,
      };

  void _showDetail(Map<String, dynamic> n, String actorName) {
    final t = Theme.of(context).textTheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_iconForKind(n['kind'] as String?), size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(n['title'] as String)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('بواسطة: $actorName', style: t.bodyMedium),
            Text('الوقت: ${_formatTime(n['created_at'] as String)}',
                style: t.bodyMedium),
            const Divider(height: 20),
            SingleChildScrollView(
              child: Text(
                n['body'] as String,
                style: t.bodyLarge?.copyWith(height: 1.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('لا توجد إشعارات حتى الآن', style: t.titleMedium),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      final name = n['actor_name'] as String? ?? '';
                      final actorName = name.isEmpty ? 'مستخدم' : name;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_iconForKind(n['kind'] as String?)),
                        ),
                        title: Text(n['title'] as String),
                        subtitle: Text(
                          '$actorName · ${_formatTime(n['created_at'] as String)}\n'
                          '${n['body'] as String}',
                        ),
                        isThreeLine: true,
                        onTap: () => _showDetail(n, actorName),
                      );
                    },
                  ),
                ),
    );
  }
}