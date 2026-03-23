import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  final String baseUrl;
  IO.Socket? _socket;

  SocketService({String? baseUrl}) : baseUrl = baseUrl ?? 'http://10.0.2.2:3000';

  void connect() {
    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket!.connect();
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, (data) => handler(data));
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}
