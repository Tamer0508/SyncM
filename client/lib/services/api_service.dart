import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/friend.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'ApiException: $message (${statusCode ?? 'n/a'})';
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
    h['Authorization'] = 'Bearer $_cookie';
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

  Future<User?> getMe() async {
    final res = await http.get(_uri('/auth/me'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return User.fromJson(_decode(res.body) as Map<String, dynamic>);
    if (res.statusCode == 401) return null;
    throw ApiException('Failed to get /auth/me', res.statusCode);
  }

  Future<List<Friend>> searchUsers(String query) async {
    final res = await http.get(_uri('/friends/search?query=${Uri.encodeQueryComponent(query)}'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final data = _decode(res.body) as List<dynamic>;
      return data.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw ApiException('Failed to search users', res.statusCode);
  }

  Future<bool> sendFriendRequest(String receiverId) async {
    final res = await http.post(_uri('/friends/request'), headers: _headers, body: json.encode({'receiverId': receiverId})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return true;
    throw ApiException('Failed to send friend request', res.statusCode);
  }

  Future<bool> acceptRequest(String friendshipId) async {
    final res = await http.patch(_uri('/friends/$friendshipId/accept'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Failed to accept request', res.statusCode);
  }

  Future<bool> deleteRequest(String friendshipId) async {
    final res = await http.delete(_uri('/friends/$friendshipId'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Failed to delete request', res.statusCode);
  }

  Future<bool> deleteFriendByUserId(String friendId) async {
    final res = await http.delete(_uri('/friends/by-user/$friendId'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return true;
    throw ApiException('Failed to delete friend by user id', res.statusCode);
  }

  Future<List<Friend>> getFriends() async {
    final res = await http.get(_uri('/friends'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final data = _decode(res.body) as List<dynamic>;
      return data.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw ApiException('Failed to fetch friends', res.statusCode);
  }

  Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    final res = await http.get(_uri('/friends/requests'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final data = _decode(res.body) as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    }
    throw ApiException('Failed to fetch incoming requests', res.statusCode);
  }

  // Sessions
  Future<Map<String, dynamic>?> createSession(String name, String friendId) async {
    final res = await http.post(_uri('/sessions'), headers: _headers, body: json.encode({'name': name, 'friendId': friendId})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return _decode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to create session', res.statusCode);
  }

  Future<List<dynamic>> getMySessions() async {
    final res = await http.get(_uri('/sessions'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as List<dynamic>;
    }
    throw ApiException('Failed to fetch sessions', res.statusCode);
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) async {
    final res = await http.post(_uri('/sessions/$sessionId/tracks'), headers: _headers, body: json.encode({'tracks': tracks})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return true;
    throw ApiException('Failed to add tracks', res.statusCode);
  }

  Future<bool> rateTrack(String trackId, int rating) async {
    final res = await http.post(_uri('/sessions/tracks/$trackId/rate'), headers: _headers, body: json.encode({'rating': rating})).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return true;
    throw ApiException('Failed to rate track', res.statusCode);
  }

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    final res = await http.patch(_uri('/sessions/$sessionId/end'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as Map<String, dynamic>;
    throw ApiException('Failed to end session', res.statusCode);
  }

  Future<List<dynamic>> getPlaylists() async {
  final userId = _cookie;
  final uri = userId != null 
    ? _uri('/spotify/playlists?userId=$userId')
    : _uri('/spotify/playlists');
  final res = await http.get(uri, headers: _jsonHeaders).timeout(timeout);
  if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
  throw ApiException('Failed to fetch playlists', res.statusCode);
}

  Future<List<dynamic>> getPlaylistTracks(String playlistId) async {
    final res = await http.get(_uri('/spotify/playlists/$playlistId/tracks'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Failed to fetch tracks', res.statusCode);
  }

  void setCookie(String cookie) {
    _cookie = cookie;
  }

  Future<Map<String, dynamic>> googleLogin(String idToken) async {
  final res = await http.post(
    _uri('/auth/google'),
    headers: _jsonHeaders,
    body: json.encode({'idToken': idToken}),
  ).timeout(timeout);
  if (res.statusCode == 200) {
    return _decode(res.body) as Map<String, dynamic>;
  }
  throw ApiException('Failed to login with Google', res.statusCode);
  }
}
