import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  const LocalStore._();

  static SharedPreferences? _prefs;

  /// Готово ли хранилище. Если нет, чтение вернёт null, а запись ничего не
  /// сделает — приложение продолжит работать, просто без ускорения старта.
  static bool get isReady => _prefs != null;

  /// Вызывается один раз в main() до runApp.
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (err) {
      // Хранилище недоступно (редко, но бывает в ограниченных средах).
      // Это не повод не запускать приложение.
      debugPrint('LocalStore init failed, running without local cache: $err');
    }
  }

  static const int maxItems = 50;

  static String _stampKey(String key) => '$key:savedAt';

  /// Сохраняет список объектов.
  static Future<void> saveList(String key, List<Map<String, dynamic>> items) async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final trimmed = items.length > maxItems ? items.sublist(0, maxItems) : items;
      await prefs.setString(key, jsonEncode(trimmed));
      await prefs.setInt(_stampKey(key), DateTime.now().millisecondsSinceEpoch);
    } catch (err) {
      // Данные могут содержать несериализуемое значение (например, DateTime).
      // Это не должно ломать работу — просто останемся без кэша по этому ключу.
      debugPrint('LocalStore.saveList failed for "$key": $err');
    }
  }

  /// Читает сохранённый список. Синхронно — вызывается при построении экрана.
  static List<Map<String, dynamic>> readList(String key) {
    final prefs = _prefs;
    if (prefs == null) return const [];

    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
    } catch (err) {
      debugPrint('LocalStore.readList failed for "$key", dropping: $err');
      unawaited(remove(key));
      return const [];
    }
  }

  static DateTime? savedAt(String key) {
    final ms = _prefs?.getInt(_stampKey(key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static bool isStale(String key, Duration maxAge) {
    final saved = savedAt(key);
    if (saved == null) return true;
    return DateTime.now().difference(saved) > maxAge;
  }

  static Future<void> remove(String key) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.remove(key);
    await prefs.remove(_stampKey(key));
  }

  static Future<void> clearAll() async {
    final prefs = _prefs;
    if (prefs == null) return;

    for (final key in StoreKeys.all) {
      await remove(key);
    }
  }
}

class StoreKeys {
  const StoreKeys._();

  static const friends = 'cache:friends';
  static const friendRequests = 'cache:friend_requests';
  static const sessions = 'cache:sessions';
  static const invites = 'cache:invites';

  static const all = [friends, friendRequests, sessions, invites];
}