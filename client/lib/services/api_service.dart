import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/friend.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? serverMessage;

  ApiException(this.message, [this.statusCode, this.serverMessage]);

  String get userMessage => serverMessage ?? message;

  @override
  String toString() => 'ApiException: $message (${statusCode ?? 'n/a'})${serverMessage != null ? ' [$serverMessage]' : ''}';
}

class ApiService {
  final String baseUrl;
  final Duration timeout;
  String? _cookie;
  String? getCookie() => _cookie;

  ApiService({String? baseUrl, Duration? timeout})
      : baseUrl = baseUrl ?? 'https://syncm-production.up.railway.app',
        timeout = timeout ?? const Duration(seconds: 30);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};
  Map<String, String> get _headers {
    final h = Map<String, String>.from(_jsonHeaders);
    if (_cookie != null && _cookie!.isNotEmpty) {
      final token = _cookie!.startsWith('connect.sid=')
          ? _cookie!.replaceFirst('connect.sid=', '')
          : _cookie!;
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  dynamic _decode(String body) {
    try {
      return json.decode(body);
    } catch (_) {
      return body;
    }
  }

  String _extractError(http.Response res) {
    try {
      final body = json.decode(res.body);
      if (body is Map && body['error'] != null) {
        return body['error'].toString();
      }
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return res.body.isNotEmpty ? res.body : 'Неизвестная ошибка';
  }

  Future<User?> getMe() async {
    final res = await http.get(_uri('/auth/me'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return User.fromJson(_decode(res.body) as Map<String, dynamic>);
    if (res.statusCode == 401) return null;
    throw ApiException('Failed to get /auth/me', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> updatePrivacySettings(Map<String, bool> settings) async {
    final res = await http.patch(
      _uri('/auth/settings'),
      headers: _headers,
      body: json.encode(settings),
    ).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Ошибка обновления настроек', res.statusCode, _extractError(res));
  }

  Future<List<Friend>> searchUsers(String query) async {
    final res = await http.get(_uri('/friends/search?query=${Uri.encodeQueryComponent(query)}'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final data = _decode(res.body) as List<dynamic>;
      return data.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw ApiException('Ошибка поиска', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final res = await http.get(_uri('/friends/user/$userId'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Ошибка загрузки профиля', res.statusCode, _extractError(res));
  }

  Future<bool> sendFriendRequest(String receiverId) async {
    final res = await http.post(_uri('/friends/request'), headers: _headers, body: json.encode({'receiverId': receiverId})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return true;
    throw ApiException('Ошибка отправки заявки', res.statusCode, _extractError(res));
  }

  Future<bool> acceptRequest(String friendshipId) async {
    final res = await http.patch(_uri('/friends/$friendshipId/accept'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Ошибка принятия заявки', res.statusCode, _extractError(res));
  }

  Future<bool> deleteRequest(String friendshipId) async {
    final res = await http.delete(_uri('/friends/$friendshipId'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Ошибка удаления заявки', res.statusCode, _extractError(res));
  }

  Future<bool> deleteFriendByUserId(String friendId) async {
    final res = await http.delete(_uri('/friends/by-user/$friendId'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Ошибка удаления друга', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> getFriends({String? cursor, int? limit}) async {
    final query = <String, String>{};
    if (limit != null) query['limit'] = '$limit';
    if (cursor != null) query['cursor'] = cursor;
    final uri = Uri.parse('$baseUrl/friends').replace(queryParameters: query);

    final res = await http.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final decoded = _decode(res.body);
      List<dynamic> itemsRaw;
      String? nextCursor;
      if (decoded is Map) {
        itemsRaw = decoded['items'] is List ? decoded['items'] as List<dynamic> : [];
        nextCursor = decoded['nextCursor']?.toString();
      } else if (decoded is List) {
        itemsRaw = decoded as List<dynamic>;
        nextCursor = null;
      } else {
        itemsRaw = [];
        nextCursor = null;
      }

      final items = itemsRaw.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
      return {'items': items, 'nextCursor': nextCursor};
    }
    throw ApiException('Ошибка получения друзей', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> getIncomingRequests({String? cursor, int? limit}) async {
    final query = <String, String>{};
    if (limit != null) query['limit'] = '$limit';
    if (cursor != null) query['cursor'] = cursor;
    final uri = Uri.parse('$baseUrl/friends/requests').replace(queryParameters: query);

    final res = await http.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final decoded = _decode(res.body);
      List<dynamic> itemsRaw;
      String? nextCursor;
      if (decoded is Map) {
        itemsRaw = decoded['items'] is List ? decoded['items'] as List<dynamic> : [];
        nextCursor = decoded['nextCursor']?.toString();
      } else if (decoded is List) {
        itemsRaw = decoded as List<dynamic>;
        nextCursor = null;
      } else {
        itemsRaw = [];
        nextCursor = null;
      }
      return {'items': itemsRaw.cast<Map<String, dynamic>>(), 'nextCursor': nextCursor};
    }
    throw ApiException('Ошибка получения входящих заявок', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>?> createSession(String name, String friendId) async {
    final res = await http.post(_uri('/sessions'), headers: _headers, body: json.encode({'name': name, 'friendId': friendId})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Ошибка создания сессии', res.statusCode, _extractError(res));
  }

  Future<List<dynamic>> getMySessions() async {
    final res = await http.get(_uri('/sessions'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as List<dynamic>;
    }
    throw ApiException('Ошибка получения сессий', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> updateProfile({String? username, String? customAvatarUrl}) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (customAvatarUrl != null) body['customAvatarUrl'] = customAvatarUrl;
    final res = await http.patch(
      _uri('/auth/profile'),
      headers: _headers,
      body: json.encode(body),
    ).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Ошибка обновления профиля', res.statusCode, _extractError(res));
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) async {
    final res = await http.post(_uri('/sessions/$sessionId/tracks'), headers: _headers, body: json.encode({'tracks': tracks})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return true;
    throw ApiException('Ошибка добавления треков', res.statusCode, _extractError(res));
  }

  Future<bool> rateTrack(String trackId, int rating) async {
    final res = await http.post(_uri('/sessions/tracks/$trackId/rate'), headers: _headers, body: json.encode({'rating': rating})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return true;
    throw ApiException('Ошибка оценки трека', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    final res = await http.patch(_uri('/sessions/$sessionId/end'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as Map<String, dynamic>;
    throw ApiException('Ошибка завершения сессии', res.statusCode, _extractError(res));
  }

  Future<List<dynamic>> getPlaylists() async {
    final res = await http.get(_uri('/spotify/playlists'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Ошибка получения плейлистов', res.statusCode, _extractError(res));
  }

  Future<List<dynamic>> getPlaylistTracks(String playlistId) async {
    final res = await http.get(_uri('/spotify/playlists/$playlistId/tracks'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as List<dynamic>;
    }
    throw ApiException('Ошибка получения треков', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> getSpotifyStatus() async {
    final res = await http.get(_uri('/spotify/status'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Ошибка статуса Spotify', res.statusCode, _extractError(res));
  }

  Future<bool> disconnectSpotify() async {
    final res = await http.post(_uri('/spotify/disconnect'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Ошибка отключения Spotify', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> googleLogin(String idToken) async {
    final res = await http.post(_uri('/auth/google'), headers: _jsonHeaders, body: json.encode({'idToken': idToken})).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Ошибка входа через Google', res.statusCode, _extractError(res));
  }

  Future<bool> playTrack(String uri, {String? deviceId}) async {
  final body = <String, dynamic>{'uri': uri};
  if (deviceId != null) body['deviceId'] = deviceId;
  final res = await http.post(_uri('/spotify/play'),
    headers: _headers,
    body: json.encode(body),
  ).timeout(timeout);
  print('playTrack status: ${res.statusCode}, body: ${res.body}'); // добавь
  return res.statusCode == 200 || res.statusCode == 204;
}

  void setCookie(String cookie) {
    _cookie = cookie;
  }
}