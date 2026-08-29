import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/auth_storage.dart';
import '../utils/local_store.dart';

class AuthProvider with ChangeNotifier {
  AuthProvider({ApiService? api}) : api = api ?? ApiService() {
    this.api.onTokenIssued = _acceptToken;
    _restoreUserSnapshot();
  }

  void _restoreUserSnapshot() {
    final token = readAuthTokenSync();
    if (token == null) return;

    _token = token;
    api.setCookie(token);

    final saved = LocalStore.readMap(StoreKeys.me);
    if (saved == null) return;

    try {
      _user = User.fromJson(saved);
    } catch (err) {
      debugPrint('Снимок профиля не прочитался: $err');
    }
  }

  final ApiService api;

  String? _token;
  User? _user;
  bool _loading = false;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;

  String? get cookie => _token;
  String? get token => _token;

  void _acceptToken(String value) {
    _token = value;
    api.setCookie(value);
    unawaited(saveAuthToken(value));
    notifyListeners();
  }

  Future<void> fetchMe() async {
    _loading = true;
    notifyListeners();
    try {
      final fresh = await api.getMe();
      final loaded = fresh == null ? null : _withLocalPrivacy(fresh);
      final changed = loaded != _user;
      _user = loaded;

      if (loaded == null) {
        _token = null;
        api.setCookie('');
        await clearAuthToken();
        unawaited(LocalStore.remove(StoreKeys.me));
      } else {
        if (!_privacyBusy) _privacyConfirmed = _privacyOf(loaded);
        if (changed) unawaited(LocalStore.saveMap(StoreKeys.me, loaded.toJson()));
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _persistUser() {
    final current = _user;
    if (current == null) return;
    unawaited(LocalStore.saveMap(StoreKeys.me, current.toJson()));
  }


  static const List<String> _privacyKeys = [
    'isFriendsHidden',
    'isActivityHidden',
    'isOnlineHidden',
    'isSearchHidden',
  ];

  Map<String, bool>? _privacyConfirmed;

  final Map<String, bool> _privacyPending = {};

  final Map<String, bool> _privacySending = {};

  Future<void>? _privacyFlush;

  bool get _privacyBusy =>
      _privacyPending.isNotEmpty || _privacySending.isNotEmpty;

  bool get privacySyncing => _privacyFlush != null;

  Map<String, bool> _privacyOf(User user) => {
        'isFriendsHidden': user.isFriendsHidden,
        'isActivityHidden': user.isActivityHidden,
        'isOnlineHidden': user.isOnlineHidden,
        'isSearchHidden': user.isSearchHidden,
      };

  User _applyPrivacy(User user, Map<String, bool> patch) => user.copyWith(
        isFriendsHidden: patch['isFriendsHidden'],
        isActivityHidden: patch['isActivityHidden'],
        isOnlineHidden: patch['isOnlineHidden'],
        isSearchHidden: patch['isSearchHidden'],
      );

  User _withLocalPrivacy(User user) => _privacyBusy
      ? _applyPrivacy(user, {..._privacySending, ..._privacyPending})
      : user;

  void _settlePrivacy() {
    final current = _user;
    if (current == null) return;

    final next = _applyPrivacy(current, {
      ...?_privacyConfirmed,
      ..._privacyPending,
    });
    if (next == current) return;

    _user = next;
    _persistUser();
    notifyListeners();
  }

  Future<void> updateSettings(Map<String, bool> settings) {
    final before = _user;
    if (before == null) return Future<void>.value();

    _privacyConfirmed ??= _privacyOf(before);

    _user = _applyPrivacy(before, settings);
    notifyListeners();

    _privacyPending.addAll(settings);

    if (_privacyFlush != null) return Future<void>.value();

    return _privacyFlush = _flushPrivacy().whenComplete(() {
      _privacyFlush = null;
    });
  }

  Future<void> _flushPrivacy() async {
    while (_privacyPending.isNotEmpty) {
      _privacySending
        ..clear()
        ..addAll(_privacyPending);
      _privacyPending.clear();

      final Map<String, dynamic> updated;
      try {
        updated = await api.updatePrivacySettings(
          Map<String, bool>.from(_privacySending),
        );
      } catch (_) {
        _privacySending.clear();
        _privacyPending.clear();
        _settlePrivacy();
        rethrow;
      }

      final confirmed = _privacyConfirmed;
      _privacyConfirmed = {
        for (final key in _privacyKeys)
          key: updated[key] as bool? ??
              _privacySending[key] ??
              confirmed?[key] ??
              false,
      };
      _privacySending.clear();

      _settlePrivacy();
    }
  }

  Future<void> updateProfile({String? username, String? customAvatarUrl}) async {
    final updated = await api.updateProfile(
      username: username,
      customAvatarUrl: customAvatarUrl,
    );
    final current = _user;
    if (current == null) return;

    _user = current.copyWith(
      displayName: updated['displayName'] as String?,
      avatarUrl: updated['avatarUrl'] as String?,
      customAvatarUrl: updated['customAvatarUrl'] as String?,
    );
    _persistUser();
    notifyListeners();
  }

  Future<void> uploadAvatar(Uint8List bytes, String fileName) async {
    final updated = await api.uploadAvatar(bytes, fileName);
    final current = _user;
    if (current == null) return;

    _user = current.copyWith(
      avatarUrl: updated['avatarUrl'] as String?,
      customAvatarUrl: updated['customAvatarUrl'] as String?,
    );
    _persistUser();
    notifyListeners();
  }

  Future<void> restoreSavedAuth() async {
    if (_token != null && _token!.isNotEmpty) return;
    final saved = await readAuthToken();
    if (saved == null || saved.isEmpty) return;
    _token = saved;
    api.setCookie(saved);
  }

  void setCookie(String cookie) => _acceptToken(cookie);

  void setUser(User user) {
    final next = _withLocalPrivacy(user);
    if (!_privacyBusy) _privacyConfirmed = _privacyOf(next);
    if (_user == next) return;
    _user = next;
    _persistUser();
    notifyListeners();
  }

  void _resetPrivacyQueue() {
    _privacyPending.clear();
    _privacySending.clear();
    _privacyConfirmed = null;
  }

  Future<void> forgetLocalSession() async {
    _resetPrivacyQueue();
    _user = null;
    _token = null;
    api.setCookie('');
    await clearAuthToken();
    await LocalStore.clearAll();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (err) {
      debugPrint('Logout request failed, clearing local session anyway: $err');
    }

    await _clearLocalSession();
  }

  Future<void> logoutEverywhere() async {
    await api.logoutEverywhere();
    await _clearLocalSession();
  }

  Future<void> _clearLocalSession() async {
    _resetPrivacyQueue();
    _user = null;
    _token = null;
    api.setCookie('');
    await clearAuthToken();

    await LocalStore.clearAll();

    notifyListeners();
  }

  User userFromMap(Map<String, dynamic> map) => User.fromJson(map);
}