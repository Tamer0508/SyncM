
bool get supportsOAuthLoopback => false;

Future<Map<String, String?>?> runOAuthLoopback({
  required int port,
  required Future<void> Function(String redirectUri) onServerReady,
  Duration timeout = const Duration(minutes: 2),
  String path = '/callback',
  String responseHtml = '',
}) async {
  throw UnsupportedError(
    'Локальный сервер OAuth недоступен на этой платформе — '
    'в вебе используется обычный редирект.',
  );
}

Future<void> stopOAuthLoopback() async {}