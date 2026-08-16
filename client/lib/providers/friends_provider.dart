import 'dart:async';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/friend.dart';
import '../services/api_service.dart';
import '../utils/local_store.dart';
import '../services/socket_service.dart';
import '../utils/app_globals.dart';
import '../utils/notifications.dart';

class FriendsProvider with ChangeNotifier {
  FriendsProvider({ApiService? api}) : api = api ?? ApiService() {
    _restoreFromCache();
  }

  void _restoreFromCache() {
    final cachedFriends = LocalStore.readList(StoreKeys.friends);
    if (cachedFriends.isNotEmpty) {
      _friends = cachedFriends.map(Friend.fromJson).toList();
      _friendsHasMore = true;
    }

    final cachedRequests = LocalStore.readList(StoreKeys.friendRequests);
    if (cachedRequests.isNotEmpty) _friendRequests = cachedRequests;
  }

  final ApiService api;

  void syncCookie(String cookie) => api.setCookie(cookie);


  List<Friend> _friends = [];
  List<Friend> get friends => List.unmodifiable(_friends);

  String? _friendsNextCursor;
  bool _friendsHasMore = true;
  bool _friendsLoading = false;

  bool get friendsLoading => _friendsLoading;
  bool get hasMoreFriends => _friendsHasMore;

  Future<void> fetchFriends({bool refresh = false, int limit = Config.pageSize}) async {
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
      final items = (res['items'] as List?)?.whereType<Friend>().toList() ?? const <Friend>[];
      final nextCursor = res['nextCursor'] as String?;

      _friends.addAll(items);
      _friendsNextCursor = nextCursor;
      _friendsHasMore = nextCursor != null;

      if (refresh) {
        unawaited(LocalStore.saveList(
          StoreKeys.friends,
          _friends.map((f) => f.toJson()).toList(),
        ));
      }
    } finally {
      _friendsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshFriends({int limit = Config.pageSize}) =>
      fetchFriends(refresh: true, limit: limit);

  Future<List<Friend>> search(String q) => api.searchUsers(q);

  Future<bool> sendRequest(String receiverId) async {
    await api.sendFriendRequest(receiverId);
    return true;
  }

  Future<bool> removeFriend(String friendshipId) async {
    final index = _friends.indexWhere((f) => f.friendshipId == friendshipId);
    if (index == -1) return false;

    final friend = _friends[index];
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

  int get unreadCount => _friendRequests.length;

  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> get incomingRequests => List.unmodifiable(_friendRequests);

  String? _incomingNextCursor;
  bool _incomingHasMore = true;
  bool _incomingLoading = false;

  bool get incomingLoading => _incomingLoading;
  bool get hasMoreIncoming => _incomingHasMore;

  Future<void> fetchIncomingRequests({bool refresh = false, int limit = Config.pageSize}) async {
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
      final items = (res['items'] as List?)?.whereType<Map>().map(Map<String, dynamic>.from).toList() ??
          const <Map<String, dynamic>>[];
      final nextCursor = res['nextCursor'] as String?;

      _friendRequests.addAll(items);
      _incomingNextCursor = nextCursor;
      _incomingHasMore = nextCursor != null;

      if (refresh) {
        unawaited(LocalStore.saveList(StoreKeys.friendRequests, _friendRequests));
      }
    } finally {
      _incomingLoading = false;
      notifyListeners();
    }
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
    if (ok) notifyListeners();
    return ok;
  }

  void markAsRead() {}


  SocketService? _socket;

  final List<SocketSubscription> _subscriptions = [];

  void init(SocketService socketService) {
    if (identical(_socket, socketService)) return;

    _detachSocket();
    _socket = socketService;

    _subscriptions.addAll([
      socketService.on('friend_request', (data) {
        if (data is Map) _addNewRequest(Map<String, dynamic>.from(data));
      }),
      socketService.on('friend_online', (data) {
        final userId = (data is Map) ? data['userId'] as String? : null;
        if (userId != null) _updateFriendOnline(userId, true);
      }),
      socketService.on('friend_offline', (data) {
        if (data is! Map) return;
        final userId = data['userId'] as String?;
        if (userId == null) return;
        _updateFriendOnline(userId, false, lastSeenAt: data['lastSeenAt'] as String?);
      }),
    ]);
  }

  void _detachSocket() {
    _subscriptions.cancelAll();
    _socket = null;
  }

  void _updateFriendOnline(String userId, bool online, {String? lastSeenAt}) {
    final idx = _friends.indexWhere((f) => f.id == userId);
    if (idx == -1) return;

    final old = _friends[idx];
    DateTime? seenAt = old.lastSeenAt;
    if (!online && lastSeenAt != null) {
      seenAt = DateTime.tryParse(lastSeenAt)?.toLocal() ?? old.lastSeenAt;
    }

    _friends[idx] = Friend(
      id: old.id,
      name: old.name,
      avatarUrl: old.avatarUrl,
      friendshipId: old.friendshipId,
      isOnline: online,
      lastSeenAt: online ? null : seenAt,
      isOnlineHidden: old.isOnlineHidden,
      friendshipStatus: old.friendshipStatus,
    );
    notifyListeners();
  }

  void _addNewRequest(Map<String, dynamic> data) {
    final id = data['id'];
    if (id != null && _friendRequests.any((r) => r['id'] == id)) return;

    _friendRequests.insert(0, data);
    _showNotification(data['fromUserName'] as String? ?? 'пользователь');
    notifyListeners();
  }

  void _showNotification(String fromUserName) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showAppNotification(
      context,
      message: 'Заявка в друзья от $fromUserName',
      type: NotificationType.info,
      actionLabel: 'Открыть',
      onAction: () => navigatorKey.currentState?.pushNamed('/friends/requests'),
    );
  }

  @override
  void dispose() {
    _detachSocket();
    super.dispose();
  }
}