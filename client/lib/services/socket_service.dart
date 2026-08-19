import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  String? _token;
  String? _baseUrl;

  int _masterOffset = 0;

  int get masterOffsetMs => _masterOffset;

  int get rttMs => _lastCalculatedRtt;

  int _lastCalculatedRtt = 100; // Храним последний RTT для отправки на бэк
  bool _isSyncing = false;
  Timer? _heartbeatTimer;
  int? _lastTickTime;

  final StreamController<Map<String, dynamic>> _friendRequestController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get onFriendRequest => _friendRequestController.stream;

  // ─── Фаза 6: реконнект и ресинк сессии ───────────────────────────────────
  // Активная сессия, которую нужно ресинкнуть после переподключения.
  // Провайдер выставляет её при входе в сессию и очищает при выходе.
  String? _activeSessionId;
  void setActiveSession(String? sessionId) => _activeSessionId = sessionId;

  // Принудительный ресинк активной сессии сейчас (например при возврате
  // приложения из фона). Если соединение живо — сразу просим состояние;
  // заодно освежаем offset часов, т.к. во сне они могли уплыть.
  Future<void> resyncNow() async {
    if (_socket == null || !_socket!.connected) return;
    await measureMasterOffset();
    if (_activeSessionId != null) {
      _socket!.emit('resync', {'sessionId': _activeSessionId});
    }
  }

  // Уведомление о том, что соединение восстановилось после разрыва (не
  // первичное подключение). Провайдер слушает и обновляет UI / состояние.
  final StreamController<void> _reconnectController = StreamController.broadcast();
  Stream<void> get onReconnect => _reconnectController.stream;

  // Был ли уже установлен коннект хотя бы раз — чтобы отличить первичное
  // подключение от переподключения.
  bool _hasConnectedOnce = false;
  bool get isConnected => _socket?.connected ?? false;

  DateTime get currentServerTime {
    return DateTime.now().add(Duration(milliseconds: _masterOffset));
  }

  // Текущее серверное время в миллисекундах (Unix epoch). Используется для
  // вычисления визуальной позиции трека по серверному времени (Фаза 4.3).
  int serverNow() {
    return DateTime.now().millisecondsSinceEpoch + _masterOffset;
  }

  DateTime serverToLocal(dynamic serverTime) {
    if (serverTime == null) return DateTime.now();
    DateTime utcTime;
    if (serverTime is String) {
      utcTime = DateTime.parse(serverTime);
    } else if (serverTime is int) {
      utcTime = DateTime.fromMillisecondsSinceEpoch(serverTime, isUtc: true);
    } else if (serverTime is DateTime) {
      utcTime = serverTime;
    } else {
      return DateTime.now();
    }
    return utcTime.toLocal();
  }

  // Сверяем часы с твоим сервером через 'ping_time' / 'pong_time'
  Future<void> measureMasterOffset() async {
    if (_socket == null || !_socket!.connected || _isSyncing) return;
    _isSyncing = true;
    try {
      await _measure();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _measure() async {

    List<Map<String, int>> attempts = [];
    const int targetCycles = 12;

    for (int i = 0; i < targetCycles; i++) {
      if (_socket == null || !_socket!.connected) break;

      final completer = Completer<Map<String, int>>();
      int t1 = DateTime.now().millisecondsSinceEpoch; 

      _socket!.once('pong_time', (data) {
        int t2 = DateTime.now().millisecondsSinceEpoch; 
        
        if (data is Map) {
          int? returnedT1 = data['clientTime'];
          int? serverTime = data['serverTime'];

          if (returnedT1 == t1 && serverTime != null) {
            int rtt = t2 - t1;
            int currentOffset = serverTime - (t1 + (rtt ~/ 2));
            completer.complete({'rtt': rtt, 'offset': currentOffset});
          }
        }
      });

      // Шлем структуру, которую ждет твой бэк, докидывая прошлый RTT
      _socket!.emit('ping_time', {
        'clientTime': t1,
        'rtt': _lastCalculatedRtt,
      });

      try {
        // Таймаут должен быть заведомо больше реального RTT. Раньше было 100мс,
        // и при RTT>100мс (обычный мобильный интернет или удалённый сервер на
        // Railway) КАЖДЫЙ замер отваливался, offset не обновлялся вовсе, и
        // устройство стартовало треки по несинхронизированным часам — это и
        // давало сильный рассинхрон. 600мс покрывает практически любой RTT.
        final result = await completer.future.timeout(const Duration(milliseconds: 600));
        attempts.add(result);
      } catch (err) {
        debugPrint('[SyncTime] Замер не удался: $err');
      }

      await Future.delayed(Duration(milliseconds: 40));
    }

    if (attempts.isEmpty) return;

    List<int> rtts = attempts.map((e) => e['rtt']!).toList()..sort();
    int medianRtt = rtts[rtts.length ~/ 2];
    _lastCalculatedRtt = medianRtt; // Сохраняем медианный RTT

    List<Map<String, int>> validAttempts = attempts
        .where((attempt) => attempt['rtt']! <= medianRtt * 2)
        .toList();

    if (validAttempts.isEmpty) validAttempts = attempts;

    validAttempts.sort((a, b) => a['rtt']!.compareTo(b['rtt']!));
    // Берём лучшую половину замеров (с наименьшим RTT — они точнее), но не
    // меньше 3. По ним считаем МЕДИАНУ offset, а не среднее: медиана
    // устойчива к одиночным выбросам (случайный лаг в одном замере не
    // утянет весь offset).
    final int takeN = validAttempts.length >= 6 ? (validAttempts.length ~/ 2) : validAttempts.length.clamp(1, 3);
    List<Map<String, int>> bestAttempts = validAttempts.take(takeN).toList();

    List<int> offsets = bestAttempts.map((e) => e['offset']!).toList()..sort();
    _masterOffset = offsets[offsets.length ~/ 2]; // медиана
    debugPrint('[SyncTime] Офсет: $_masterOffset мс, RTT: $_lastCalculatedRtt мс, замеров: ${attempts.length}/$targetCycles');
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _lastTickTime = DateTime.now().millisecondsSinceEpoch;
    
    _heartbeatTimer = Timer.periodic(Duration(seconds: 15), (timer) async {
      if (_socket == null || !_socket!.connected) return;

      int now = DateTime.now().millisecondsSinceEpoch;
      if (_lastTickTime != null && (now - _lastTickTime!) > 20000) {
        _masterOffset = 0;
        await measureMasterOffset();
      } else {
        await _executeSingleSync(); 
      }
      _lastTickTime = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastTickTime = null;
  }

  Future<void> _executeSingleSync() async {
    if (_socket == null || !_socket!.connected || _isSyncing) return;

    final completer = Completer<void>();
    int t1 = DateTime.now().millisecondsSinceEpoch;

    _socket!.once('pong_time', (data) {
      int t2 = DateTime.now().millisecondsSinceEpoch;
      if (data is Map && data['clientTime'] == t1 && data['serverTime'] != null) {
        int rtt = t2 - t1;
        _lastCalculatedRtt = rtt; 
        // Порог RTT для принятия замера. Раньше 300мс — при более высоком
        // пинге (мобильный интернет) heartbeat вообще не корректировал offset
        // между полными калибровками, и часы медленно уплывали. 600мс покрывает
        // реальные условия. EMA-сглаживание ниже гасит случайные выбросы.
        if (rtt < 600) {
          int newOffset = (data['serverTime'] as int) - (t1 + (rtt ~/ 2));
          _masterOffset = ((_masterOffset * 4) + newOffset) ~/ 5;
        }
      }
      if (!completer.isCompleted) completer.complete();
    });

    _socket!.emit('ping_time', {
      'clientTime': t1,
      'rtt': _lastCalculatedRtt,
    });
    await completer.future.timeout(Duration(milliseconds: 1200), onTimeout: () {});
  }

  void init(String baseUrl, String token) {
    // Уже есть сокет с теми же параметрами (подключён ИЛИ подключается) — не
    // трогаем. Раньше проверялось только _socket?.connected == true, но между
    // созданием и реальным подключением есть окно, и повторный init в этом
    // окне (у нас теперь два пути: initState и build) убивал первый сокет
    // через disconnect() до того, как он подключался — onConnect не срабатывал.
    if (_socket != null && _baseUrl == baseUrl && _token == token) return;
    _baseUrl = baseUrl;
    _token = token;
    _socket?.disconnect();
    
    _socket = io.io(baseUrl, <String, dynamic>{
      // Только websocket. polling на Railway (за прокси, без sticky sessions)
      // не завершает хендшейк и даёт timeout — раньше всё работало именно на
      // чистом websocket, возвращаем его.
      'transports': ['websocket'],
      'auth': {'token': token},
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 9999,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 15000,
      'randomizationFactor': 0.5,
    });

    debugPrint('[Socket] подключаемся к $baseUrl, длинаТокена=${token.length}');

    _rebindAll();

    _socket!.onConnectError((err) => debugPrint('[Socket] ОШИБКА подключения: $err'));
    _socket!.onError((err) => debugPrint('[Socket] ошибка: $err'));
    _socket!.onDisconnect((reason) => debugPrint('[Socket] отключён: $reason'));

    _socket!.onConnect((_) async {
      debugPrint('[Socket] ПОДКЛЮЧЁН');

      // Фаза 6: после ЛЮБОГО подключения заново измеряем offset часов.
      // Ускоренная процедура сама по себе быстрая (несколько ping/pong).
      await measureMasterOffset();
      _startHeartbeat();

      // Отличаем первичное подключение от переподключения.
      if (_hasConnectedOnce) {
        // Это реконнект после разрыва. Если мы в сессии — просим у сервера
        // полное состояние (session_state), чтобы мгновенно вернуться в
        // синхру, и уведомляем подписчиков.
        if (_activeSessionId != null) {
          _socket!.emit('resync', {'sessionId': _activeSessionId});
        }
        if (!_reconnectController.isClosed) _reconnectController.add(null);
      }
      _hasConnectedOnce = true;
    });

    _socket!.on('friend_request', (data) {
      try {
        final parsed = Map<String, dynamic>.from(data as Map);
        _friendRequestController.add(parsed);
      } catch (_) {}
    });

    _socket!.onDisconnect((_) => _stopHeartbeat());
  }


  final Map<String, List<_Subscriber>> _subscribers = {};
  final Set<String> _boundEvents = {};

  /// Подписывается на событие. Возвращает токен — отписываться нужно им.
  SocketSubscription on(String event, void Function(dynamic data) handler) {
    final subscriber = _Subscriber(event, handler);
    _subscribers.putIfAbsent(event, () => <_Subscriber>[]).add(subscriber);
    _bindEvent(event);
    return SocketSubscription._(this, subscriber);
  }

  void _bindEvent(String event) {
    final socket = _socket;
    if (socket == null) return;
    if (!_boundEvents.add(event)) return;
    socket.on(event, (data) => _dispatch(event, data));
  }

  void _rebindAll() {
    _boundEvents.clear();
    for (final event in _subscribers.keys) {
      _bindEvent(event);
    }
  }

  void _dispatch(String event, dynamic data) {
    final list = _subscribers[event];
    if (list == null || list.isEmpty) return;
    // Копия списка: обработчик вправе отписаться прямо во время вызова —
    // так делает PlaybackProvider.stop() внутри session_ended.
    for (final subscriber in List<_Subscriber>.of(list)) {
      if (subscriber.cancelled) continue;
      try {
        subscriber.handler(data);
      } catch (err, stack) {
        debugPrint('[Socket] обработчик "$event" упал: $err\n$stack');
      }
    }
  }

  void _cancel(_Subscriber subscriber) {
    if (subscriber.cancelled) return;
    subscriber.cancelled = true;
    final list = _subscribers[subscriber.event];
    if (list == null) return;
    list.remove(subscriber);
    if (list.isEmpty) _subscribers.remove(subscriber.event);
  }

  void emit(String event, [dynamic data]) => _socket?.emit(event, data);

  void disconnect() {
    _stopHeartbeat();
    _socket?.dispose();
    _socket = null;
    _baseUrl = null;
    _token = null;
    _hasConnectedOnce = false;
    _activeSessionId = null;
    _masterOffset = 0;
    _boundEvents.clear();
  }

  Future<void> dispose() async {
    disconnect();
    _subscribers.clear();
    await _friendRequestController.close();
    await _reconnectController.close();
  }
}

class _Subscriber {
  _Subscriber(this.event, this.handler);

  final String event;
  final void Function(dynamic data) handler;
  bool cancelled = false;
}

class SocketSubscription {
  SocketSubscription._(this._service, this._subscriber);

  final SocketService _service;
  final _Subscriber _subscriber;

  String get event => _subscriber.event;
  bool get isCancelled => _subscriber.cancelled;

  void cancel() => _service._cancel(_subscriber);
}

extension SocketSubscriptionList on List<SocketSubscription> {
  void cancelAll() {
    for (final subscription in this) {
      subscription.cancel();
    }
    clear();
  }
}