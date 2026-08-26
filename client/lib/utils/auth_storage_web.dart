import 'package:web/web.dart' as web;

const _authTokenKey = 'syncm_auth_token';

// Web-версия через localStorage. Сигнатуры async — чтобы совпадали с
// нативной реализацией (условный импорт требует идентичных сигнатур).

Future<String?> readAuthToken() async => readAuthTokenSync();

Future<void> saveAuthToken(String token) async {
  web.window.localStorage.setItem(_authTokenKey, token);
}

Future<void> clearAuthToken() async {
  web.window.localStorage.removeItem(_authTokenKey);
}

/// Синхронное чтение токена — см. комментарий в нативной реализации.
String? readAuthTokenSync() {
  final token = web.window.localStorage.getItem(_authTokenKey);
  if (token == null || token.isEmpty) return null;
  return token;
}
