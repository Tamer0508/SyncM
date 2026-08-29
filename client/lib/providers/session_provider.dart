import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/local_store.dart';
import '../services/socket_service.dart';
import 'settings_provider.dart';
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
  List<SessionModel> get sessions => UnmodifiableListView(_sessions);

  List<Map<String, dynamic>> _invites = [];

  Map<String, dynamic>? _endedResults;
  Map<String, dynamic>? get endedResults => _endedResults;

  Map<String, dynamic>? _openSessionRequest;
  Map<String, dynamic>? get openSessionRequest => _openSessionRequest;

  void requestOpenSession(Map<String, dynamic> session) {
    _openSessionRequest = session;
    notifyListeners();
  }

  void consumeOpenSession() {
    _openSessionRequest = null;
  }

  void consumeEndedResults() {
    if (_endedResults == null) return;
    _endedResults = null;
  }
  List<Map<String, dynamic>> get invites => UnmodifiableListView(_invites);

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

  Future<void> fetchInvites() async {
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

  final List<SocketSubscription> _subscriptions = [];

  final Set<String> _selfEndedSessions = {};

  void init(SocketService socketService) {
    if (identical(_socket, socketService)) return;

    _detachSocket();
    _socket = socketService;

    _subscriptions.add(socketService.on('session_invite', (data) {
      if (data is Map) _onSessionInvite(Map<String, dynamic>.from(data));
    }));

    _subscriptions.add(socketService.on('session_ended', (data) {
      final result = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

      fetchMySessions().ignore();

      final endedId = result['sessionId'] as String?;
      if (endedId != null && _selfEndedSessions.remove(endedId)) return;

      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;

      if (ctx.isWideWindow) {
        _endedResults = result;
        notifyListeners();
        return;
      }

      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/session/results',
        (route) => route.settings.name == '/home' || route.isFirst,
        arguments: result,
      );
    }));

    _subscriptions.add(socketService.on('user_joined', (_) {
      fetchMySessions().ignore();
    }));

    _subscriptions.add(socketService.on('invite_response', (data) {
      if (data is! Map) return;
      if (data['accept'] == true) {
        fetchMySessions().ignore();
      }
    }));
  }

  void _detachSocket() {
    _subscriptions.cancelAll();
    _socket = null;
  }

  void _onSessionInvite(Map<String, dynamic> data) {
    final sessionId = data['sessionId'] as String?;
    if (sessionId == null) return;

    final alreadyListed = _invites.any((i) => i['id'] == sessionId);
    if (!alreadyListed) {
      _invites.insert(0, {
        'id': sessionId,
        'name': data['sessionName'] ?? appL10n?.homeSession ?? 'Сессия',
        'hostId': data['hostId'],
      });
      _showInviteNotification(
        data['sessionName'] as String? ?? appL10n?.homeSession ?? 'Сессия',
      );
      notifyListeners();
    }

    fetchInvites().ignore();
  }

  void markInvitesAsRead() {}

  void _showInviteNotification(String sessionName) {
    if (!NotificationPrefs.allow('sessionInvites')) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    showAppNotification(
      context,
      message: appL10n?.invitesNotification(sessionName) ??
          'Приглашение в сессию «$sessionName»',
      type: NotificationType.info,
      actionLabel: appL10n?.commonOpen ?? 'Открыть',
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

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    _selfEndedSessions.add(sessionId);
    try {
      return await api.endSession(sessionId);
    } catch (err) {
      _selfEndedSessions.remove(sessionId);
      rethrow;
    }
  }

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

  void clear() {
    _sessions = [];
    _invites = [];
    _endedResults = null;
    _openSessionRequest = null;
    _selfEndedSessions.clear();
    _loading = false;
    _invitesLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _detachSocket();
    super.dispose();
  }
}