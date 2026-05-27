import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../utils/auth_storage.dart';

class AuthProvider with ChangeNotifier {
  final ApiService api;
  String? _cookie;
  User? _user;
  bool _loading = false;

  AuthProvider({ApiService? api}) : api = api ?? ApiService();

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;
  String? get cookie => _cookie;

  Future<void> fetchMe() async {
    _loading = true;
    notifyListeners();
    try {
      final u = await api.getMe();
      _user = u;
      if (u == null) {
        _cookie = null;
        clearAuthToken();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(Map<String, bool> settings) async {
    final updated = await api.updatePrivacySettings(settings);
    if (_user != null) {
      _user = User(
        id: _user!.id,
        displayName: _user!.displayName,
        email: _user!.email,
        avatarUrl: _user!.avatarUrl,
        spotifyConnected: _user!.spotifyConnected,
        spotifyId: _user!.spotifyId,
        isFriendsHidden: updated['isFriendsHidden'] ?? _user!.isFriendsHidden,
        isActivityHidden: updated['isActivityHidden'] ?? _user!.isActivityHidden,
        isOnlineHidden: updated['isOnlineHidden'] ?? _user!.isOnlineHidden,
      );
      notifyListeners();
    }
  }

  Future<void> updateProfile({String? username, String? customAvatarUrl}) async {
    final updated = await api.updateProfile(username: username, customAvatarUrl: customAvatarUrl);
    if (_user != null) {
      _user = User(
        id: _user!.id,
        displayName: updated['displayName'] ?? _user!.displayName,
        email: _user!.email,
        avatarUrl: updated['avatarUrl'] ?? _user!.avatarUrl,
        customAvatarUrl: updated['customAvatarUrl'] ?? _user!.customAvatarUrl,
        spotifyConnected: _user!.spotifyConnected,
        spotifyId: _user!.spotifyId,
        isFriendsHidden: _user!.isFriendsHidden,
        isActivityHidden: _user!.isActivityHidden,
        isOnlineHidden: _user!.isOnlineHidden,
      );
      notifyListeners();
    }
  }

  Future<void> uploadAvatar(String filePath) async {
    final updated = await api.uploadAvatar(filePath);
    if (_user != null) {
      _user = User(
        id: _user!.id,
        displayName: _user!.displayName,
        email: _user!.email,
        avatarUrl: updated['avatarUrl'] ?? _user!.avatarUrl,
        customAvatarUrl: updated['customAvatarUrl'] ?? _user!.customAvatarUrl,
        spotifyConnected: _user!.spotifyConnected,
        spotifyId: _user!.spotifyId,
        isFriendsHidden: _user!.isFriendsHidden,
        isActivityHidden: _user!.isActivityHidden,
        isOnlineHidden: _user!.isOnlineHidden,
      );
      notifyListeners();
    }
  }

  void restoreSavedAuth() {
    if (_cookie != null && _cookie!.isNotEmpty) return;
    final token = readAuthToken();
    if (token == null || token.isEmpty) return;
    _cookie = token;
    api.setCookie(token);
  }

  void setCookie(String cookie) {
    _cookie = cookie;
    api.setCookie(cookie);
    saveAuthToken(cookie);
    notifyListeners();
  }

  void setUser(User user) {
    _user = user;
    notifyListeners();
  }

  void logout() {
    _user = null;
    _cookie = null;
    api.setCookie('');
    clearAuthToken();
    notifyListeners();
  }

  User userFromMap(Map<String, dynamic> map) => User.fromJson(map);
}