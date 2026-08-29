import 'local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _authTokenKey = 'syncm_auth_token';

Future<String?> readAuthToken() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);
    if (token == null || token.isEmpty) return null;
    return token;
  } catch (_) {
    return null;
  }
}

Future<void> saveAuthToken(String token) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, token);
  } catch (_) {}
}

Future<void> clearAuthToken() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
  } catch (_) {}
}
String? readAuthTokenSync() {
  try {
    final token = LocalStore.readString(_authTokenKey);
    if (token == null || token.isEmpty) return null;
    return token;
  } catch (_) {
    return null;
  }
}
