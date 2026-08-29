import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  const LocalStore._();

  static SharedPreferences? _prefs;

  static bool get isReady => _prefs != null;

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (err) {
      debugPrint('LocalStore init failed, running without local cache: $err');
    }
  }

  static const int maxItems = 50;

  static String _stampKey(String key) => '$key:savedAt';

  static Future<void> saveList(String key, List<Map<String, dynamic>> items) async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final trimmed = items.length > maxItems ? items.sublist(0, maxItems) : items;
      await prefs.setString(key, jsonEncode(trimmed));
      await prefs.setInt(_stampKey(key), DateTime.now().millisecondsSinceEpoch);
    } catch (err) {
      debugPrint('LocalStore.saveList failed for "$key": $err');
    }
  }

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

  static Future<void> saveMap(String key, Map<String, dynamic> value) async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      await prefs.setString(key, jsonEncode(value));
      await prefs.setInt(_stampKey(key), DateTime.now().millisecondsSinceEpoch);
    } catch (err) {
      debugPrint('LocalStore.saveMap failed for "$key": $err');
    }
  }

  static Map<String, dynamic>? readMap(String key) {
    final prefs = _prefs;
    if (prefs == null) return null;

    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (err) {
      debugPrint('LocalStore.readMap failed for "$key", dropping: $err');
      unawaited(remove(key));
      return null;
    }
  }

  static Future<void> saveString(String key, String value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(key, value);
  }

  static String? readString(String key) => _prefs?.getString(key);

  static bool readBool(String key, {bool defaultValue = false}) =>
      _prefs?.getBool(key) ?? defaultValue;

  static Future<void> saveBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  static double readDouble(String key, {double defaultValue = 0}) =>
      _prefs?.getDouble(key) ?? defaultValue;

  static Future<void> saveDouble(String key, double value) async {
    await _prefs?.setDouble(key, value);
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

  static const me = 'cache:me';

  static const customPlaylists = 'cache:playlists:custom';
  static const spotifyPlaylists = 'cache:playlists:spotify';

  static const profiles = 'cache:profiles';

  static const themeMode = 'settings:theme_mode';

  static const confirmEndSession = 'settings:confirm_end_session';

  static const autoOpenPlayer = 'settings:auto_open_player';

  static const keepScreenOn = 'settings:keep_screen_on';

  static const prefetchOnStart = 'settings:prefetch_on_start';

  static const inviteNotifications = 'settings:invite_notifications';

  static const textScale = 'settings:text_scale';
  static const compactMode = 'settings:compact_mode';
  static const accentColor = 'settings:accent_color';
  static const reduceMotion = 'settings:reduce_motion';
  static const artworkBackground = 'settings:artwork_background';

  static const railWidth = 'settings:rail_width';

  static const language = 'settings:language';

  static const settingsUpdatedAt = 'settings:updated_at';

  static const notificationPrefs = 'settings:notifications';

  static const startTab = 'settings:start_tab';

  static const artworkColors = 'cache:artwork_colors';

  static const all = [
    friends,
    friendRequests,
    sessions,
    invites,
    me,
    customPlaylists,
    spotifyPlaylists,
    profiles,
  ];
}