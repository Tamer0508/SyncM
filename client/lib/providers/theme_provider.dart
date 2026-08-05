import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../utils/local_store.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _restore();
  }

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDark {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
  }

  void _restore() {
    final saved = LocalStore.readString(StoreKeys.themeMode);
    if (saved == null) return;

    _themeMode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _persist();
    notifyListeners();
  }

  void toggleTheme() {
    setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  void _persist() {
    LocalStore.saveString(StoreKeys.themeMode, _themeMode.name);
  }
}