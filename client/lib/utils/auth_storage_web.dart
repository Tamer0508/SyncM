// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _authTokenKey = 'syncm_auth_token';

// Web-версия через localStorage. Сигнатуры async — чтобы совпадали с
// нативной реализацией (условный импорт требует идентичных сигнатур).

Future<String?> readAuthToken() async {
  final token = html.window.localStorage[_authTokenKey];
  if (token == null || token.isEmpty) return null;
  return token;
}

Future<void> saveAuthToken(String token) async {
  html.window.localStorage[_authTokenKey] = token;
}

Future<void> clearAuthToken() async {
  html.window.localStorage.remove(_authTokenKey);
}