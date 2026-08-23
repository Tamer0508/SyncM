import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальное хранилище последних загруженных данных.
///
/// Решает то, ради чего всё и затевалось: при холодном старте список друзей и
/// сессий рисуется мгновенно из сохранённой копии, а сеть лишь обновляет его
/// в фоне. Без этого слоя каждый запуск начинался с пустого экрана и
/// скелетонов, сколько бы мы ни грели данные в памяти — память умирает
/// вместе с процессом.
///
/// Хранилище синхронное после init(): SharedPreferences подгружается один раз
/// при старте приложения, дальше чтение идёт из памяти. Это принципиально —
/// асинхронное чтение при построении первого кадра означало бы тот самый
/// пустой экран, от которого мы уходим.
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

  /// Сколько записей списка сохранять.
  ///
  /// Смысл кэша — мгновенно показать первый экран, а не хранить всё. Список
  /// на пару сотен позиций сериализуется заметно дольше, чем рисуется, и
  /// упирается в ограничение размера у SharedPreferences.
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
      // Повреждённая или устаревшая по формату запись: чистим, чтобы не
      // спотыкаться о неё при каждом запуске.
      debugPrint('LocalStore.readList failed for "$key", dropping: $err');
      unawaited(remove(key));
      return const [];
    }
  }

  /// Когда данные были сохранены. null, если записи нет.
  static DateTime? savedAt(String key) {
    final ms = _prefs?.getInt(_stampKey(key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Насколько данные устарели. Экраны могут по этому признаку решить,
  /// показывать ли сохранённое или сразу скелетон.
  static bool isStale(String key, Duration maxAge) {
    final saved = savedAt(key);
    if (saved == null) return true;
    return DateTime.now().difference(saved) > maxAge;
  }

  /// Сохраняет объект (снимок профиля, карту цветов обложек и подобное).
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

  /// Сохраняет одиночную строку — для настроек вроде выбранной темы.
  static Future<void> saveString(String key, String value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(key, value);
  }

  /// Читает строку. Синхронно: настройки нужны при построении первого кадра,
  /// иначе приложение мигнёт чужой темой перед применением сохранённой.
  static String? readString(String key) => _prefs?.getString(key);

  /// Читает булеву настройку. По умолчанию — значение defaultValue.
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

  /// Очищает весь кэш данных. Вызывается при выходе из аккаунта: иначе
  /// следующий вошедший увидит на первом кадре чужих друзей и чужие сессии.
  static Future<void> clearAll() async {
    final prefs = _prefs;
    if (prefs == null) return;

    for (final key in StoreKeys.all) {
      await remove(key);
    }
  }
}

/// Ключи хранилища в одном месте — чтобы очистка при выходе не забыла ни один.
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

  /// Выбранная тема. Намеренно НЕ входит в all: настройка принадлежит
  /// устройству, а не аккаунту, и при выходе из профиля сбрасывать её
  /// незачем — человек не ожидает, что выход поменяет оформление.
  static const themeMode = 'settings:theme_mode';

  /// Показывать ли подтверждение перед завершением сессии.
  static const confirmEndSession = 'settings:confirm_end_session';

  /// Открывать полноэкранный плеер при запуске трека.
  static const autoOpenPlayer = 'settings:auto_open_player';

  /// Держать экран включённым во время сессии.
  static const keepScreenOn = 'settings:keep_screen_on';

  /// Прогревать данные при запуске приложения.
  static const prefetchOnStart = 'settings:prefetch_on_start';

  /// Показывать уведомление о приглашении в сессию.
  static const inviteNotifications = 'settings:invite_notifications';

  static const textScale = 'settings:text_scale';
  static const compactMode = 'settings:compact_mode';
  static const accentColor = 'settings:accent_color';
  static const reduceMotion = 'settings:reduce_motion';
  static const artworkBackground = 'settings:artwork_background';

  static const railWidth = 'settings:rail_width';

  /// Язык интерфейса: system, ru или en. Как и тема, принадлежит устройству
  /// и переживает выход из аккаунта.
  static const language = 'settings:language';

  /// Когда настройки последний раз меняли на этом устройстве. По этой отметке
  /// решается спор с сервером: чья версия новее, та и остаётся.
  static const settingsUpdatedAt = 'settings:updated_at';

  /// Копия серверных настроек уведомлений. Нужна на старте: всплывающая
  /// карточка может прийти раньше, чем ответ сервера с настройками.
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