// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _authTokenKey = 'syncm_auth_token';

String? readAuthToken() {
  final token = html.window.localStorage[_authTokenKey];
  if (token == null || token.isEmpty) return null;
  return token;
}

void saveAuthToken(String token) {
  html.window.localStorage[_authTokenKey] = token;
}

void clearAuthToken() {
  html.window.localStorage.remove(_authTokenKey);
}
