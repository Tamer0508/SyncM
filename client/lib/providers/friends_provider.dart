import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/friend.dart';

class FriendsProvider with ChangeNotifier {
  final ApiService api;

  FriendsProvider({ApiService? api}) : api = api ?? ApiService();

  List<Friend> _friends = [];
  List<Friend> get friends => _friends;

  Future<void> fetchFriends() async {
    _friends = await api.getFriends();
    notifyListeners();
  }

  Future<List<Friend>> search(String q) async {
    return await api.searchUsers(q);
  }

  Future<bool> sendRequest(String receiverId) async {
    await api.sendFriendRequest(receiverId);
    return true;
  }
}
