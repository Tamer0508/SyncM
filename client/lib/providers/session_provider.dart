import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../models/session.dart';
import '../utils/app_globals.dart';

class SessionProvider with ChangeNotifier {
  final ApiService api;

  SessionProvider({ApiService? api}) : api = api ?? ApiService();

  List<SessionModel> _sessions = [];
  List<SessionModel> get sessions => _sessions;

  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> get invites => _invites;

  bool _loading = false;
  bool get loading => _loading;

  bool _invitesLoading = false;
  bool get invitesLoading => _invitesLoading;

  int _unreadInvitesCount = 0;
  int get unreadInvitesCount => _unreadInvitesCount;

  bool _socketListening = false;
  SocketService? _socket;

  Future<void> fetchMySessions() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await api.getMySessions();
      _sessions = data
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
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
      _invites = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } finally {
      _invitesLoading = false;
      notifyListeners();
    }
  }

  void syncCookie(String cookie) {
    api.setCookie(cookie);
  }

  void init(SocketService socketService) {
    _socket ??= socketService;
    listenToSocket();
  }

  void listenToSocket() {
    if (_socketListening) return;
    _socketListening = true;

    _socket?.on('session_invite', (data) {
      if (data is! Map) return;
      final parsed = Map<String, dynamic>.from(data);
      _onSessionInvite(parsed);
    });

    _socket?.on('invite_response', (data) async {
      if (data is! Map) return;
      final parsed = Map<String, dynamic>.from(data);
      if (parsed['accept'] == true) {
        await fetchMySessions();
      }
    });
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
    }

    _unreadInvitesCount++;
    _showInviteNotification(data['sessionName'] as String? ?? 'Сессия');
    notifyListeners();

    fetchInvites(refresh: true);
  }

  void markInvitesAsRead() {
    _unreadInvitesCount = 0;
    notifyListeners();
  }

  void _showInviteNotification(String sessionName) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('🎵 Приглашение в сессию «$sessionName»'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.deepPurple[700],
        action: SnackBarAction(
          label: 'Открыть',
          textColor: Colors.white,
          onPressed: () {
            navigatorKey.currentState?.pushNamed('/session/invites');
          },
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> createSession(String name, String friendId) async {
    return await api.createSession(name, friendId);
  }

  Future<Map<String, dynamic>?> respondToInvite(String sessionId, bool accept) async {
    final result = await api.respondToInvite(sessionId, accept);
    if (result != null) {
      _invites.removeWhere((i) => i['id'] == sessionId);
      if (accept) {
        await fetchMySessions();
      }
      notifyListeners();
    }
    return result;
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) async {
    return await api.addTracks(sessionId, tracks);
  }

  Future<bool> rateTrack(String trackId, int rating) async {
    return await api.rateTrack(trackId, rating);
  }

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    return await api.endSession(sessionId);
  }

  String? hostNameForInvite(Map<String, dynamic> invite) {
    final hostId = invite['hostId'] as String?;
    final members = invite['members'] as List?;
    if (hostId == null || members == null) return null;
    for (final m in members) {
      final member = m as Map<String, dynamic>;
      final user = member['user'] as Map<String, dynamic>?;
      if (user?['id'] == hostId) {
        return user?['username'] as String?;
      }
    }
    return null;
  }
}
