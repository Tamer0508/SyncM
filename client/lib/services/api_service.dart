import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/friend.dart';
import '../utils/retry.dart';
import '../config.dart';

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

/// Запись кэша GET-ответа: значение и момент, после которого оно устаревает.
class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final dynamic value;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class ApiService {
  final String baseUrl;
  final Duration timeout;
  String? _cookie;
  String? getCookie() => _cookie;

  /// Один HTTP-клиент на всё приложение.
  ///
  /// Функции верхнего уровня (http.get и соседи) создают новый клиент на
  /// каждый вызов и закрывают его сразу после ответа: соединение не
  /// переиспользуется, и каждый запрос платит за TCP- и TLS-рукопожатие
  /// заново. С общим клиентом keep-alive работает, и следующий запрос к тому
  /// же хосту уходит по уже открытому соединению.
  static final http.Client _client = http.Client();

  void Function(String token)? _onTokenIssued;
  set onTokenIssued(void Function(String token) cb) => _onTokenIssued = cb;

  static final ApiService _shared = ApiService._internal(
    baseUrl: Config.baseUrl,
    timeout: Config.requestTimeout,
  );

  factory ApiService() => _shared;

  factory ApiService.instance({String? baseUrl, Duration? timeout}) => ApiService._internal(
        baseUrl: baseUrl ?? Config.baseUrl,
        timeout: timeout ?? Config.requestTimeout,
      );

  ApiService._internal({required this.baseUrl, required this.timeout});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};
  final Uuid _uuid = const Uuid();

  static const Object _idempotencyScope = #syncmIdempotencyKey;

  /// Заголовки собираются один раз на токен, а не на каждый запрос: раньше
  /// каждый вызов создавал две Map и заново склеивал строку 'Bearer ...'.
  Map<String, String>? _cachedHeaders;
  String? _cachedHeadersFor;

  Map<String, String> get _headers {
    final cookie = _cookie;
    if (_cachedHeaders != null && _cachedHeadersFor == cookie) {
      return _cachedHeaders!;
    }

    final h = <String, String>{'Content-Type': 'application/json'};
    if (cookie != null && cookie.isNotEmpty) {
      final token = cookie.startsWith('connect.sid=')
          ? cookie.replaceFirst('connect.sid=', '')
          : cookie;
      h['Authorization'] = 'Bearer $token';
    }

    _cachedHeaders = h;
    _cachedHeadersFor = cookie;
    return h;
  }

  // ---------- Дедупликация и краткий кэш GET-запросов ----------

  /// Недавно полученные ответы. Ключ — метод и путь запроса.
  final Map<String, _CacheEntry> _getCache = {};

  /// Запросы, выполняющиеся прямо сейчас. Второй желающий получает тот же
  /// Future, а не второй запрос: прогрев и экран стартуют почти одновременно
  /// и раньше честно дублировали друг друга.
  final Map<String, Future<dynamic>> _inFlight = {};

  /// Сколько ответ считается свежим. Значение намеренно небольшое: задача —
  /// убрать дубли и мгновенно отдать данные при возврате на экран, а не
  /// заменить собой обновление.
  static const Duration _defaultTtl = Duration(seconds: 30);

  Future<T> _cachedGet<T>(
    String key,
    Future<T> Function() request, {
    Duration ttl = _defaultTtl,
    bool refresh = false,
  }) {
    if (!refresh) {
      final hit = _getCache[key];
      if (hit != null && hit.isFresh) return Future<T>.value(hit.value as T);
    }

    // К уже идущему запросу присоединяемся даже при refresh: он стартовал
    // доли секунды назад, и второй такой же ничего нового не принесёт.
    final running = _inFlight[key];
    if (running != null) return running.then((value) => value as T);

    final future = request().then((value) {
      _getCache[key] = _CacheEntry(value, DateTime.now().add(ttl));
      return value;
    }).whenComplete(() {
      // Именно телом, а не стрелкой: Map.remove вернул бы удалённое
      // значение — то есть этот самый Future, — а whenComplete ждёт
      // возвращённый Future. Запрос начинал ждать сам себя и не
      // завершался никогда.
      _inFlight.remove(key);
    });

    _inFlight[key] = future;
    return future;
  }

  /// Сбрасывает кэш по началу ключа. Вызывается после изменений: список
  /// плейлистов после создания нового обязан перечитаться.
  void _invalidate(String prefix) {
    _getCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Полная очистка: смена пользователя не должна показывать чужие данные.
  void clearCache() {
    _getCache.clear();
    _inFlight.clear();
  }

  String _getIdempotencyKey(String operation) {
    final scoped = Zone.current[_idempotencyScope];
    if (scoped is String) return scoped;
    return _uuid.v4();
  }

  Map<String, String> _headersWithIdempotency(String operation) {
    final headers = Map<String, String>.from(_headers);
    headers['Idempotency-Key'] = _getIdempotencyKey(operation);
    return headers;
  }

  static const Set<int> _retryableStatuses = {502, 503, 504};

  bool _shouldRetry(Exception error) {
    if (error is ApiException) {
      // statusCode == null — ответ вообще не получен (обрыв связи).
      if (error.statusCode == null) return true;
      return _retryableStatuses.contains(error.statusCode);
    }
    return true;
  }

  Future<T> _retryMutable<T>(String operation, Future<T> Function() fn) {
    final key = _uuid.v4();
    return runZoned(
      () => retryWithBackoff(fn, shouldRetry: _shouldRetry),
      zoneValues: {_idempotencyScope: key},
    );
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


  Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final res = await _client
        .get(_uri('/friends/blocked'), headers: _headers)
        .timeout(timeout);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body);
    return data is List ? data.whereType<Map>().map(Map<String, dynamic>.from).toList() : [];
  }

  Future<Map<String, dynamic>> getUserActivity(String userId, {bool refresh = false}) {
    return _cachedGet('GET /friends/user/$userId/activity', refresh: refresh, () async {
      final res = await _client
          .get(_uri('/friends/user/$userId/activity'), headers: _headers)
          .timeout(timeout);
      if (res.statusCode != 200) {
        return <String, dynamic>{'history': [], 'likedCount': 0};
      }

      final data = jsonDecode(res.body);
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{'history': [], 'likedCount': 0};
    });
  }

  Future<bool> blockUser(String userId) async {
    final res = await _client
        .post(_uri('/friends/blocked/$userId'),
            headers: _headersWithIdempotency('block:$userId'))
        .timeout(timeout);
    if (res.statusCode == 200) _invalidate('GET /friends');
    return res.statusCode == 200;
  }

  Future<bool> unblockUser(String userId) async {
    final res = await _client
        .delete(_uri('/friends/blocked/$userId'),
            headers: _headersWithIdempotency('unblock:$userId'))
        .timeout(timeout);
    if (res.statusCode == 200) _invalidate('GET /friends');
    return res.statusCode == 200;
  }


  Future<List<Map<String, dynamic>>> getPlayHistory({
    int limit = 50,
    bool refresh = false,
  }) {
    return _cachedGet('GET /auth/history?limit=$limit', refresh: refresh, () async {
      final res = await _client
          .get(_uri('/auth/history?limit=$limit'), headers: _headers)
          .timeout(timeout);
      if (res.statusCode != 200) return <Map<String, dynamic>>[];
      final data = jsonDecode(res.body);
      return data is List
          ? data.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
    });
  }

  Future<bool> clearPlayHistory() async {
    final res = await _client
        .delete(_uri('/auth/history'),
            headers: _headersWithIdempotency('clear-history'))
        .timeout(timeout);
    if (res.statusCode == 200) _invalidate('GET /auth/history');
    return res.statusCode == 200;
  }

  Future<void> deleteAccount() async {
    final res = await _client
        .delete(_uri('/auth/account'), headers: _headers)
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw ApiException(
        'Не удалось удалить аккаунт',
        res.statusCode,
        _extractError(res),
      );
    }

    _cookie = null;
    clearCache();
  }

  Future<void> logout() async {
    try {
      await _client.get(_uri('/auth/logout'), headers: _headers).timeout(timeout);
    } finally {
      _cookie = null;
      clearCache();
    }
  }

  Future<User?> getMe() async {
    final needToken = (_cookie == null || _cookie!.isEmpty) ? '?needToken=1' : '';
    final res = await _client.get(_uri('/auth/me$needToken'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final data = _decode(res.body) as Map<String, dynamic>;
      final issued = data['authToken'] as String?;
      if (issued != null && issued.isNotEmpty) {
        _cookie = issued;
        _onTokenIssued?.call(issued);
      }
      return User.fromJson(data);
    }
    if (res.statusCode == 401) return null;
    throw ApiException('Failed to get /auth/me', res.statusCode, _extractError(res));
  }

  Future<String> createSpotifyLinkIntent({String? returnTo}) async {
    final res = await _client.post(
      _uri('/auth/spotify/link-intent'),
      headers: _headers,
      body: json.encode({'returnTo': returnTo}),
    ).timeout(timeout);
    if (res.statusCode != 200) {
      throw ApiException('Не удалось начать привязку Spotify', res.statusCode, _extractError(res));
    }
    return (_decode(res.body) as Map<String, dynamic>)['state'] as String;
  }

  Future<Map<String, dynamic>> updatePrivacySettings(Map<String, bool> settings) async {
    const operation = 'updatePrivacySettings';
    return _retryMutable(operation, () async {
      final res = await _client.patch(
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
    final res = await _client.get(_uri('/friends/search?query=${Uri.encodeQueryComponent(query)}'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) {
      final data = _decode(res.body) as List<dynamic>;
      return data.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw ApiException('Ошибка поиска', res.statusCode, _extractError(res));
  }

  Future<Map<String, dynamic>> getUserProfile(String userId, {bool refresh = false}) {
    return _cachedGet('GET /friends/user/$userId', refresh: refresh, () async {
      final res = await _client.get(_uri('/friends/user/$userId'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body) as Map<String, dynamic>;
      }
      throw ApiException('Ошибка загрузки профиля', res.statusCode, _extractError(res));
    });
  }

  Future<bool> sendFriendRequest(String receiverId) async {
    final operation = 'sendFriendRequest:$receiverId';
    return _retryMutable(operation, () async {
      final res = await _client.post(
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
      final res = await _client.patch(
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
      final res = await _client.delete(
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
      final res = await _client.delete(
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

    final res = await _client.get(uri, headers: _headers).timeout(timeout);
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

    final res = await _client.get(uri, headers: _headers).timeout(timeout);
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
      final res = await _client.post(
        _uri('/sessions'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'name': name, 'friendId': friendId}),
      ).timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        _invalidate('GET /sessions');
        return _decode(res.body);
      }
      throw ApiException('Ошибка создания сессии', res.statusCode, _extractError(res));
    });
  }

  /// Состояние сессий приходит по сокету, поэтому кэш здесь живёт секунды:
  /// он схлопывает совпавшие по времени запросы (прогрев и экран стартуют
  /// почти одновременно), но не заменяет собой обновление по событию.
  static const Duration _realtimeTtl = Duration(seconds: 3);

  Future<List<dynamic>> getMySessions() {
    return _cachedGet('GET /sessions', ttl: _realtimeTtl, () async {
      final res = await _client.get(_uri('/sessions'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body) as List<dynamic>;
      }
      throw ApiException('Ошибка получения сессий', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> updateProfile({String? username, String? customAvatarUrl}) async {
    final operation = 'updateProfile:${username ?? ''}:${customAvatarUrl ?? ''}';
    return _retryMutable(operation, () async {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (customAvatarUrl != null) body['customAvatarUrl'] = customAvatarUrl;
      final res = await _client.patch(
        _uri('/auth/profile'),
        headers: _headersWithIdempotency(operation),
        body: json.encode(body),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        _invalidate('GET /friends/user/');
        return _decode(res.body);
      }
      throw ApiException('Ошибка обновления профиля', res.statusCode, _extractError(res));
    });
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) async {
    final operation = 'addTracks:$sessionId';
    return _retryMutable(operation, () async {
      final res = await _client.post(
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
      final res = await _client.post(
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
      final res = await _client.patch(
        _uri('/sessions/$sessionId/end'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        _invalidate('GET /sessions');
        return _decode(res.body);
      }
      throw ApiException('Ошибка завершения сессии', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getPlaylists({bool refresh = false}) {
    return _cachedGet('GET /spotify/playlists', refresh: refresh, () async {
      final res = await _client.get(_uri('/spotify/playlists'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
      throw ApiException('Ошибка получения плейлистов', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getPlaylistTracks(String playlistId, {bool refresh = false}) {
    return _cachedGet('GET /spotify/playlists/$playlistId/tracks', refresh: refresh, () async {
      final res = await _client.get(_uri('/spotify/playlists/$playlistId/tracks'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body) as List<dynamic>;
      }
      throw ApiException('Ошибка получения треков', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> getSpotifyStatus({bool refresh = false}) {
    return _cachedGet('GET /spotify/status', refresh: refresh, () async {
      final res = await _client.get(_uri('/spotify/status'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        return _decode(res.body) as Map<String, dynamic>;
      }
      throw ApiException('Ошибка статуса Spotify', res.statusCode, _extractError(res));
    });
  }

  Future<bool> disconnectSpotify() async {
    const operation = 'disconnectSpotify';
    return _retryMutable(operation, () async {
      final res = await _client.post(
        _uri('/spotify/disconnect'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        _invalidate('GET /spotify');
        return true;
      }
      throw ApiException('Ошибка отключения Spotify', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> googleLogin(String idToken) async {
    const operation = 'googleLogin';
    return _retryMutable(operation, () async {
      final res = await _client.post(
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


  // ---------- ИСПРАВЛЕННЫЙ МЕТОД (без dart:html) ----------
  Future<Map<String, dynamic>> uploadAvatar(Uint8List bytes, String fileName) async {
    const operation = 'uploadAvatar';
    return _retryMutable(operation, () async {
      final uri = _uri('/auth/avatar');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = _headers['Authorization'] ?? '';
      request.headers['Idempotency-Key'] = _getIdempotencyKey(operation);
      request.files.add(http.MultipartFile.fromBytes('avatar', bytes, filename: fileName));
      final streamed = await request.send().timeout(Config.uploadTimeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        _invalidate('GET /friends/user/');
        return _decode(res.body);
      }
      throw ApiException('Ошибка загрузки аватарки', res.statusCode, _extractError(res));
    });
  }

  Future<Map<String, dynamic>> createCustomPlaylist(String name, {String? description, String? imageUrl}) async {
    final operation = 'createCustomPlaylist:$name:${description ?? ''}:${imageUrl ?? ''}';
    return _retryMutable(operation, () async {
      final res = await _client.post(
        _uri('/playlists/custom'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'name': name, 'description': description, 'imageUrl': imageUrl}),
      ).timeout(timeout);
      if (res.statusCode == 201) {
        _invalidate('GET /playlists');
        return _decode(res.body);
      }
      throw ApiException('Ошибка создания плейлиста', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getMyPlaylists({bool refresh = false}) {
    return _cachedGet('GET /playlists', refresh: refresh, () async {
      final res = await _client.get(_uri('/playlists'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
      throw ApiException('Ошибка получения плейлистов', res.statusCode, _extractError(res));
    });
  }

  Future<void> deletePlaylist(String playlistId) async {
    final operation = 'deletePlaylist:$playlistId';
    return _retryMutable(operation, () async {
      final res = await _client.delete(
        _uri('/playlists/$playlistId'),
        headers: _headersWithIdempotency(operation),
      ).timeout(timeout);
      if (res.statusCode != 200) {
        throw ApiException('Ошибка удаления', res.statusCode, _extractError(res));
      }
      _invalidate('GET /playlists');
    });
  }

  Future<Map<String, dynamic>> addTrackToPlaylist(String playlistId, String trackUri, String trackName, String artistName, {int? durationMs}) async {
    final operation = 'addTrackToPlaylist:$playlistId:$trackUri';
    return _retryMutable(operation, () async {
      final res = await _client.post(
        _uri('/playlists/$playlistId/tracks'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({
          'trackUri': trackUri,
          'trackName': trackName,
          'artistName': artistName,
          'durationMs': durationMs,
        }),
      ).timeout(timeout);
      if (res.statusCode == 201) {
        _invalidate('GET /playlists/$playlistId/tracks');
        return _decode(res.body) as Map<String, dynamic>;
      }
      throw ApiException('Ошибка добавления трека', res.statusCode, _extractError(res));
    });
  }

  // Returns `null` when access is forbidden (HTTP 403) so the UI can
  // display a soft placeholder instead of treating it as an error.
  Future<List<dynamic>?> getPlaylistTracksById(String playlistId, {bool refresh = false}) {
    return _cachedGet('GET /playlists/$playlistId/tracks', refresh: refresh, () async {
      final res = await _client.get(_uri('/playlists/$playlistId/tracks'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
      if (res.statusCode == 403) return null;
      throw ApiException('Ошибка загрузки треков', res.statusCode, _extractError(res));
    });
  }

  Future<bool> toggleLike(String spotifyUri, String trackName, String artistName) async {
    final operation = 'toggleLike:$spotifyUri';
    return _retryMutable(operation, () async {
      final res = await _client.post(
        _uri('/playlists/liked/toggle'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({
          'spotifyUri': spotifyUri,
          'trackName': trackName,
          'artistName': artistName,
        }),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        _invalidate('GET /playlists/liked');
        return (_decode(res.body) as Map)['liked'] == true;
      }
      throw ApiException('Ошибка лайка', res.statusCode, _extractError(res));
    });
  }

  Future<List<dynamic>> getLikedTracks({bool refresh = false}) {
    return _cachedGet('GET /playlists/liked', refresh: refresh, () async {
      final res = await _client.get(_uri('/playlists/liked'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
      throw ApiException('Ошибка загрузки избранного', res.statusCode, _extractError(res));
    });
  }

  Future<void> logPlay(String spotifyUri, String trackName, String artistName) async {
    try {
      await _retryMutable('logPlay:$spotifyUri', () async {
        final res = await _client.post(
          _uri('/playlists/history'),
          headers: _headersWithIdempotency('logPlay:$spotifyUri'),
          body: json.encode({
            'spotifyUri': spotifyUri,
            'trackName': trackName,
            'artistName': artistName,
          }),
        ).timeout(timeout);
        _invalidate('GET /auth/history');
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
      return await _client.post(
        _uri('/spotify/play'),
        headers: _headersWithIdempotency(operation),
        body: json.encode(body),
      ).timeout(timeout);
    });
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<void> pausePlayback() async {
    await _retryMutable('pausePlayback', () async {
      return await _client.put(
        _uri('/spotify/pause'),
        headers: _headersWithIdempotency('pausePlayback'),
      ).timeout(timeout);
    });
  }

  Future<void> resumePlayback() async {
    await _retryMutable('resumePlayback', () async {
      return await _client.put(
        _uri('/spotify/resume'),
        headers: _headersWithIdempotency('resumePlayback'),
      ).timeout(timeout);
    });
  }

  Future<void> skipToNext() async {
    await _retryMutable('skipToNext', () async {
      return await _client.post(
        _uri('/spotify/next'),
        headers: _headersWithIdempotency('skipToNext'),
      ).timeout(timeout);
    });
  }

  Future<void> skipToPrevious() async {
    await _retryMutable('skipToPrevious', () async {
      return await _client.post(
        _uri('/spotify/previous'),
        headers: _headersWithIdempotency('skipToPrevious'),
      ).timeout(timeout);
    });
  }

  Future<void> seekToPosition(int ms) async {
    final res = await _client.put(_uri('/spotify/seek?position_ms=$ms'), headers: _headers).timeout(timeout);
    if (res.statusCode != 200) {
      throw ApiException('Ошибка перемотки', res.statusCode, _decode(res.body) is Map ? (_decode(res.body) as Map)['error']?.toString() : null);
    }
  }

  Future<void> setVolume(int percent) async {
    final clamped = percent.clamp(0, 100);
    await _client.put(_uri('/spotify/volume?volume_percent=$clamped'), headers: _headers).timeout(timeout);
  }

  Future<List<dynamic>> getDevices() async {
    final res = await _client.get(_uri('/spotify/devices'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
    throw ApiException('Ошибка получения устройств', res.statusCode);
  }

  Future<List<dynamic>> getMyInvites() {
    return _cachedGet('GET /sessions/invites', ttl: _realtimeTtl, () async {
      final res = await _client.get(_uri('/sessions/invites'), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) return _decode(res.body) as List<dynamic>;
      return <dynamic>[];
    });
  }

  Future<Map<String, dynamic>?> respondToInvite(String sessionId, bool accept) async {
    final operation = 'respondToInvite:$sessionId:$accept';
    return _retryMutable(operation, () async {
      final res = await _client.post(
        _uri('/sessions/$sessionId/respond'),
        headers: _headersWithIdempotency(operation),
        body: json.encode({'accept': accept}),
      ).timeout(timeout);
      if (res.statusCode == 200) {
        _invalidate('GET /sessions');
        return _decode(res.body) as Map<String, dynamic>;
      }
      throw ApiException('Ошибка ответа на приглашение', res.statusCode, _extractError(res));
    });
  }

  Future<bool> setShuffle(bool state) async {
    final uri = Uri.parse('$baseUrl/spotify/shuffle?state=$state');
    try {
      final response = await _client.put(uri, headers: _headers);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        debugPrint('[ApiService] setShuffle failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[ApiService] setShuffle error: $e');
      return false;
    }
  }

  Future<bool> setRepeatMode(String mode) async {
    final uri = Uri.parse('$baseUrl/spotify/repeat?state=$mode');
    try {
      final response = await _client.put(uri, headers: _headers);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        debugPrint('[ApiService] setRepeatMode failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[ApiService] setRepeatMode error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getPlayerState() async {
    final res = await _client.get(_uri('/spotify/player'), headers: _headers).timeout(timeout);
    if (res.statusCode == 200) return _decode(res.body) as Map<String, dynamic>;
    return null;
  }

  void setCookie(String cookie) {
    // Сменился пользователь — кэш прошлого показывать нельзя.
    if (_cookie != cookie) clearCache();
    _cookie = cookie;
  }
}