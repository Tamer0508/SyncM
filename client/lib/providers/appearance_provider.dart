import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/local_store.dart';

class AppearanceProvider extends ChangeNotifier {
  AppearanceProvider() {
    _restore();
  }


  double _textScale = 1.0;
  double get textScale => _textScale;

  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.30;

  void setTextScale(double value) {
    final next = value.clamp(minTextScale, maxTextScale);
    if (next == _textScale) return;
    _textScale = next;
    LocalStore.saveDouble(StoreKeys.textScale, next);
    notifyListeners();
  }


  bool _compact = false;
  bool get compact => _compact;

  VisualDensity get density =>
      _compact ? VisualDensity.compact : VisualDensity.standard;

  void setCompact(bool value) {
    if (value == _compact) return;
    _compact = value;
    LocalStore.saveBool(StoreKeys.compactMode, value);
    notifyListeners();
  }


  AccentColor _accent = AccentColor.olive;
  AccentColor get accent => _accent;

  void setAccent(AccentColor value) {
    if (value == _accent) return;
    _accent = value;
    LocalStore.saveString(StoreKeys.accentColor, value.name);
    notifyListeners();
  }


  bool _reduceMotion = false;
  bool get reduceMotion => _reduceMotion;

  void setReduceMotion(bool value) {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    LocalStore.saveBool(StoreKeys.reduceMotion, value);
    notifyListeners();
  }


  bool _artworkBackground = true;
  bool get artworkBackground => _artworkBackground;

  void setArtworkBackground(bool value) {
    if (value == _artworkBackground) return;
    _artworkBackground = value;
    LocalStore.saveBool(StoreKeys.artworkBackground, value);
    notifyListeners();
  }
  final Map<String, bool> _flags = {};

  bool flag(String key, {bool defaultValue = false}) =>
      _flags[key] ?? LocalStore.readBool(key, defaultValue: defaultValue);

  Future<void> setFlag(String key, bool value) async {
    _flags[key] = value;
    notifyListeners();
    await LocalStore.saveBool(key, value);
  }

  void _restore() {
    _textScale = LocalStore.readDouble(StoreKeys.textScale, defaultValue: 1.0)
        .clamp(minTextScale, maxTextScale);
    _compact = LocalStore.readBool(StoreKeys.compactMode);
    _reduceMotion = LocalStore.readBool(StoreKeys.reduceMotion);
    _artworkBackground =
        LocalStore.readBool(StoreKeys.artworkBackground, defaultValue: true);

    final saved = LocalStore.readString(StoreKeys.accentColor);
    _accent = AccentColor.values.firstWhere(
      (a) => a.name == saved,
      orElse: () => AccentColor.olive,
    );
  }

  /// Возвращает всё к значениям по умолчанию.
  void resetAll() {
    _textScale = 1.0;
    _compact = false;
    _accent = AccentColor.olive;
    _reduceMotion = false;
    _artworkBackground = true;

    LocalStore.saveDouble(StoreKeys.textScale, 1.0);
    LocalStore.saveBool(StoreKeys.compactMode, false);
    LocalStore.saveString(StoreKeys.accentColor, AccentColor.olive.name);
    LocalStore.saveBool(StoreKeys.reduceMotion, false);
    LocalStore.saveBool(StoreKeys.artworkBackground, true);

    notifyListeners();
  }
}