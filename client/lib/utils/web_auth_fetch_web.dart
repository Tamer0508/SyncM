import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<Map<String, dynamic>?> fetchMeWithCredentials(String baseUrl) async {
  final url = Uri.parse('$baseUrl/auth/me?needToken=1').toString();
  try {
    // credentials: 'include' — аналог withCredentials: true у старого XHR.
    final resp = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(method: 'GET', credentials: 'include'),
        )
        .toDart;
    if (resp.status == 200) {
      final text = (await resp.text().toDart).toDart;
      if (text.isEmpty) return null;
      final result = json.decode(text) as Map<String, dynamic>;
      // Remove auth_done from URL without reloading
      try {
        final uri = Uri.base;
        final newParams = Map<String, String>.from(uri.queryParameters);
        newParams.remove('auth_done');
        final newUri = uri.replace(queryParameters: newParams);
        web.window.history.replaceState(null, '', newUri.toString());
      } catch (_) {}
      return result;
    }
    if (resp.status == 401) return null;
    throw Exception('Failed to fetch /auth/me: ${resp.status}');
  } catch (e) {
    rethrow;
  }
}
