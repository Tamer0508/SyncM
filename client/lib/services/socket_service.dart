import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _token;
  String? _baseUrl;

  bool get isConnected => _socket?.connected ?? false;

  void init(String baseUrl, String token) {
    if (_socket?.connected == true && _baseUrl == baseUrl && _token == token) return;

    _baseUrl = baseUrl;
    _token = token;

    _socket?.disconnect();
    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket!.onConnect((_) {
      _socket!.emit('authenticate', {'token': token});
    });

    _socket!.onDisconnect((_) {});
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, (data) => handler(data));
  }

  void off(String event) {
    _socket?.off(event);
  }

  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}