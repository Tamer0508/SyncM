import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/friend.dart';
import '../utils/retry.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? serverMessage;

  ApiException(this.message, [this.statusCode, this.serverMessage]);

  String get userMessage => serverMessage ?? message;

  bool get suppressUiNotification => statusCode == 429 || statusCode == 500;

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
  final Uuid _uuid = const Uuid();
  final Map<String, String> _idempotencyKeys = {};

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

  String _getIdempotencyKey(String operation) =>
      _idempotencyKeys.putIfAbsent(operation, () => _uuid.v4());

  Map<String, String> _headersWithIdempotency(String operation) {
    final headers = Map<String, String>.from(_headers);
    headers['Idempotency-Key'] = _getIdempotencyKey(operation);
    return headers;
  }

  bool _shouldRetry(Exception error) {
    if (error is ApiException) {
      return error.statusCode == null || (error.statusCode ?? 0) >= 500;
    }
    return true;
  }

  Future<T> _retryMutable<T>(String operation, Future<T> Function() fn) async {
    try {
      final result = await retryWithBackoff(
        fn,
        shouldRetry: _shouldRetry,
      );
      _idempotencyKeys.remove(operation);
      return result;
    } catch (e) {
      rethrow;
    }
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

  // ---------- Все остальные методы без изменений (только не трогал) ----------

  Future<User?> getMe() async {
    final res = await http.get(_uri('/auth/me'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return User.fromJson(_decode(res.body) as Map<String, dynamic>);
    if (res.statusCode == 401) return null;
    throw ApiException('Failed to get /auth/me', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> updatePrivacySettings(Map<String, bool> settings) async {
    const operation = 'updatePrivacySettings';
    return _retryMutable(operation, () async {
      final res = await http.patch(
        _uri('/auth/settings'),
        headers: _headersWithIdempotency(operation),
        body: json.encode(settings),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body);
      }
      throw ApiException('Ошибка обновления настроек', res.statusCode, _extractError(res));
    });
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
      return _decode(res.body);
    }
    throw ApiException('Ошибка загрузки профиля', res.statusCode, _extractError(res));
  }

  Future<bool> sendFriendRequest(String receiverId) async {
    final operation = 'sendFriendRequest:$receiverId';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/friends/request'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'receiverId': receiverId}),
      ).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) return true;
      throw ApiException('Ошибка отправки заявки', res.statusCode, _extractError(res));
    });
  }

  Future<bool> acceptRequest(String friendshipId) async {
    final operation = 'acceptRequest:$friendshipId';
    return _retryMutable(operation, () async {
      final res = await http.patch(
        _uri('/friends/$friendshipId/accept'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) return true;
      throw ApiException('Ошибка принятия заявки', res.statusCode, _extractError(res));
    });
  }

  Future<bool> deleteRequest(String friendshipId) async {
    final operation = 'deleteRequest:$friendshipId';
    return _retryMutable(operation, () async {
      final res = await http.delete(
        _uri('/friends/$friendshipId'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) return true;
      throw ApiException('Ошибка удаления заявки', res.statusCode, _extractError(res));
    });
  }

  Future<bool> deleteFriendByUserId(String friendId) async {
    final operation = 'deleteFriendByUserId:$friendId';
    return _retryMutable(operation, () async {
      final res = await http.delete(
        _uri('/friends/by-user/$friendId'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) return true;
      throw ApiException('Ошибка удаления друга', res.statusCode, _extractError(res));
    });
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
        itemsRaw = decoded;
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
        itemsRaw = decoded;
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
    final operation = 'createSession:$name:$friendId';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/sessions'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'name': name, 'friendId': friendId}),
      ).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return _decode(res.body);
      }
      throw ApiException('Ошибка создания сессии', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getMySessions() async {
    final res = await http.get(_uri('/sessions'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      return _decode(res.body) as List<dynamic>;
    }
    throw ApiException('Ошибка получения сессий', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> updateProfile({String? username, String? customAvatarUrl}) async {
    final operation = 'updateProfile:${username ?? ''}:${customAvatarUrl ?? ''}';
    return _retryMutable(operation, () async {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (customAvatarUrl != null) body['customAvatarUrl'] = customAvatarUrl;
      final res = await http.patch(
        _uri('/auth/profile'),
        headers: _headersWithIdempotency(operation),
        body: json.encode(body),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body);
      }
      throw ApiException('Ошибка обновления профиля', res.statusCode, _extractError(res));
    });
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) async {
    final operation = 'addTracks:$sessionId';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/sessions/$sessionId/tracks'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'tracks': tracks}),
      ).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) return true;
      throw ApiException('Ошибка добавления треков', res.statusCode, _extractError(res));
    });
  }

  Future<bool> rateTrack(String trackId, int rating) async {
    final operation = 'rateTrack:$trackId';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/sessions/tracks/$trackId/rate'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'rating': rating}),
      ).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) return true;
      throw ApiException('Ошибка оценки трека', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    final operation = 'endSession:$sessionId';
    return _retryMutable(operation, () async {
      final res = await http.patch(
        _uri('/sessions/$sessionId/end'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body);
      throw ApiException('Ошибка завершения сессии', res.statusCode, _extractError(res));
    });
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
      return _decode(res.body);
    }
    throw ApiException('Ошибка статуса Spotify', res.statusCode, _extractError(res));
  }

  Future<bool> disconnectSpotify() async {
    const operation = 'disconnectSpotify';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/spotify/disconnect'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) return true;
      throw ApiException('Ошибка отключения Spotify', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> googleLogin(String idToken) async {
    const operation = 'googleLogin';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/auth/google'),
        headers: _jsonHeaders..['Idempotency-Key'] = _getIdempotencyKey(operation),
        body: json.encode({'idToken': idToken}),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body);
      }
      throw ApiException('Ошибка входа через Google', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>?> getSession(String sessionId) async {
    final response = await http.get(_uri('/sessions/$sessionId'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  // ---------- ИСПРАВЛЕННЫЙ МЕТОД (без dart:html) ----------
  Future<Map<String, dynamic>> uploadAvatar(Uint8List bytes, String fileName) async {
    const operation = 'uploadAvatar';
    return _retryMutable(operation, () async {
      final uri = _uri('/auth/avatar');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = _headers['Authorization'] ?? '';
      request.headers['Idempotency-Key'] = _getIdempotencyKey(operation);
      request.files.add(http.MultipartFile.fromBytes('avatar', bytes, filename: fileName));
      final streamed = await request.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        return _decode(res.body);
      }
      throw ApiException('Ошибка загрузки аватарки', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> createCustomPlaylist(String name, {String? description, String? imageUrl}) async {
    final operation = 'createCustomPlaylist:$name:${description ?? ''}:${imageUrl ?? ''}';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/playlists/custom'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'name': name, 'description': description, 'imageUrl': imageUrl}),
      ).timeout(timeout);
      if (res.statusCode == 201) return _decode(res.body);
      throw ApiException('Ошибка создания плейлиста', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getMyPlaylists() async {
    final res = await http.get(_uri('/playlists'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Ошибка получения плейлистов', res.statusCode, _extractError(res));
  }

  Future<void> deletePlaylist(String playlistId) async {
    final operation = 'deletePlaylist:$playlistId';
    return _retryMutable(operation, () async {
      final res = await http.delete(
        _uri('/playlists/$playlistId'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode != 200) throw ApiException('Ошибка удаления', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> addTrackToPlaylist(String playlistId, String trackUri, String trackName, String artistName, {int? durationMs}) async {
    final operation = 'addTrackToPlaylist:$playlistId:$trackUri';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/playlists/$playlistId/tracks'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({
          'trackUri': trackUri,
          'trackName': trackName,
          'artistName': artistName,
          'durationMs': durationMs,
        }),
      ).timeout(timeout);
      if (res.statusCode == 201) return _decode(res.body) as Map<String, dynamic>;
      throw ApiException('Ошибка добавления трека', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getPlaylistTracksById(String playlistId) async {
    final res = await http.get(_uri('/playlists/$playlistId/tracks'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Ошибка загрузки треков', res.statusCode, _extractError(res));
  }

  Future<bool> toggleLike(String spotifyUri, String trackName, String artistName) async {
    final operation = 'toggleLike:$spotifyUri';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/playlists/liked/toggle'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({
          'spotifyUri': spotifyUri,
          'trackName': trackName,
          'artistName': artistName,
        }),
      ).timeout(timeout);
      if (res.statusCode == 200) return (_decode(res.body) as Map)['liked'] == true;
      throw ApiException('Ошибка лайка', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getLikedTracks() async {
    final res = await http.get(_uri('/playlists/liked'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Ошибка загрузки избранного', res.statusCode, _extractError(res));
  }

  Future<void> logPlay(String spotifyUri, String trackName, String artistName) async {
    try {
      await _retryMutable('logPlay:$spotifyUri', () async {
        final res = await http.post(
          _uri('/playlists/history'),
          headers: _headersWithIdempotency('logPlay:$spotifyUri'),
          body: json.encode({
            'spotifyUri': spotifyUri,
            'trackName': trackName,
            'artistName': artistName,
          }),
        ).timeout(timeout);
        return res;
      });
    } catch (_) {
      /* тихо игнорируем */
    }
  }

  Future<bool> playTrack(String uri, {String? deviceId, String? contextUri, int? offset}) async {
    final operation = 'playTrack:$uri:${contextUri ?? ''}:${deviceId ?? ''}:$offset';
    final body = <String, dynamic>{};
    if (contextUri != null) {
      body['contextUri'] = contextUri;
      if (offset != null) body['offset'] = offset;
    } else {
      body['uri'] = uri;
    }
    if (deviceId != null) body['deviceId'] = deviceId;
    final res = await _retryMutable(operation, () async {
      return await http.post(
        _uri('/spotify/play'),
        headers: _headersWithIdempotency(operation),
        body: json.encode(body),
      ).timeout(timeout);
    });
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<void> pausePlayback() async {
    await _retryMutable('pausePlayback', () async {
      return await http.put(
        _uri('/spotify/pause'),
        headers: _headersWithIdempotency('pausePlayback'),
      ).timeout(timeout);
    });
  }

  Future<void> resumePlayback() async {
    await _retryMutable('resumePlayback', () async {
      return await http.put(
        _uri('/spotify/resume'),
        headers: _headersWithIdempotency('resumePlayback'),
      ).timeout(timeout);
    });
  }

  Future<void> skipToNext() async {
    await _retryMutable('skipToNext', () async {
      return await http.post(
        _uri('/spotify/next'),
        headers: _headersWithIdempotency('skipToNext'),
      ).timeout(timeout);
    });
  }

  Future<void> skipToPrevious() async {
    await http.post(_uri('/spotify/previous'), headers: _headers).timeout(timeout);
  }

  Future<void> seekToPosition(int ms) async {
    final res = await http.put(_uri('/spotify/seek?position_ms=$ms'), headers: _headers).timeout(timeout);
    if (res.statusCode != 200) {
      throw ApiException('Ошибка перемотки', res.statusCode, _decode(res.body) is Map ? (_decode(res.body) as Map)['error']?.toString() : null);
    }
  }

  Future<void> setVolume(int percent) async {
    final clamped = percent.clamp(0, 100);
    await http.put(_uri('/spotify/volume?volume_percent=$clamped'), headers: _headers).timeout(timeout);
  }

  Future<List<dynamic>> getDevices() async {
    final res = await http.get(_uri('/spotify/devices'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Ошибка получения устройств', res.statusCode);
  }

  Future<List<dynamic>> getMyInvites() async {
    final res = await http.get(_uri('/sessions/invites'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    return [];
  }

  Future<Map<String, dynamic>?> respondToInvite(String sessionId, bool accept) async {
    final operation = 'respondToInvite:$sessionId:$accept';
    return _retryMutable(operation, () async {
      final res = await http.post(
        _uri('/sessions/$sessionId/respond'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'accept': accept}),
      ).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body) as Map<String, dynamic>;
      throw ApiException('Ошибка ответа на приглашение', res.statusCode, _extractError(res));
    });
  }

  Future<bool> setShuffle(bool state) async {
    final uri = Uri.parse('$baseUrl/spotify/shuffle?state=$state');
    try {
      final response = await http.put(uri, headers: _headers);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print('[ApiService] setShuffle failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('[ApiService] setShuffle error: $e');
      return false;
    }
  }

  Future<bool> setRepeatMode(String mode) async {
    final uri = Uri.parse('$baseUrl/spotify/repeat?state=$mode');
    try {
      final response = await http.put(uri, headers: _headers);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print('[ApiService] setRepeatMode failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('[ApiService] setRepeatMode error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getPlayerState() async {
    final res = await http.get(_uri('/spotify/player'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as Map<String, dynamic>;
    return null;
  }

  void setCookie(String cookie) {
    _cookie = cookie;
  }
}