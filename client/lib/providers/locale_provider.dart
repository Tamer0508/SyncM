import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../utils/local_store.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    _restore();
  }

  static const List<String> supported = ['ru', 'en'];

  String _language = 'system';
  String get language => _language;

  Locale? get locale => _language == 'system' ? null : Locale(_language);

  void setLanguage(String value) {
    final next = (value == 'system' || supported.contains(value)) ? value : 'system';
    if (next == _language) return;

    _language = next;
    LocalStore.saveString(StoreKeys.language, next);
    notifyListeners();
  }

  void _restore() {
    final saved = LocalStore.readString(StoreKeys.language);
    if (saved == null) return;
    if (saved != 'system' && !supported.contains(saved)) return;
    _language = saved;
  }
}
