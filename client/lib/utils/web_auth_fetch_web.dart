// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

Future<Map<String, dynamic>?> fetchMeWithCredentials(String baseUrl) async {
  final url = Uri.parse('$baseUrl/auth/me?needToken=1').toString();
  try {
    final resp = await html.HttpRequest.request(url, method: 'GET', withCredentials: true);
    if (resp.status == 200) {
      final text = resp.responseText ?? '';
      if (text.isEmpty) return null;
      final result = json.decode(text) as Map<String, dynamic>;
      // Remove auth_done from URL without reloading
      try {
        final uri = Uri.base;
        final newParams = Map<String, String>.from(uri.queryParameters);
        newParams.remove('auth_done');
        final newUri = uri.replace(queryParameters: newParams);
        html.window.history.replaceState(null, '', newUri.toString());
      } catch (_) {}
      return result;
    }
    if (resp.status == 401) return null;
    throw Exception('Failed to fetch /auth/me: ${resp.status}');
  } catch (e) {
    rethrow;
  }
}