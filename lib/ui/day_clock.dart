import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/dates.dart';

/// Notifies when the local calendar day changes (midnight, or when the app
/// resumes on a new day), so "Today", "This Week" etc. roll over correctly.
class DayClock extends ChangeNotifier with WidgetsBindingObserver {
  DayClock() {
    _today = Dates.dateOnly(DateTime.now());
    _schedule();
    WidgetsBinding.instance.addObserver(this);
  }

  late DateTime _today;
  Timer? _timer;

  DateTime get today => _today;

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), _check);
  }

  void _check() {
    final t = Dates.dateOnly(DateTime.now());
    if (t != _today) {
      _today = t;
      notifyListeners();
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
