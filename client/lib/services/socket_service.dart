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

  int _lastCalculatedRtt = 100;
  bool _isSyncing = false;
  Timer? _heartbeatTimer;
  int? _lastTickTime;

  final StreamController<Map<String, dynamic>> _friendRequestController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get onFriendRequest => _friendRequestController.stream;

  String? _activeSessionId;
  void setActiveSession(String? sessionId) => _activeSessionId = sessionId;

  Future<void> resyncNow() async {
    if (_socket == null || !_socket!.connected) return;
    await measureMasterOffset();
    if (_activeSessionId != null) {
      _socket!.emit('resync', {'sessionId': _activeSessionId});
    }
  }

  final StreamController<void> _reconnectController = StreamController.broadcast();
  Stream<void> get onReconnect => _reconnectController.stream;

  bool _hasConnectedOnce = false;
  bool get isConnected => _socket?.connected ?? false;

  DateTime get currentServerTime {
    return DateTime.now().add(Duration(milliseconds: _masterOffset));
  }

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

      _socket!.emit('ping_time', {
        'clientTime': t1,
        'rtt': _lastCalculatedRtt,
      });

      try {
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
    _lastCalculatedRtt = medianRtt;

    List<Map<String, int>> validAttempts = attempts
        .where((attempt) => attempt['rtt']! <= medianRtt * 2)
        .toList();

    if (validAttempts.isEmpty) validAttempts = attempts;

    validAttempts.sort((a, b) => a['rtt']!.compareTo(b['rtt']!));
    final int takeN = validAttempts.length >= 6 ? (validAttempts.length ~/ 2) : validAttempts.length.clamp(1, 3);
    List<Map<String, int>> bestAttempts = validAttempts.take(takeN).toList();

    List<int> offsets = bestAttempts.map((e) => e['offset']!).toList()..sort();
    _masterOffset = offsets[offsets.length ~/ 2];
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
    if (_socket != null && _baseUrl == baseUrl && _token == token) return;
    _baseUrl = baseUrl;
    _token = token;
    _socket?.disconnect();
    
    _socket = io.io(baseUrl, <String, dynamic>{
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

      await measureMasterOffset();
      _startHeartbeat();

      if (_hasConnectedOnce) {
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