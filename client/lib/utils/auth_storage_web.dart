import 'package:web/web.dart' as web;

const _authTokenKey = 'syncm_auth_token';

Future<String?> readAuthToken() async => readAuthTokenSync();

Future<void> saveAuthToken(String token) async {
  web.window.localStorage.setItem(_authTokenKey, token);
}

Future<void> clearAuthToken() async {
  web.window.localStorage.removeItem(_authTokenKey);
}

String? readAuthTokenSync() {
  final token = web.window.localStorage.getItem(_authTokenKey);
  if (token == null || token.isEmpty) return null;
  return token;
}
