// providers/friends_provider.dart
import 'package:flutter/material.dart';
import 'package:syncm/services/socket_service.dart';
import '../services/api_service.dart';
import '../models/friend.dart';
import '../utils/app_globals.dart';

class FriendsProvider with ChangeNotifier {
  final ApiService api;

  FriendsProvider({ApiService? api}) : api = api ?? ApiService();

  void syncCookie(String cookie) {
    api.setCookie(cookie);
  }

  List<Friend> _friends = [];
  List<Friend> get friends => _friends;

  String? _friendsNextCursor;
  bool _friendsHasMore = true;
  bool _friendsLoading = false;

  bool get friendsLoading => _friendsLoading;
  bool get hasMoreFriends => _friendsHasMore;

  Future<void> fetchFriends({bool refresh = false, int limit = 20}) async {
    if (_friendsLoading) return;
    if (refresh) {
      _friends = [];
      _friendsNextCursor = null;
      _friendsHasMore = true;
    }
    if (!_friendsHasMore) return;

    _friendsLoading = true;
    notifyListeners();

    try {
      final res = await api.getFriends(cursor: _friendsNextCursor, limit: limit);
      final items = res['items'] as List<Friend>;
      final nextCursor = res['nextCursor'] as String?;

      _friends.addAll(items);
      _friendsNextCursor = nextCursor;
      _friendsHasMore = nextCursor != null;
    } finally {
      _friendsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshFriends({int limit = 20}) async {
    await fetchFriends(refresh: true, limit: limit);
  }

  Future<List<Friend>> search(String q) => api.searchUsers(q);

  Future<bool> sendRequest(String receiverId) async {
    await api.sendFriendRequest(receiverId);
    return true;
  }

  Future<bool> acceptRequest(String friendshipId) async {
    final ok = await api.acceptRequest(friendshipId);
    if (ok) {
      _friendRequests.removeWhere((req) => req['id'] == friendshipId);
      await fetchFriends(refresh: true);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> deleteRequest(String friendshipId) async {
    final ok = await api.deleteRequest(friendshipId);
    if (ok) {
      _friendRequests.removeWhere((req) => req['id'] == friendshipId);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> cancelSentRequest(String friendshipId) async {
    final ok = await api.deleteRequest(friendshipId);
    if (ok) {
      notifyListeners();
    }
    return ok;
  }

  int _unreadFriendRequestsCount = 0;
  int get unreadCount => _unreadFriendRequestsCount;

  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> get incomingRequests => _friendRequests;

  String? _incomingNextCursor;
  bool _incomingHasMore = true;
  bool _incomingLoading = false;

  bool get incomingLoading => _incomingLoading;
  bool get hasMoreIncoming => _incomingHasMore;

  Future<void> fetchIncomingRequests({bool refresh = false, int limit = 20}) async {
    if (_incomingLoading) return;
    if (refresh) {
      _friendRequests = [];
      _incomingNextCursor = null;
      _incomingHasMore = true;
    }
    if (!_incomingHasMore) return;

    _incomingLoading = true;
    notifyListeners();

    try {
      final res = await api.getIncomingRequests(cursor: _incomingNextCursor, limit: limit);
      final items = (res['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final nextCursor = res['nextCursor'] as String?;

      _friendRequests.addAll(items);
      _incomingNextCursor = nextCursor;
      _incomingHasMore = nextCursor != null;
    } finally {
      _incomingLoading = false;
      notifyListeners();
    }
  }

  Future<bool> removeFriend(String friendshipId) async {
    final friend = _friends.firstWhere((f) => f.friendshipId == friendshipId);
    final ok = await api.deleteFriendByUserId(friend.id);
    if (ok) {
      _friends.removeWhere((f) => f.id == friend.id);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> removeFriendByUserId(String userId) async {
    final ok = await api.deleteFriendByUserId(userId);
    if (ok) {
      _friends.removeWhere((f) => f.id == userId);
      notifyListeners();
    }
    return ok;
  }

  bool _socketListening = false;

  SocketService? _socket;

  void init(SocketService socketService) {
    _socket ??= socketService;
    listenToSocket();
  }

  void listenToSocket() {
    if (_socketListening) return;
    _socketListening = true;
    _socket?.on('friend_request', (data) {
      if (data is Map<String, dynamic>) {
        _addNewRequest(data);
      }
    });
    _socket?.on('friend_online', (data) {
      final userId = data['userId'] as String;
      _updateFriendOnline(userId, true);
    });
    _socket?.on('friend_offline', (data) {
      final userId = data['userId'] as String;
      _updateFriendOnline(userId, false, lastSeenAt: data['lastSeenAt'] as String?);
    });
  }

  void _updateFriendOnline(String userId, bool online, {String? lastSeenAt}) {
    final idx = _friends.indexWhere((f) => f.id == userId);
    if (idx != -1) {
      final old = _friends[idx];
      _friends[idx] = Friend(
        id: old.id,
        name: old.name,
        avatarUrl: old.avatarUrl,
        friendshipId: old.friendshipId,
        isOnline: online,
        lastSeenAt: online
            ? null
            : (lastSeenAt != null ? DateTime.parse(lastSeenAt).toLocal() : old.lastSeenAt),
        // Раньше поле терялось при каждом событии присутствия.
        isOnlineHidden: old.isOnlineHidden,
      );
      notifyListeners();
    }
  }

  void markAsRead() {
    _unreadFriendRequestsCount = 0;
    notifyListeners();
  }

  void _addNewRequest(Map<String, dynamic> data) {
    _friendRequests.insert(0, data);
    _unreadFriendRequestsCount++;
    _showNotification(data['fromUserName'] ?? 'пользователь');
    notifyListeners();
  }

  void _showNotification(String fromUserName) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('📨 Новая заявка в друзья от $fromUserName'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green[700],
      ),
    );
  }
}