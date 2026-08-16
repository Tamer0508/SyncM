import 'dart:async';
import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/api_service.dart';
import '../theme.dart';
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

  /// Итоги только что завершённой сессии, которые ещё не показаны.
  ///
  /// Заполняется, когда сессию закрыл кто-то другой, а мы на широком экране:
  /// показать их должен главный экран в своей центральной части. Он же
  /// вызывает consumeEndedResults, чтобы итоги не всплыли повторно при
  /// следующей перерисовке.
  Map<String, dynamic>? _endedResults;
  Map<String, dynamic>? get endedResults => _endedResults;

  /// Сессия, которую просят открыть.
  ///
  /// Переход к сессии происходит из нескольких мест: создание, принятие
  /// приглашения, список активных сессий. Каждое из них раньше открывало её
  /// маршрутом напрямую — и на широком экране это закрывало боковую панель и
  /// панель воспроизведения, хотя при повторном заходе с главной та же
  /// сессия показывалась встроенной. Отсюда и расхождение: одна и та же
  /// сессия выглядела по-разному в зависимости от того, как в неё попали.
  ///
  /// Теперь экраны не решают сами, а просят показать сессию. Как показать —
  /// встроенно или маршрутом — определяет тот, кто это умеет.
  Map<String, dynamic>? _openSessionRequest;
  Map<String, dynamic>? get openSessionRequest => _openSessionRequest;

  void requestOpenSession(Map<String, dynamic> session) {
    _openSessionRequest = session;
    notifyListeners();
  }

  void consumeOpenSession() {
    _openSessionRequest = null;
    // Без оповещения: значение забирают во время построения дерева.
  }

  void consumeEndedResults() {
    if (_endedResults == null) return;
    _endedResults = null;
    // Без оповещения: поле забирают во время построения, а notifyListeners
    // оттуда вызывать нельзя — это приводит к исключению.
  }
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

  /// Загружает приглашения.
  ///
  /// Параметра `refresh` здесь нет намеренно: список приглашений всегда
  /// перезаписывается целиком, страниц у него нет, и «обновить» — это
  /// единственное, что метод умеет. Раньше параметр был, но не использовался,
  /// и вызывающий код рассчитывал на поведение, которого не существовало.
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

      // Список активных сессий изменился.
      fetchMySessions().ignore();

      // Сессию закрыли мы сами — итоги уже показал тот, кто нажал кнопку.
      final endedId = result['sessionId'] as String?;
      if (endedId != null && _selfEndedSessions.remove(endedId)) return;

      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;

      if (ctx.isWideWindow) {
        _endedResults = result;
        notifyListeners();
        return;
      }

      // На узком экране панелей нет — переходим маршрутом.
      //
      // pushNamedAndRemoveUntil до главного: экран сессии мог быть открыт не
      // напрямую, а поверх других (выбор плейлиста, полноэкранный плеер), и
      // простой pop оставил бы человека на промежуточном экране закрытой
      // сессии.
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/session/results',
        (route) => route.settings.name == '/home' || route.isFirst,
        arguments: result,
      );
    }));

    // Кто-то присоединился к сессии — обновляем список, чтобы состав
    // участников не приходилось обновлять вручную.
    _subscriptions.add(socketService.on('user_joined', (_) {
      fetchMySessions().ignore();
    }));

    _subscriptions.add(socketService.on('invite_response', (data) {
      if (data is! Map) return;
      if (data['accept'] == true) {
        // Список активных сессий изменился — подтягиваем свежий.
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
        'name': data['sessionName'] ?? 'Сессия',
        'hostId': data['hostId'],
      });
      _showInviteNotification(data['sessionName'] as String? ?? 'Сессия');
      notifyListeners();
    }

    fetchInvites().ignore();
  }

  void markInvitesAsRead() {}

  void _showInviteNotification(String sessionName) {
    if (!LocalStore.readBool(StoreKeys.inviteNotifications, defaultValue: true)) {
      return;
    }

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

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    // Помечаем ДО запроса: рассылка session_ended уходит из обработчика на
    // сервере и вполне может опередить ответ на наш же HTTP-запрос.
    _selfEndedSessions.add(sessionId);
    try {
      return await api.endSession(sessionId);
    } catch (err) {
      // Не завершилась — отметку снимаем, иначе чужое завершение этой сессии
      // потом будет молча проигнорировано.
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

  @override
  void dispose() {
    _detachSocket();
    super.dispose();
  }
}