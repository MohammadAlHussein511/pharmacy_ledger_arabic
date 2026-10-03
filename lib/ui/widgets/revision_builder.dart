import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ledger_store.dart';

/// Runs [load] and rebuilds whenever the ledger changes or [dependency]
/// changes. Keeps showing previous data while reloading (no flicker).
class RevisionBuilder<T> extends StatefulWidget {
  const RevisionBuilder({
    super.key,
    required this.load,
    required this.builder,
    this.dependency,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? dependency;

  @override
  State<RevisionBuilder<T>> createState() => _RevisionBuilderState<T>();
}

class _RevisionBuilderState<T> extends State<RevisionBuilder<T>> {
  int _revision = -1;
  Object? _dependency;
  Future<T>? _future;
  T? _last;
  bool _hasLast = false;

  @override
  Widget build(BuildContext context) {
    final rev = context.watch<LedgerStore>().revision;
    if (_future == null || rev != _revision || widget.dependency != _dependency) {
      _revision = rev;
      if (widget.dependency != _dependency) _hasLast = false;
      _dependency = widget.dependency;
      _future = widget.load();
    }
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('Could not load data. Please try again.', textAlign: TextAlign.center),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.done && snap.hasData) {
          _last = snap.data;
          _hasLast = true;
          return widget.builder(context, snap.data as T);
        }
        if (_hasLast) return widget.builder(context, _last as T);
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
