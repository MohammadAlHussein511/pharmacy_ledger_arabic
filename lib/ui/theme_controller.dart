import 'package:flutter/material.dart';

import '../data/repositories/settings_repository.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._settings) : _mode = _settings.themeMode;

  final SettingsRepository _settings;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    await _settings.setThemeMode(m);
  }
}
