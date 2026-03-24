// providers/friends_provider.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/friend.dart';
import 'auth_provider.dart';

class FriendsProvider with ChangeNotifier {
  final ApiService api;

  FriendsProvider({ApiService? api}) : api = api ?? ApiService();

  // Вызови это после логина из AuthProvider
  void syncCookie(String cookie) {
    api.setCookie(cookie);
  }

  List<Friend> _friends = [];
  List<Friend> get friends => _friends;

  Future<void> fetchFriends() async {
    _friends = await api.getFriends();
    notifyListeners();
  }

  Future<List<Friend>> search(String q) => api.searchUsers(q);

  Future<bool> sendRequest(String receiverId) async {
    await api.sendFriendRequest(receiverId);
    return true;
  }

  Future<List<Map<String, dynamic>>> getIncomingRequests() =>
      api.getIncomingRequests();

  Future<bool> removeFriend(String friendshipId) async {
    final ok = await api.deleteRequest(friendshipId);
    if (ok) {
      _friends.removeWhere((f) => f.friendshipId == friendshipId);
      notifyListeners();
    }
    return ok;
  }
}