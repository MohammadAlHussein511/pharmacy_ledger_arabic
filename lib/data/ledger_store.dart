import 'package:flutter/foundation.dart';

/// Bumped after every successful write. Screens listen to it and re-run
/// their (cheap, indexed) aggregate queries, so every total on screen is
/// always derived from the current transaction records.
class LedgerStore extends ChangeNotifier {
  int _revision = 0;
  int get revision => _revision;

  void changed() {
    _revision++;
    notifyListeners();
  }
}
