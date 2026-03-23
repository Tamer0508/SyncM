import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  final String baseUrl;
  IO.Socket? _socket;

  String? _cookie;

  SocketService({String? baseUrl}) : baseUrl = baseUrl ?? 'http://10.0.2.2:3000';

  void connect() {
    final opts = <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    };
    if (_cookie != null && _cookie!.isNotEmpty) opts['extraHeaders'] = {'Cookie': _cookie!};

    _socket = IO.io(baseUrl, opts);
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

  void setCookie(String cookie) {
    _cookie = cookie;
  }
}
