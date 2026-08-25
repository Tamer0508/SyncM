import 'package:flutter/foundation.dart';
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
  int _startTab = 0;
  int get startTab => _startTab;

  void setStartTab(int value) {
    final next = value.clamp(0, 2);
    if (next == _startTab) return;
    _startTab = next;
    LocalStore.saveDouble(StoreKeys.startTab, next.toDouble());
    notifyListeners();
  }

  final Map<String, ValueNotifier<bool>> _flags = {};

  /// Текущее значение флага.
  bool flag(String key, {bool defaultValue = false}) =>
      _flagOf(key, defaultValue).value;

  ValueListenable<bool> flagListenable(
    String key, {
    bool defaultValue = false,
  }) =>
      _flagOf(key, defaultValue);

  ValueNotifier<bool> _flagOf(String key, bool defaultValue) =>
      _flags.putIfAbsent(
        key,
        () => ValueNotifier(
          LocalStore.readBool(key, defaultValue: defaultValue),
        ),
      );

  Future<void> setFlag(String key, bool value) async {
    // defaultValue здесь не важен: значение задаётся явно следующей строкой.
    _flagOf(key, value).value = value;
    await LocalStore.saveBool(key, value);
  }

  @override
  void dispose() {
    for (final notifier in _flags.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _restore() {
    _textScale = LocalStore.readDouble(StoreKeys.textScale, defaultValue: 1.0)
        .clamp(minTextScale, maxTextScale);
    _compact = LocalStore.readBool(StoreKeys.compactMode);
    _reduceMotion = LocalStore.readBool(StoreKeys.reduceMotion);
    _artworkBackground =
        LocalStore.readBool(StoreKeys.artworkBackground, defaultValue: true);

    _startTab = LocalStore.readDouble(StoreKeys.startTab, defaultValue: 0)
        .round()
        .clamp(0, 2);

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
    _startTab = 0;

    LocalStore.saveDouble(StoreKeys.startTab, 0);
    LocalStore.saveDouble(StoreKeys.textScale, 1.0);
    LocalStore.saveBool(StoreKeys.compactMode, false);
    LocalStore.saveString(StoreKeys.accentColor, AccentColor.olive.name);
    LocalStore.saveBool(StoreKeys.reduceMotion, false);
    LocalStore.saveBool(StoreKeys.artworkBackground, true);

    notifyListeners();
  }
}