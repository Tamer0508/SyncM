import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/auth_storage.dart';
import '../utils/local_store.dart';

class AuthProvider with ChangeNotifier {
  AuthProvider({ApiService? api}) : api = api ?? ApiService() {
    this.api.onTokenIssued = _acceptToken;
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
      final loaded = await api.getMe();
      _user = loaded;
      if (loaded == null) {
        _token = null;
        api.setCookie('');
        await clearAuthToken();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(Map<String, bool> settings) async {
    final updated = await api.updatePrivacySettings(settings);
    final current = _user;
    if (current == null) return;

    _user = current.copyWith(
      isFriendsHidden: updated['isFriendsHidden'],
      isActivityHidden: updated['isActivityHidden'],
      isOnlineHidden: updated['isOnlineHidden'],
      isSearchHidden: updated['isSearchHidden'],
    );
    notifyListeners();
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
    _user = user;
    notifyListeners();
  }

  Future<void> forgetLocalSession() async {
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

    _user = null;
    _token = null;
    api.setCookie('');
    await clearAuthToken();

    await LocalStore.clearAll();

    notifyListeners();
  }

  User userFromMap(Map<String, dynamic> map) => User.fromJson(map);
}