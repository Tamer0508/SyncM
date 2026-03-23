import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  final ApiService api;

  AuthProvider({ApiService? api}) : api = api ?? ApiService();

  User? _user;
  bool _loading = false;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;

  Future<void> fetchMe() async {
    _loading = true;
    notifyListeners();
    try {
      final u = await api.getMe();
      _user = u;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void logout() {
    _user = null;
    notifyListeners();
  }
  User userFromMap(Map<String, dynamic> map) {
    return User.fromJson(map);
  }

  void setUser(User user) {
    _user = user;
    notifyListeners();
  }

  void setCookie(String cookie) {
    api.setCookie(cookie);
  }
}
