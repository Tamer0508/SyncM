import 'dart:async';
import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/api_service.dart';
import '../utils/local_store.dart';
import '../services/socket_service.dart';
import '../utils/app_globals.dart';
import '../utils/notifications.dart';

class SessionProvider with ChangeNotifier {
  SessionProvider({ApiService? api}) : api = api ?? ApiService() {
    _restoreFromCache();
  }

  void _restoreFromCache() {
    final cachedSessions = LocalStore.readList(StoreKeys.sessions);
    if (cachedSessions.isNotEmpty) {
      _sessions = cachedSessions.map(SessionModel.fromJson).toList();
    }

    final cachedInvites = LocalStore.readList(StoreKeys.invites);
    if (cachedInvites.isNotEmpty) _invites = cachedInvites;
  }

  final ApiService api;

  void syncCookie(String cookie) => api.setCookie(cookie);

  List<SessionModel> _sessions = [];
  List<SessionModel> get sessions => List.unmodifiable(_sessions);

  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> get invites => List.unmodifiable(_invites);

  bool _loading = false;
  bool get loading => _loading;

  bool _invitesLoading = false;
  bool get invitesLoading => _invitesLoading;

  int get unreadInvitesCount => _invites.length;

  Future<void> fetchMySessions() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await api.getMySessions();
      final raw = data.whereType<Map>().map(Map<String, dynamic>.from).toList();
      _sessions = raw.map(SessionModel.fromJson).toList();

      unawaited(LocalStore.saveList(StoreKeys.sessions, raw));
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchInvites({bool refresh = false}) async {
    if (_invitesLoading) return;
    _invitesLoading = true;
    notifyListeners();
    try {
      final data = await api.getMyInvites();
      _invites = data.whereType<Map>().map(Map<String, dynamic>.from).toList();
      unawaited(LocalStore.saveList(StoreKeys.invites, _invites));
    } finally {
      _invitesLoading = false;
      notifyListeners();
    }
  }

  SocketService? _socket;

  static const _events = [
    'session_invite',
    'invite_response',
    'session_ended',
    'user_joined',
  ];

  void init(SocketService socketService) {
    if (identical(_socket, socketService)) return;

    _detachSocket();
    _socket = socketService;

    socketService.on('session_invite', (data) {
      if (data is Map) _onSessionInvite(Map<String, dynamic>.from(data));
    });

    socketService.on('session_ended', (data) {
      final result = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      debugPrint('[Session] получено session_ended');

      fetchMySessions().ignore();

      final navigator = navigatorKey.currentState;
      if (navigator == null) return;

      navigator.pushNamedAndRemoveUntil(
        '/session/results',
        (route) => route.settings.name == '/home' || route.isFirst,
        arguments: result,
      );
    });

    socketService.on('user_joined', (_) {
      fetchMySessions().ignore();
    });

    socketService.on('invite_response', (data) {
      if (data is! Map) return;
      if (data['accept'] == true) {
        // Список активных сессий изменился — подтягиваем свежий.
        fetchMySessions().ignore();
      }
    });
  }

  void _detachSocket() {
    final socket = _socket;
    if (socket == null) return;
    for (final event in _events) {
      socket.off(event);
    }
    _socket = null;
  }

  void _onSessionInvite(Map<String, dynamic> data) {
    final sessionId = data['sessionId'] as String?;
    if (sessionId == null) return;

    final alreadyListed = _invites.any((i) => i['id'] == sessionId);
    if (!alreadyListed) {
      _invites.insert(0, {
        'id': sessionId,
        'name': data['sessionName'] ?? 'Сессия',
        'hostId': data['hostId'],
      });
      _showInviteNotification(data['sessionName'] as String? ?? 'Сессия');
      notifyListeners();
    }

    fetchInvites(refresh: true).ignore();
  }

  void markInvitesAsRead() {}

  void _showInviteNotification(String sessionName) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showAppNotification(
      context,
      message: 'Приглашение в сессию «$sessionName»',
      type: NotificationType.info,
      actionLabel: 'Открыть',
      onAction: () => navigatorKey.currentState?.pushNamed('/session/invites'),
    );
  }


  Future<Map<String, dynamic>?> createSession(String name, String friendId) =>
      api.createSession(name, friendId);

  Future<Map<String, dynamic>?> respondToInvite(String sessionId, bool accept) async {
    final result = await api.respondToInvite(sessionId, accept);
    if (result != null) {
      _invites.removeWhere((i) => i['id'] == sessionId);
      if (accept) await fetchMySessions();
      notifyListeners();
    }
    return result;
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) =>
      api.addTracks(sessionId, tracks);

  Future<bool> rateTrack(String trackId, int rating) => api.rateTrack(trackId, rating);

  Future<Map<String, dynamic>?> endSession(String sessionId) => api.endSession(sessionId);

  String? hostNameForInvite(Map<String, dynamic> invite) {
    final hostId = invite['hostId'] as String?;
    final members = invite['members'] as List?;
    if (hostId == null || members == null) return null;

    for (final m in members) {
      if (m is! Map) continue;
      final user = m['user'];
      if (user is Map && user['id'] == hostId) {
        return user['username'] as String?;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _detachSocket();
    super.dispose();
  }
}