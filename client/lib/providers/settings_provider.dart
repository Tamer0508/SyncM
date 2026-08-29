import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../services/api_service.dart';
import '../theme.dart';
import '../utils/local_store.dart';
import 'appearance_provider.dart';
import 'auth_provider.dart';
import 'locale_provider.dart';
import 'theme_provider.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required this.appearance,
    required this.theme,
    required this.localeProvider,
  }) {
    _restoreCache();
    appearance.addListener(_onLocalChanged);
    theme.addListener(_onLocalChanged);
    localeProvider.addListener(_onLocalChanged);
  }

  final AppearanceProvider appearance;
  final ThemeProvider theme;
  final LocaleProvider localeProvider;

  static const Duration _pushDelay = Duration(milliseconds: 700);

  ApiService? _api;
  String? _userId;

  Timer? _pushTimer;

  bool _applying = false;

  Map<String, dynamic>? _lastPushedAppearance;

  bool _loading = false;
  bool get loading => _loading;

  Map<String, bool> _notifications = Map.of(NotificationPrefs.defaults);
  Map<String, bool> get notifications => Map.unmodifiable(_notifications);

  String _inviteScope = 'friends';

  String get inviteScope => _inviteScope;

  bool notification(String key) =>
      _notifications[key] ?? NotificationPrefs.defaults[key] ?? true;

  void syncAuth(AuthProvider auth) {
    final user = auth.user;

    if (user == null) {
      if (_userId == null) return;
      _reset();
      return;
    }

    _api = auth.api;
    _api?.language = _effectiveLanguage;

    if (_userId == user.id) return;
    _userId = user.id;
    unawaited(load());
  }

  Future<void> load({bool refresh = true}) async {
    final api = _api;
    if (api == null) return;

    _loading = true;
    notifyListeners();

    try {
      final settings = await api.getUserSettings(refresh: refresh);
      _applyServerSettings(settings);
    } catch (err) {
      debugPrint('Не удалось загрузить настройки: $err');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _applyServerSettings(Map<String, dynamic> settings) {
    final scope = settings['allowSessionInvites'];
    if (scope is String) _inviteScope = scope;

    final prefs = settings['preferences'];
    if (prefs is! Map) return;

    final remoteNotifications = prefs['notifications'];
    if (remoteNotifications is Map) {
      _notifications = {
        ...NotificationPrefs.defaults,
        for (final entry in remoteNotifications.entries)
          if (entry.value is bool) entry.key.toString(): entry.value as bool,
      };
      NotificationPrefs.remember(_notifications);
    }

    final serverUpdatedAt = (prefs['updatedAt'] as num?)?.toInt() ?? 0;
    final localUpdatedAt =
        LocalStore.readDouble(StoreKeys.settingsUpdatedAt).toInt();

    if (serverUpdatedAt == 0 && localUpdatedAt == 0) {
      unawaited(_seedFromLocal());
      return;
    }

    if (serverUpdatedAt > localUpdatedAt) {
      _applying = true;
      try {
        final remoteAppearance = prefs['appearance'];
        if (remoteAppearance is Map) {
          _applyAppearance(Map<String, dynamic>.from(remoteAppearance));
        }

        final language = prefs['language'];
        if (language is String) localeProvider.setLanguage(language);
      } finally {
        _applying = false;
      }

      LocalStore.saveDouble(
          StoreKeys.settingsUpdatedAt, serverUpdatedAt.toDouble());
      _lastPushedAppearance = _localPreferences();
      return;
    }

    if (localUpdatedAt > serverUpdatedAt) {
      unawaited(_push(_localPreferences(), localUpdatedAt));
    } else {
      _lastPushedAppearance = _localPreferences();
    }
  }

  Future<void> _seedFromLocal() async {
    final legacyInvites =
        LocalStore.readBool(StoreKeys.inviteNotifications, defaultValue: true);

    if (!legacyInvites) {
      _notifications = {..._notifications, 'sessionInvites': false};
      NotificationPrefs.remember(_notifications);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    unawaited(LocalStore.saveDouble(StoreKeys.settingsUpdatedAt, now.toDouble()));

    await _push(
      _localPreferences(),
      now,
      notifications: legacyInvites ? null : {'sessionInvites': false},
    );
  }

  Map<String, dynamic> _localPreferences() => {
        'appearance': _localAppearance(),
        'language': localeProvider.language,
      };

  String get _effectiveLanguage {
    final language = localeProvider.language;
    if (language != 'system') return language;

    final system = PlatformDispatcher.instance.locale.languageCode;
    return LocaleProvider.supported.contains(system) ? system : 'ru';
  }

  Map<String, dynamic> _localAppearance() => {
        'themeMode': theme.themeMode.name,
        'accent': appearance.accent.name,
        'textScale': appearance.textScale,
        'compact': appearance.compact,
        'reduceMotion': appearance.reduceMotion,
        'artworkBackground': appearance.artworkBackground,
        'startTab': appearance.startTab,
      };

  void _applyAppearance(Map<String, dynamic> data) {
    {
      final mode = switch (data['themeMode']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
      if (mode != null) theme.setThemeMode(mode);

      final accentName = data['accent'];
      if (accentName is String) {
        final accent = AccentColor.values
            .where((a) => a.name == accentName)
            .firstOrNull;
        if (accent != null) appearance.setAccent(accent);
      }

      final scale = data['textScale'];
      if (scale is num) appearance.setTextScale(scale.toDouble());

      final compact = data['compact'];
      if (compact is bool) appearance.setCompact(compact);

      final reduceMotion = data['reduceMotion'];
      if (reduceMotion is bool) appearance.setReduceMotion(reduceMotion);

      final artwork = data['artworkBackground'];
      if (artwork is bool) appearance.setArtworkBackground(artwork);

      final startTab = data['startTab'];
      if (startTab is num) appearance.setStartTab(startTab.toInt());
    }
  }

  void _onLocalChanged() {
    _api?.language = _effectiveLanguage;

    if (_applying || _api == null) return;

    final next = _localPreferences();
    if (mapEquals(next, _lastPushedAppearance)) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    LocalStore.saveDouble(StoreKeys.settingsUpdatedAt, now.toDouble());

    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, () => unawaited(_push(next, now)));
  }

  Future<void> _push(
    Map<String, dynamic> preferences,
    int updatedAt, {
    Map<String, bool>? notifications,
  }) async {
    final api = _api;
    if (api == null) return;

    try {
      await api.patchUserSettings({
        'preferences': {
          ...preferences,
          if (notifications != null) 'notifications': notifications,
          'updatedAt': updatedAt,
        },
      });
      _lastPushedAppearance = preferences;
    } catch (err) {
      debugPrint('Не удалось отправить настройки на сервер: $err');
    }
  }

  Future<void> setNotification(String key, bool value) async {
    final api = _api;
    if (api == null) return;

    final previous = Map.of(_notifications);
    _notifications = {..._notifications, key: value};
    NotificationPrefs.remember(_notifications);
    notifyListeners();

    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final result = await api.patchUserSettings({
        'preferences': {
          'notifications': {key: value},
          'updatedAt': now,
        },
      });
      _applyServerSettings(result);
    } catch (err) {
      _notifications = previous;
      NotificationPrefs.remember(_notifications);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setInviteScope(String scope) async {
    final api = _api;
    if (api == null) return;

    final previous = _inviteScope;
    _inviteScope = scope;
    notifyListeners();

    try {
      await api.patchUserSettings({'allowSessionInvites': scope});
    } catch (err) {
      _inviteScope = previous;
      notifyListeners();
      rethrow;
    }
  }

  void _restoreCache() {
    _notifications = NotificationPrefs.restore();
  }

  void _reset() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _userId = null;
    _api = null;
    _lastPushedAppearance = null;
    _inviteScope = 'friends';
    _notifications = Map.of(NotificationPrefs.defaults);
    NotificationPrefs.remember(_notifications);
    notifyListeners();
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    appearance.removeListener(_onLocalChanged);
    theme.removeListener(_onLocalChanged);
    localeProvider.removeListener(_onLocalChanged);
    super.dispose();
  }
}

class NotificationPrefs {
  const NotificationPrefs._();

  static const Map<String, bool> defaults = {
    'friendRequests': true,
    'sessionInvites': true,
  };

  static Map<String, bool> _current = Map.of(defaults);

  static bool allow(String key) => _current[key] ?? defaults[key] ?? true;

  static void remember(Map<String, bool> value) {
    _current = Map.of(value);
    LocalStore.saveMap(StoreKeys.notificationPrefs, Map<String, dynamic>.from(value));
  }

  static Map<String, bool> restore() {
    final saved = LocalStore.readMap(StoreKeys.notificationPrefs);
    if (saved == null) return Map.of(defaults);

    _current = {
      ...defaults,
      for (final entry in saved.entries)
        if (entry.value is bool) entry.key: entry.value as bool,
    };
    return Map.of(_current);
  }
}
