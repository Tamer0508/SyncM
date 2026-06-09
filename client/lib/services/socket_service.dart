import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _token;
  String? _baseUrl;

  int _masterOffset = 0; 
  int _lastCalculatedRtt = 100; // Храним последний RTT для отправки на бэк
  bool _isSyncing = false;
  Timer? _heartbeatTimer;
  int? _lastTickTime;

  final StreamController<Map<String, dynamic>> _friendRequestController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get onFriendRequest => _friendRequestController.stream;
  bool get isConnected => _socket?.connected ?? false;

  DateTime get currentServerTime {
    return DateTime.now().add(Duration(milliseconds: _masterOffset));
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

    List<Map<String, int>> attempts = [];
    const int targetCycles = 8; 

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
        final result = await completer.future.timeout(Duration(milliseconds: 100));
        attempts.add(result);
      } catch (_) {}

      await Future.delayed(Duration(milliseconds: 40));
    }

    if (attempts.isEmpty) {
      _isSyncing = false;
      return;
    }

    List<int> rtts = attempts.map((e) => e['rtt']!).toList()..sort();
    int medianRtt = rtts[rtts.length ~/ 2];
    _lastCalculatedRtt = medianRtt; // Сохраняем медианный RTT

    List<Map<String, int>> validAttempts = attempts
        .where((attempt) => attempt['rtt']! <= medianRtt * 2)
        .toList();

    if (validAttempts.isEmpty) validAttempts = attempts;

    validAttempts.sort((a, b) => a['rtt']!.compareTo(b['rtt']!));
    List<Map<String, int>> bestAttempts = validAttempts.take(3).toList();

    int offsetSum = 0;
    for (var attempt in bestAttempts) {
      offsetSum += attempt['offset']!;
    }

    _masterOffset = offsetSum ~/ bestAttempts.length;
    _isSyncing = false;
    print('[SyncTime] Калибровка завершена. Офсет: $_masterOffset мс. RTT: $_lastCalculatedRtt мс.');
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
        if (rtt < 300) {
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
    if (_socket?.connected == true && _baseUrl == baseUrl && _token == token) return;
    _baseUrl = baseUrl;
    _token = token;
    _socket?.disconnect();
    
    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket!.onConnect((_) async {
      _socket!.emit('authenticate', {'token': token});
      await measureMasterOffset(); 
      _startHeartbeat(); 
    });

    _socket!.on('friend_request', (data) {
      try {
        final parsed = Map<String, dynamic>.from(data as Map);
        _friendRequestController.add(parsed);
      } catch (_) {}
    });

    _socket!.onDisconnect((_) => _stopHeartbeat());
  }

  void on(String event, Function(dynamic) handler) => _socket?.on(event, (data) => handler(data));
  void off(String event) => _socket?.off(event);
  void emit(String event, [dynamic data]) => _socket?.emit(event, data);
  void disconnect() { _stopHeartbeat(); _socket?.disconnect(); _socket = null; }
}