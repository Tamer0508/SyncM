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