import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ledger_store.dart';
import '../../data/models/ledger_transaction.dart';
import 'common.dart';
import 'transaction_widgets.dart';

typedef PageLoader = Future<List<LedgerTransaction>> Function(int limit, int offset);

/// Lazily loads transactions in pages of [pageSize] (never the whole table).
/// Reloads from the first page whenever the ledger changes.
class PagedTransactionList extends StatefulWidget {
  const PagedTransactionList({
    super.key,
    required this.loader,
    required this.dependency,
    this.pageSize = 50,
    this.emptyMessage = 'No payments recorded for this period.',
  });

  final PageLoader loader;
  final Object dependency;
  final int pageSize;
  final String emptyMessage;

  @override
  State<PagedTransactionList> createState() => _PagedTransactionListState();
}

class _PagedTransactionListState extends State<PagedTransactionList> {
  final List<LedgerTransaction> _items = [];
  bool _loading = false;
  bool _done = false;
  int _revision = -1;
  Object? _dependency;
  int _generation = 0;

  Future<void> _reset() async {
    _generation++;
    _items.clear();
    _done = false;
    _loading = false;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await widget.loader(widget.pageSize, _items.length);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page);
        _done = page.length < widget.pageSize;
      });
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rev = context.watch<LedgerStore>().revision;
    if (rev != _revision || widget.dependency != _dependency) {
      _revision = rev;
      _dependency = widget.dependency;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reset();
      });
    }
    if (_items.isEmpty && _done) {
      return EmptyState(message: widget.emptyMessage, icon: Icons.search_off);
    }
    return Column(
      children: [
        for (final tx in _items) TransactionTile(tx: tx, showDate: true),
        if (_loading)
          const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
        else if (!_done)
          TextButton(onPressed: _loadMore, child: const Text('Load more')),
      ],
    );
  }
}
