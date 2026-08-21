import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:palette_generator/palette_generator.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_phase.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/session_foreground_service.dart';
import '../utils/local_store.dart';

typedef SessionTracksCallback = void Function(Map<String, dynamic> data);
typedef SessionPlaybackCallback = void Function(Map<String, dynamic> track);

class PlaybackProvider extends ChangeNotifier {
  ApiService? _apiService;
  ApiService? get apiService => _apiService;
  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _isWeb => kIsWeb;

  Map<String, dynamic>? _currentTrack;
  bool _isPlaying = false;
  bool _isConnected = false;
  int _durationMs = 0;
  int _positionMs = 0;
  Uint8List? _currentImageBytes;
  String? _lastImageUri;
  Timer? _pollingTimer;
  Timer? _trackChangeTimer;
  bool _isAdvancingQueue = false;
  int _lastActivePositionMs = 0;
  int _lastActiveDurationMs = 0;
  int? _preMuteVolume;
  int _audioLatencyMs = 0;
  int _driftStrikes = 0;
  int get audioLatencyMs => _audioLatencyMs;
  static const String _kAudioLatencyKey = 'audio_latency_ms';

  SocketService? _socketService;

  final List<SocketSubscription> _sessionSubscriptions = [];

  String? _currentSessionId;
  String? _userId;
  String? _preparedTrackId;
  bool _isReadySent = false;
  bool _isSeekingFromRemote = false;
  bool _isSessionSeeking = false;
  bool _isSkipping = false;
  DateTime? _lastToggle;

  bool _shuffleActive = false;
  String _repeatMode = 'off';

  String? _currentPlaylistId;
  List<dynamic>? _currentPlaylistTracks;
  bool _suppressAutoCorrection = false;

  String? _pendingTrackUri;
  DateTime? _pendingSince;

  static const _pendingTrackTimeout = Duration(milliseconds: 1500);

  void _markPendingTrack(String? uri) {
    _pendingTrackUri = uri;
    _pendingSince = uri == null ? null : DateTime.now();

    if (uri != null) {
      _currentImageBytes = null;
      _lastImageUri = null;
      notifyListeners();
    }
  }

  bool _shouldIgnoreSdkTrack(String incomingUri) {
    if (_sessionMode) return false;

    final pending = _pendingTrackUri;
    if (pending == null) return false;

    if (incomingUri == pending) {
      _markPendingTrack(null);
      return false;
    }

    final since = _pendingSince;
    if (since != null && DateTime.now().difference(since) > _pendingTrackTimeout) {
      _markPendingTrack(null);
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _sessionQueue = [];
  int _sessionQueueIndex = -1;
  bool _sessionMode = false;
  bool _sessionPaused = false;
  bool _isHost = false;
  bool _isRemoteSync = false;
  bool _queueEnded = false;
  int _syncAnchorPositionMs = 0;
  int? _syncAnchorServerTime;
  SessionTracksCallback? onTracksAdded;
  SessionPlaybackCallback? onSessionPlaybackStarted;
  void Function(String message)? onPrepareError;

  List<Map<String, dynamic>> get sessionQueue => List.unmodifiable(_sessionQueue);
  int get sessionQueueIndex => _sessionQueueIndex;
  bool get sessionMode => _sessionMode;
  bool get queueEnded => _queueEnded;

  Map<String, dynamic>? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;

  bool get isConnected => _isConnected;
  int get durationMs => _durationMs;

  int get positionMs {
    if (_sessionMode &&
        _isPlaying &&
        !_sessionPaused &&
        _syncAnchorServerTime != null) {
      final nowServer = _socketService?.serverNow();
      if (nowServer != null) {
        final int elapsed = nowServer - _syncAnchorServerTime!;
        final int pos = _syncAnchorPositionMs + elapsed;
        if (_durationMs > 0) return pos.clamp(0, _durationMs);
        return pos < 0 ? 0 : pos;
      }
    }
    if (_isPlaying && _positionAnchorAt != null) {
      final elapsed = DateTime.now().difference(_positionAnchorAt!).inMilliseconds;
      final pos = _positionMs + elapsed;
      if (_durationMs > 0) return pos.clamp(0, _durationMs);
      return pos;
    }

    return _positionMs;
  }

  DateTime? _positionAnchorAt;
  Uint8List? get currentImageBytes => _currentImageBytes;

  bool get isSyncing =>
      _sessionMode &&
      (_isSessionSeeking ||
          _isAdvancingQueue ||
          (_preparedTrackId != null && !_isReadySent));

  SyncPhase get syncPhase {
    if (!_sessionMode || _currentSessionId == null) return SyncPhase.idle;
    if (isSyncing) return SyncPhase.drifting;
    if (_sessionPaused || !_isPlaying) return SyncPhase.waiting;
    return SyncPhase.synced;
  }

  bool get shuffleActive => _shuffleActive;
  String get repeatMode => _repeatMode;
  bool get repeatActive => _repeatMode != 'off';

  final Map<String, PaletteGenerator> _paletteCache = {};
  Map<String, PaletteGenerator> get paletteCache => _paletteCache;

  static const _clientId = '809ce8e069a64cb5970c20e356024786';
  static const _redirectUrl = 'syncm://callback';


  void setApiService(ApiService api) {
    _apiService = api;
    _loadAudioLatency();
  }

  Future<void> _loadAudioLatency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _audioLatencyMs = prefs.getInt(_kAudioLatencyKey) ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('[SyncM] Не удалось загрузить калибровку задержки: $e');
    }
  }

  Future<void> setAudioLatency(int ms) async {
    _audioLatencyMs = ms.clamp(0, 1000);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAudioLatencyKey, _audioLatencyMs);
    } catch (e) {
      debugPrint('[SyncM] Не удалось сохранить калибровку задержки: $e');
    }
  }

  static Map<String, dynamic> mapSessionTrack(dynamic raw, int index) {
    final t = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    String artist = (t['artistName'] ?? t['artist'] ?? '') as String;
    if (artist.isEmpty && t['artists'] is List) {
      artist = (t['artists'] as List)
          .map((a) => a is Map ? (a['name'] ?? '') : '$a')
          .where((name) => '$name'.isNotEmpty)
          .join(', ');
    }

    String? imageUrl = t['imageUrl'] as String?;
    if (imageUrl == null || imageUrl.isEmpty) {
      final images = (t['album'] is Map ? t['album']['images'] : null);
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map) imageUrl = first['url'] as String?;
      }
    }

    return {
      'id': t['id'],
      'uri': t['spotifyUri'] ?? t['uri'],
      'title': t['trackName'] ?? t['title'] ?? t['name'] ?? '',
      'artist': artist,
      'imageUrl': imageUrl,
      'durationMs': t['durationMs'] ?? t['duration_ms'],
      'index': index,
    };
  }

  void setSessionQueue(List<dynamic> tracks) {
    _sessionQueue = tracks.asMap().entries
        .map((e) => mapSessionTrack(e.value, e.key))
        .where((t) => (t['uri'] as String?)?.isNotEmpty == true)
        .toList();
    notifyListeners();
  }

  Future<void> playSessionTrack(int index, {bool syncToSession = true, int? positionMs}) async {
    if (index < 0 || index >= _sessionQueue.length) return;

    _sessionMode = true;
    _queueEnded = false;
    _sessionQueueIndex = index;
    final track = Map<String, dynamic>.from(_sessionQueue[index]);

    _positionMs = positionMs ?? 0;
    _positionAnchorAt = DateTime.now();
    _durationMs = (track['durationMs'] as num?)?.toInt() ?? 0;
    notifyListeners();

    if (syncToSession && !_isRemoteSync && _currentSessionId != null) {
      final trackId = (track['uri'] as String).split(':').last;
      _socketService?.emit('session_prepare', {
        'sessionId': _currentSessionId,
        'trackId': trackId,
        'durationMs': track['durationMs'],
      });
      onSessionPlaybackStarted?.call(track);
      return;
    }

    await playTrack(track, positionMs: positionMs, fromSession: true);
    onSessionPlaybackStarted?.call(track);
  }

  Future<void> handleSessionPlayEvent(Map<String, dynamic> data) async {
    _isRemoteSync = true;
    try {
      if (data['tracks'] is List) {
        setSessionQueue(data['tracks'] as List);
      }
      final index = (data['trackIndex'] as num?)?.toInt() ?? 0;
      await playSessionTrack(index, syncToSession: false);
      onSessionPlaybackStarted?.call(_sessionQueue[index]);
    } finally {
      _isRemoteSync = false;
    }
  }

  Future<void> _advanceSessionQueue() async {
    if (!_sessionMode || _sessionQueue.isEmpty) return;
    try {
      final next = _sessionQueueIndex + 1;
      if (next < _sessionQueue.length) {
        _sessionQueueIndex = next;
        _queueEnded = false;
        final track = Map<String, dynamic>.from(_sessionQueue[next]);
        _positionMs = 0;
        _positionAnchorAt = DateTime.now();
        _durationMs = (track['durationMs'] as num?)?.toInt() ?? 0;
        notifyListeners();

        final trackId = (track['uri'] as String).split(':').last;
        _socketService?.emit('session_advance', {
          'sessionId': _currentSessionId,
          'trackId': trackId,
          'durationMs': track['durationMs'],
        });
        _scheduleAdvanceFlagReset();
      } else {
        await _stopAtQueueEnd();
        _isAdvancingQueue = false;
      }
    } catch (e) {
      debugPrint('[SyncM] _advanceSessionQueue error: $e');
      _isAdvancingQueue = false;
    }
  }

  Timer? _advanceResetTimer;
  void _scheduleAdvanceFlagReset() {
    _advanceResetTimer?.cancel();

    _advanceResetTimer = Timer(const Duration(milliseconds: 3500), () {
      _isAdvancingQueue = false;
    });
  }

  Future<void> _stopAtQueueEnd() async {
    _queueEnded = true;
    _isPlaying = false;
    _sessionPaused = true;
    await _restoreVolumeIfMuted();
    if (_isWindows || _isWeb) {
      try {
        await _apiService?.pausePlayback();
      } catch (_) {}
    } else {
      try {
        await SpotifySdk.pause();
      } catch (_) {}
    }
    if (_currentSessionId != null) {
      _socketService?.emit('session_command', {
        'sessionId': _currentSessionId,
        'action': 'pause',
      });
    }
    notifyListeners();
  }

  void _checkSessionTrackEnd() {
    if (!_sessionMode || !_isHost || _queueEnded || !_isPlaying || _isAdvancingQueue) return;
    if (_durationMs > 0 && _positionMs >= _durationMs - 900) {
      _isAdvancingQueue = true;
      _advanceSessionQueue();
    }
  }

  void _startPolling() {
    if (_apiService == null) return;

    _pollingTimer?.cancel();
    int tickCount = 0;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isPlaying) return;

      if (_sessionMode) {
        _positionMs = positionMs;
        if (_isHost) _checkSessionTrackEnd();
      } else if (_durationMs > 0) {
        _positionMs = (_positionMs + 500).clamp(0, _durationMs);
        _positionAnchorAt = DateTime.now();
        notifyListeners();
      }

      tickCount++;
      if (tickCount % 6 == 0 && !_sessionMode) {
        try {
          final state = await _apiService?.getPlayerState();
          if (state == null) return;
          if (_sessionPaused) return;
          _isPlaying = state['is_playing'] ?? false;
          _positionMs = state['progress_ms'] ?? 0;
          _positionAnchorAt = DateTime.now();
          _durationMs = state['item']?['duration_ms'] ?? 0;
          final track = state['item'];
          if (track != null) {
            _currentTrack = {
              'title': track['name'],
              'artist': (track['artists'] as List?)
                      ?.map((a) => a['name'])
                      .join(', ') ??
                  '',
              'imageUrl': track['album']?['images']?[0]?['url'],
              'uri': track['uri'],
            };
          }
          notifyListeners();
        } catch (e) {
          debugPrint('[Polling] error: $e');
        }
      }
    });
  }

  void updateHostStatus(bool isHost) {
    _isHost = isHost;
    notifyListeners();
  }

  void initSession(String sessionId, String userId, SocketService socketService, {bool isHost = false}) {
    _isHost = isHost;
    _currentSessionId = sessionId;
    _userId = userId;
    _socketService = socketService;

    _sessionSubscriptions.cancelAll();

    socketService.emit('join_session', {'sessionId': sessionId});
    socketService.setActiveSession(sessionId);
    _startSessionUiTicker();
    SessionForegroundService.start(
      keepScreenOn: LocalStore.readBool(StoreKeys.keepScreenOn, defaultValue: true),
    );

    _sessionSubscriptions.add(socketService.on('session_prepare', handleServerPrepare));

    _sessionSubscriptions.add(socketService.on('session_start', (data) async {
      _sessionPaused = false;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final trackId = map['trackId'] as String?;
      final startAt = (map['startAt'] as num?)?.toInt();
      final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;

      if (trackId == null || startAt == null) return;

      final dynamic rawLocalStart = socketService.serverToLocal(startAt);
      final int rawStart = rawLocalStart is num ? rawLocalStart.round() : startAt;
      final int localStart = rawStart - _audioLatencyMs;
      final now = DateTime.now().millisecondsSinceEpoch;
      final int delayMs = localStart - now;

      if (delayMs < -1000) {
        final int actualPos = positionMs + (now - localStart).abs();
        _setSyncAnchor(actualPos, socketService.serverNow());
        await _playAtPosition(trackId, actualPos);
        await _restoreVolumeIfMuted();
        socketService.emit('resync', {'sessionId': sessionId});
        return;
      }

      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      _setSyncAnchor(positionMs, socketService.serverNow());

      _isSessionSeeking = true;

      final String currentUri = _currentTrack?['uri'] as String? ?? '';
      final String targetUri = trackId.startsWith('spotify:') ? trackId : 'spotify:track:$trackId';
      if (_isPlaying && currentUri == targetUri) {
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.seekToPosition(positionMs);
          } else {
            await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
          }
          _positionMs = positionMs;
          _positionAnchorAt = DateTime.now();
          notifyListeners();
        } catch (e) {
          debugPrint('[Session Seek] Чистый seek не удался, полный ре-старт: $e');
          await _playAtPosition(trackId, positionMs);
        }
        await _restoreVolumeIfMuted();
        _clearSessionSeekingSoon();
        return;
      }

      await _playAtPosition(trackId, positionMs);
      await _restoreVolumeIfMuted();
      _clearSessionSeekingSoon();
    }));

    _sessionSubscriptions.add(socketService.on('session_sync', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final positionMs = (map['positionMs'] as num?)?.toInt();
      final serverTime = (map['serverTime'] as num?)?.toInt();

      if (positionMs == null || serverTime == null || !_isPlaying) return;

      final dynamic rawCurrentServerTime = socketService.currentServerTime;
      final int currentServerTime =
          rawCurrentServerTime is num ? rawCurrentServerTime.round() : DateTime.now().millisecondsSinceEpoch;
      final int expectedPos = positionMs + (currentServerTime - serverTime);

      _setSyncAnchor(positionMs, serverTime);

      final int drift = (expectedPos - _positionMs).abs();

      if (_isSessionSeeking || _isAdvancingQueue) {
        _driftStrikes = 0;
        return;
      }

      final int driftThreshold = 2000;

      if (drift > driftThreshold && _isPlaying) {
        _driftStrikes++;
      } else {
        _driftStrikes = 0;
      }

      if (_driftStrikes >= 2 && _isPlaying) {
        _driftStrikes = 0;
        _positionMs = expectedPos;
        _positionAnchorAt = DateTime.now();
        notifyListeners();
        if (!_isWindows && !_isWeb && _isConnected) {
          SpotifySdk.seekTo(positionedMilliseconds: expectedPos).catchError((_) {});
        } else if (_isWindows || _isWeb) {
          final svc = _apiService;
          if (svc != null) {
            svc.seekToPosition(expectedPos).catchError((e) {
              debugPrint('[SyncM] session_sync авто-коррекция позиции не удалась: $e');
            });
          }
        }
      }
    }));

    _sessionSubscriptions.add(socketService.on('session_reseek', (data) async {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final positionMs = (map['positionMs'] as num?)?.toInt();
      final serverTime = (map['serverTime'] as num?)?.toInt();
      if (positionMs == null || serverTime == null || !_isPlaying) return;
      if (_sessionPaused || _isSessionSeeking || _isAdvancingQueue) return;

      final int nowServer = _socketService?.serverNow() ?? DateTime.now().millisecondsSinceEpoch;
      final int target = positionMs + (nowServer - serverTime);
      final int drift = (target - _positionMs).abs();

      if (drift < 900) return;

      _positionMs = target;
      _positionAnchorAt = DateTime.now();
      _setSyncAnchor(target, nowServer);
      notifyListeners();
      try {
        if (_isWindows || _isWeb) {
          await _apiService?.seekToPosition(target);
        } else {
          await SpotifySdk.seekTo(positionedMilliseconds: target);
        }
      } catch (e) {
        debugPrint('[SyncM] session_reseek не удался: $e');
      }
    }));

    _sessionSubscriptions.add(socketService.on('session_pause', (data) async {
      debugPrint('[Socket] Получен session_pause: $data');
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final positionMs = (map['positionMs'] as num?)?.toInt();

      _isPlaying = false;
      _sessionPaused = true;
      if (positionMs != null) _positionMs = positionMs;
      _clearSyncAnchor();
      notifyListeners();
      await _restoreVolumeIfMuted();

      if (_isWindows || _isWeb) {
        try {
          await _apiService?.pausePlayback();
        } catch (_) {}
      } else {
        try {
          await SpotifySdk.pause();
        } catch (_) {}
      }
    }));

    _sessionSubscriptions.add(socketService.on('session_resume', (data) async {
      _sessionPaused = false;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final resumePos = (map['positionMs'] as num?)?.toInt();
      if (resumePos != null) _positionMs = resumePos;
      _setSyncAnchor(resumePos ?? _positionMs, socketService.serverNow());
      if (!_isPlaying) {
        _isPlaying = true;
        notifyListeners();
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } catch (e) {
          debugPrint('[Socket] Resume error: $e');
        }
      } else {
        notifyListeners();
      }
    }));

    _sessionSubscriptions.add(socketService.on('session_state', (data) async {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final state = map['state'] as String?;
      final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
      final serverTime = (map['serverTime'] as num?)?.toInt();
      final trackId = map['trackId'] as String?;

      if (trackId == null) return;

      if (state == 'playing' && serverTime != null) {
        final dynamic rawCurrentServerTime = socketService.currentServerTime;
        final int currentServerTime =
            rawCurrentServerTime is num ? rawCurrentServerTime.round() : DateTime.now().millisecondsSinceEpoch;
        final int actualPos = positionMs + (currentServerTime - serverTime);
        _setSyncAnchor(positionMs, serverTime);
        await _playAtPosition(trackId, actualPos);
      } else if (state == 'paused') {
        _positionMs = positionMs;
        _positionAnchorAt = DateTime.now();
        _isPlaying = false;
        _clearSyncAnchor();
        notifyListeners();
      }
    }));

    _sessionSubscriptions.add(socketService.on('session_play', (data) {
      if (data is Map) handleSessionPlayEvent(Map<String, dynamic>.from(data));
    }));

    _sessionSubscriptions.add(socketService.on('play', (data) async {
      _sessionPaused = false;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final String? uri = map['spotifyUri'] as String?;
      final int? pos = (map['position_ms'] as num?)?.toInt();

      if (uri == null) return;
      debugPrint('[Socket Play] Сервер приказал включить трек: $uri');

      Map<String, dynamic> fullTrackData = {'uri': uri};
      final index = _sessionQueue.indexWhere((t) => t['uri'] == uri);

      if (index >= 0) {
        fullTrackData = Map<String, dynamic>.from(_sessionQueue[index]);
        _sessionQueueIndex = index;
      }

      if (uri != _currentTrack?['uri']) {
        _currentTrack = fullTrackData;
        notifyListeners();

        await playTrack(fullTrackData, positionMs: pos, fromSession: true);
      } else {
        _isPlaying = true;
        notifyListeners();
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } catch (e) {
          debugPrint('Ошибка снятия с паузы в сессии: $e');
        }
      }
    }));

    _sessionSubscriptions.add(socketService.on('seek', (data) async {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final int pos = (map['position_ms'] as num?)?.toInt() ?? 0;

      debugPrint('[Socket] Получена глобальная перемотка на: $pos мс');
      _isSeekingFromRemote = true;
      _positionMs = pos;
      _positionAnchorAt = DateTime.now();
      notifyListeners();

      try {
        if (!_isWindows && !_isWeb && _isConnected) {
          await SpotifySdk.seekTo(positionedMilliseconds: pos);
        } else if (_isWindows || _isWeb) {
          await _apiService?.seekToPosition(pos);
        }
      } catch (e) {
        debugPrint('[Socket Seek] Ошибка физической перемотки: $e');
      } finally {
        await Future.delayed(const Duration(milliseconds: 300));
        _isSeekingFromRemote = false;
      }
    }));

    _sessionSubscriptions.add(socketService.on('session_ended', (data) async {
      debugPrint('[Session] сессия завершена хостом');
      debugPrint('[Session] провайдер: session_ended, глушим');
      try {
        if (_isWindows || _isWeb) {
          await _apiService?.pausePlayback();
        } else {
          await SpotifySdk.pause();
        }
      } catch (err) {
        debugPrint('[Session] не удалось остановить воспроизведение: $err');
      }

      stop();
    }));

    _sessionSubscriptions.add(socketService.on('tracks-added', (data) {
      if (data is Map) onTracksAdded?.call(Map<String, dynamic>.from(data));
    }));
  }

  Timer? _sessionSeekingTimer;
  void _clearSessionSeekingSoon() {
    _sessionSeekingTimer?.cancel();
    _sessionSeekingTimer = Timer(const Duration(milliseconds: 3000), () {
      _isSessionSeeking = false;
    });
  }

  Timer? _sessionUiTicker;
  void _startSessionUiTicker() {
    _sessionUiTicker?.cancel();
    _sessionUiTicker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_sessionMode && _isPlaying && !_sessionPaused && _syncAnchorServerTime != null) {
        notifyListeners();
      }
    });
  }

  void _stopSessionUiTicker() {
    _sessionUiTicker?.cancel();
    _sessionUiTicker = null;
  }

  void _setSyncAnchor(int positionMs, int serverTime) {
    _syncAnchorPositionMs = positionMs;
    _syncAnchorServerTime = serverTime;
    _positionMs = positionMs;
  }

  void _clearSyncAnchor() {
    _syncAnchorServerTime = null;
  }

  Future<void> _restoreVolumeIfMuted() async {
    if (!_isWindows && !_isWeb) return;
    final vol = _preMuteVolume;
    if (vol == null) return;
    _preMuteVolume = null;
    try {
      await _apiService?.setVolume(vol);
    } catch (e) {
      debugPrint('[SyncM] Volume restore error: $e');
    }
  }

  Future<void> _playAtPosition(String uriOrId, int positionMs) async {
    final fullUri = uriOrId.startsWith('spotify:') ? uriOrId : 'spotify:track:$uriOrId';
    final index = _sessionQueue.indexWhere((t) => t['uri'] == fullUri);
    if (index < 0) return;

    _sessionMode = true;
    _sessionQueueIndex = index;
    _positionMs = positionMs;
    _positionAnchorAt = DateTime.now();

    final track = Map<String, dynamic>.from(_sessionQueue[index]);
    await playTrack(track, positionMs: positionMs, fromSession: true);
  }

  Future<bool>? _connectAttempt;

  Future<bool> connect({bool silent = false}) {
    if (_isConnected) return Future.value(true);

    final running = _connectAttempt;
    if (running != null) return running;

    final attempt = _connect(silent: silent);
    _connectAttempt = attempt;
    return attempt.whenComplete(() {
      if (identical(_connectAttempt, attempt)) _connectAttempt = null;
    });
  }

  Future<bool> _connect({required bool silent}) async {
    try {
      _isConnected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
      );

      if (!_isConnected && !silent) {
        await SpotifySdk.getAccessToken(
          clientId: _clientId,
          redirectUrl: _redirectUrl,
          scope: 'app-remote-control,user-modify-playback-state,'
              'user-read-playback-state,playlist-read-private,streaming',
        );
        _isConnected = await SpotifySdk.connectToSpotifyRemote(
          clientId: _clientId,
          redirectUrl: _redirectUrl,
        );
      }

      if (_isConnected) _subscribeToPlayerState();
      notifyListeners();
      return _isConnected;
    } catch (e) {
      debugPrint('[Spotify] Connect error: $e');

      if (silent) {
        _isConnected = false;
        notifyListeners();
        return false;
      }

      try {
        await SpotifySdk.getAccessToken(
          clientId: _clientId,
          redirectUrl: _redirectUrl,
          scope: 'app-remote-control,user-modify-playback-state,'
              'user-read-playback-state,playlist-read-private,streaming',
        );
        _isConnected = await SpotifySdk.connectToSpotifyRemote(
          clientId: _clientId,
          redirectUrl: _redirectUrl,
        );
        if (_isConnected) _subscribeToPlayerState();
      } catch (retryError) {
        debugPrint('[Spotify] Authorize error: $retryError');
        _isConnected = false;
      }

      notifyListeners();
      return _isConnected;
    }
  }

  StreamSubscription<PlayerState>? _playerStateSub;

  void _subscribeToPlayerState() {
    _playerStateSub?.cancel();
    _playerStateSub = SpotifySdk.subscribePlayerState().listen((PlayerState state) async {
      _isPlaying = !state.isPaused;
      _durationMs = state.track?.duration ?? 0;
      _positionMs = state.playbackPosition;
      _positionAnchorAt = DateTime.now();

      if (!state.isPaused) {
        _lastActivePositionMs = state.playbackPosition;
        if (state.track != null) _lastActiveDurationMs = state.track!.duration;
      }

      if (state.track != null) {
        final trackUri = state.track!.uri;

        if (_shouldIgnoreSdkTrack(trackUri)) return;

        final imageUriId = state.track!.imageUri.raw;
        final trackChanged = trackUri != _currentTrack?['uri'];
        final imageChanged = imageUriId != _lastImageUri;

        final fromQueue = _findInQueue(trackUri);

        _currentTrack = {
          ...(trackChanged ? const <String, dynamic>{} : _currentTrack ?? {}),
          if (fromQueue != null) ...fromQueue,
          'title': state.track!.name,
          'artist': state.track!.artist.name,
          'uri': trackUri,
        };

        if (imageChanged) {
          _lastImageUri = imageUriId;
          _currentImageBytes = null;
          notifyListeners();
          try {
            final imageBytes = await SpotifySdk.getImage(
              imageUri: state.track!.imageUri,
              dimension: ImageDimension.large,
            );
            if (_lastImageUri == imageUriId) {
              _currentImageBytes = imageBytes;
              notifyListeners();
            }
          } catch (e) {
            debugPrint('[Spotify] Ошибка скачивания обложки: $e');
            _currentImageBytes = null;
            notifyListeners();
          }
        } else {
          notifyListeners();
        }

        if (_preparedTrackId != null && !_isReadySent) {
          final activeTrackId = trackUri.split(':').last;
          if (activeTrackId == _preparedTrackId && state.isPaused) {
            _isReadySent = true;
            debugPrint('[SyncPlay] Spotify загрузил трек. Отправляем client_ready');
            _socketService?.emit('client_ready', {
              'sessionId': _currentSessionId,
              'trackId': _preparedTrackId,
            });
          }
        }

        if (trackChanged && _currentSessionId != null && !_sessionMode) {
          _socketService?.emit('next_track', {
            'sessionId': _currentSessionId,
            'spotifyUri': trackUri,
          });
        }

        final bool isIntentionalPreparePause = _preparedTrackId != null && !_isReadySent;
        if (_sessionMode &&
            _isHost &&
            state.isPaused &&
            !_isAdvancingQueue &&
            !_isSessionSeeking &&
            !isIntentionalPreparePause) {
          final dur = _lastActiveDurationMs;
          if (dur > 0 && _lastActivePositionMs >= dur - 1200) {
            debugPrint('[SyncM] Трек завершился. Переключаем...');
            _isAdvancingQueue = true;
            _advanceSessionQueue();
          }
        }

        if (!_sessionMode &&
            trackChanged &&
            _shuffleActive &&
            _currentPlaylistId != null &&
            !_suppressAutoCorrection) {
          try {
            await _ensurePlaylistTracksLoaded();
            final found = _currentPlaylistTracks?.any((t) => (t['uri'] as String?) == trackUri) ?? false;
            if (!found) _playRandomFromCurrentPlaylist();
          } catch (e) {
            debugPrint('[PlaybackProvider] Error validating track against playlist: $e');
          }
        }
      } else {
        notifyListeners();
      }
    }, onError: (err) => debugPrint('[Spotify] PlayerState stream error: $err'));
  }

  Future<void> playTrack(Map<String, dynamic> track,
      {String? playlistId,
      List<dynamic>? knownPlaylistTracks,
      int? positionMs,
      bool fromSession = false}) async {
    final uri = track['uri'] as String?;
    if (uri == null) return;

    _markPendingTrack(uri);

    if (!fromSession) _sessionMode = false;

    if (!_isConnected && !_isWindows && !_isWeb) {
      final connected = await connect();
      if (!connected) return;
    }

    try {
      if (_isWindows || _isWeb) {
        try {
          final contextUri = playlistId != null
              ? (playlistId.startsWith('spotify:') ? playlistId : 'spotify:playlist:$playlistId')
              : null;

          await _apiService?.playTrack(
            uri,
            contextUri: contextUri,
            offset: track['index'] as int?,
          );

          if (positionMs != null && positionMs > 0) {
            await Future.delayed(const Duration(milliseconds: 300));
            try {
              await _apiService?.seekToPosition(positionMs);
            } catch (e) {
              debugPrint('[Web/Windows] Seek after play error: $e');
            }
          }

          _currentTrack = track;
          _isPlaying = true;

          if (playlistId != null) {
            _currentPlaylistId = playlistId.startsWith('spotify:') ? playlistId : 'spotify:playlist:$playlistId';
            if (knownPlaylistTracks != null) {
              _currentPlaylistTracks = knownPlaylistTracks;
            } else {
              try {
                final tracks = await _apiService?.getPlaylistTracks(playlistId);
                _currentPlaylistTracks = tracks;
              } catch (e) {
                debugPrint('[PlaybackProvider] Failed to prefetch playlist tracks: $e');
              }
            }
          } else {
            _currentPlaylistId = null;
            _currentPlaylistTracks = null;
          }

          if (track['imageUrl'] != null && !_paletteCache.containsKey(track['imageUrl'])) {
            _preloadPalette(track['imageUrl']);
          }

          notifyListeners();
          _startPolling();
        } catch (e) {
          debugPrint('[Web/Windows] Play error: $e');
        }
        return;
      }

      if (playlistId != null) {
        final contextUri = playlistId.startsWith('spotify:')
            ? playlistId
            : 'spotify:playlist:$playlistId';

        final sameContext = _currentPlaylistId == contextUri && _isConnected;

        if (!sameContext) {
          await SpotifySdk.play(spotifyUri: contextUri);
          await Future.delayed(const Duration(milliseconds: 500));
        }

        await SpotifySdk.skipToIndex(
          spotifyUri: contextUri,
          trackIndex: track['index'] as int? ?? 0,
        );
      } else {
        await SpotifySdk.play(spotifyUri: uri);
      }

      if (positionMs != null && positionMs > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
      }

      if (playlistId != null) {
        _currentPlaylistId = playlistId.startsWith('spotify:') ? playlistId : 'spotify:playlist:$playlistId';
        if (knownPlaylistTracks != null) {
          _currentPlaylistTracks = knownPlaylistTracks;
        } else {
          try {
            final tracks = await _apiService?.getPlaylistTracks(playlistId);
            _currentPlaylistTracks = tracks;
          } catch (e) {
            debugPrint('[PlaybackProvider] Failed to prefetch playlist tracks: $e');
          }
        }
      } else {
        _currentPlaylistId = null;
        _currentPlaylistTracks = null;
      }

      _currentTrack = track;
      _isPlaying = true;

      if (_currentSessionId != null && !_sessionMode && !_isRemoteSync) {
        _socketService?.emit('play', {
          'sessionId': _currentSessionId,
          'spotifyUri': uri,
          'position_ms': positionMs ?? 0,
        });
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[Spotify] Play error: $e');
      try {
        _isConnected = false;
        final reconnected = await connect();
        if (reconnected) {
          await SpotifySdk.play(spotifyUri: uri);
          _currentTrack = track;
          _isPlaying = true;
          notifyListeners();
        }
      } catch (e2) {
        debugPrint('[Spotify] Fallback play error: $e2');
      }
    }
  }

  Future<void> togglePlay() async {
    final now = DateTime.now();
    if (_lastToggle != null && now.difference(_lastToggle!) < const Duration(milliseconds: 500)) return;
    _lastToggle = now;

    if (_sessionMode && _currentSessionId != null) {
      if (_isPlaying) {
        debugPrint('[Socket] Пауза → session_command');
        _isPlaying = false;
        _sessionPaused = true;
        notifyListeners();
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.pausePlayback();
          } else {
            await SpotifySdk.pause();
          }
        } catch (e) {
          debugPrint('[togglePlay] local pause error: $e');
        }
        _socketService?.emit('session_command', {
          'sessionId': _currentSessionId,
          'action': 'pause',
        });
      } else {
        debugPrint('[Socket] Возобновление → session_command');
        _sessionPaused = false;
        _isPlaying = true;
        notifyListeners();
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } catch (e) {
          debugPrint('[togglePlay] local resume error: $e');
        }
        _socketService?.emit('session_command', {
          'sessionId': _currentSessionId,
          'action': 'resume',
        });
      }
      return;
    }

    try {
      if (_isPlaying) {
        if (_isWindows || _isWeb) {
          await _apiService?.pausePlayback();
        } else {
          await SpotifySdk.pause();
        }
        _isPlaying = false;
      } else {
        if (_isWindows || _isWeb) {
          await _apiService?.resumePlayback();
        } else {
          await SpotifySdk.resume();
        }
        _isPlaying = true;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Solo Play/Pause] Ошибка: $e');
    }
  }

  Future<void> _updateFromPlayerState(dynamic state) async {
    if (state == null) return;
    _isPlaying = state['is_playing'] ?? false;
    _positionMs = state['progress_ms'] ?? 0;
    _positionAnchorAt = DateTime.now();
    _durationMs = state['item']?['duration_ms'] ?? 0;
    final track = state['item'];
    if (track != null) {
      final newImageUrl = track['album']?['images']?[0]?['url'];
      _currentTrack = {
        'title': track['name'],
        'artist': (track['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '',
        'imageUrl': newImageUrl,
        'uri': track['uri'],
      };
      _currentImageBytes = null;

      if (newImageUrl != null && !_paletteCache.containsKey(newImageUrl)) {
        _preloadPalette(newImageUrl);
      }

      if (_shuffleActive && _currentPlaylistId != null && !_suppressAutoCorrection) {
        try {
          await _ensurePlaylistTracksLoaded();
          final uri = _currentTrack?['uri'] as String?;
          final found = _currentPlaylistTracks?.any((t) => (t['uri'] as String?) == uri) ?? false;
          if (!found) {
            _playRandomFromCurrentPlaylist();
          }
        } catch (e) {
          debugPrint('[PlaybackProvider] Error checking playlist membership: $e');
        }
      }
    }
    notifyListeners();
  }

  void _pollForTrackChange() {
    final oldUri = _currentTrack?['uri'];
    _trackChangeTimer?.cancel();
    int attempts = 0;
    _trackChangeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      attempts++;
      if (attempts > 10) {
        timer.cancel();
        return;
      }
      try {
        final state = await _apiService?.getPlayerState();
        if (state == null) return;
        final track = state['item'];
        final newUri = track?['uri'];
        if (newUri != null && newUri != oldUri) {
          timer.cancel();
          _updateFromPlayerState(state);
        }
      } catch (e) {
        debugPrint('[Poll] error: $e');
      }
    });
  }

  Color? _artworkColor;
  Color? get artworkColor => _artworkColor;

  String? _artworkColorKey;

  String? _artworkColorPending;

  Map<String, dynamic>? get previousQueueTrack => _queueNeighbour(-1);
  Map<String, dynamic>? get nextQueueTrack => _queueNeighbour(1);

  static String? _trackKeyOf(dynamic track) {
    if (track == null) return null;
    final raw = (track['uri'] ?? track['id']) as String?;
    if (raw == null || raw.isEmpty) return null;
    return raw.contains(':') ? raw.split(':').last : raw;
  }

  Map<String, dynamic>? _findInQueue(String uri) {
    final key = _trackKeyOf({'uri': uri});
    if (key == null) return null;

    final tracks = _sessionMode
        ? _sessionQueue
        : (_currentPlaylistTracks ?? const []);
    if (tracks.isEmpty) return null;

    final found = tracks.indexWhere((t) => _trackKeyOf(t) == key);
    if (found < 0) return null;

    return mapSessionTrack(tracks[found], found);
  }

  ({List<dynamic> tracks, int position})? get _activeQueue {
    if (_sessionMode) {
      if (_sessionQueue.isEmpty) return null;

      final key = _trackKeyOf(_currentTrack);
      if (key != null) {
        final found =
            _sessionQueue.indexWhere((t) => _trackKeyOf(t) == key);
        if (found >= 0) {
          _sessionQueueIndex = found;
          return (tracks: _sessionQueue, position: found);
        }
      }

      if (_sessionQueueIndex < 0 || _sessionQueueIndex >= _sessionQueue.length) {
        return null;
      }
      return (tracks: _sessionQueue, position: _sessionQueueIndex);
    }

    final tracks = _currentPlaylistTracks;
    if (tracks == null || tracks.isEmpty) return null;

    final position = _queuePosition;
    if (position == null) return null;

    return (tracks: tracks, position: position);
  }

  bool get canControlQueue => !_isRemoteSync;

  int? get _queuePosition {
    final tracks = _currentPlaylistTracks;
    if (tracks == null || tracks.isEmpty) return null;

    final key = _trackKeyOf(_currentTrack);
    if (key != null) {
      final found = tracks.indexWhere((t) => _trackKeyOf(t) == key);
      if (found >= 0) {
        _currentTrack?['index'] = found;
        return found;
      }
    }

    final index = _currentTrack?['index'] as int?;
    if (index != null && index >= 0 && index < tracks.length) return index;

    return null;
  }

  Map<String, dynamic>? _queueNeighbour(int offset) {
    if (!canControlQueue) return null;

    if (_shuffleActive) return null;

    final queue = _activeQueue;
    if (queue == null) return null;

    final target = queue.position + offset;
    if (target < 0 || target >= queue.tracks.length) return null;

    return mapSessionTrack(queue.tracks[target], target);
  }

  Future<void> goToNext() async {
    if (await playQueueNeighbour(1)) return;
    await skipNext();
  }

  Future<void> goToPrevious() async {
    if (await playQueueNeighbour(-1)) return;
    await skipPrevious();
  }

  Future<bool> playQueueNeighbour(int direction) async {
    if (!canControlQueue) return false;

    final track = direction > 0 ? nextQueueTrack : previousQueueTrack;
    if (track == null) return false;

    if (_sessionMode) {
      final target = _sessionQueueIndex + direction;
      if (target < 0 || target >= _sessionQueue.length) return false;
      await playSessionTrack(target);
      return true;
    }

    final tracks = _currentPlaylistTracks;
    final playlistId = _currentPlaylistId;

    await playTrack(
      track,
      playlistId: playlistId?.split(':').last,
      knownPlaylistTracks: tracks,
    );
    return true;
  }

  Color? dominantColorForUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return _paletteCache[url]?.dominantColor?.color;
  }

  Color? mutedColorForUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    final base = _paletteCache[url]?.dominantColor?.color;
    if (base == null) return null;

    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.6))
        .withLightness(0.28)
        .toColor();
  }

  List<String> get neighbourArtworkUrls {
    if (_shuffleActive) return const [];

    final queue = _activeQueue;
    if (queue == null) return const [];

    final urls = <String>[];
    for (final offset in const [-1, 1, 2]) {
      final target = queue.position + offset;
      if (target < 0 || target >= queue.tracks.length) continue;

      final url = mapSessionTrack(queue.tracks[target], target)['imageUrl']
          as String?;
      if (url != null && url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  void ensureArtworkColor() {
    final track = _currentTrack;
    if (track == null) {
      if (_artworkColor != null) {
        _artworkColor = null;
        _artworkColorKey = null;
        _artworkColorPending = null;
      }
      return;
    }

    final url = track['imageUrl'] as String?;
    final key = (url != null && url.isNotEmpty) ? url : track['uri'] as String?;
    if (key == null) return;

    if (key == _artworkColorKey || key == _artworkColorPending) return;

    final bytes = _currentImageBytes;
    final hasSource = bytes != null || (url != null && url.isNotEmpty);
    if (!hasSource) return;

    _artworkColorPending = key;
    unawaited(_computeArtworkColor(key, url, bytes));
  }

  Future<void> _computeArtworkColor(
    String key,
    String? url,
    Uint8List? bytes,
  ) async {
    final ImageProvider provider;
    if (bytes != null) {
      provider = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      provider = NetworkImage(url);
    } else {
      return;
    }

    try {
      final palette = _paletteCache[key] ??
          await PaletteGenerator.fromImageProvider(
            provider,
            size: const Size(64, 64),
            maximumColorCount: 8,
          );
      _paletteCache[key] = palette;

      if (key != _artworkColorPending) return;

      final base = palette.dominantColor?.color;
      if (base == null) return;

      _artworkColorKey = key;

      final hsl = HSLColor.fromColor(base);
      _artworkColor = hsl
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.6))
          .withLightness(0.28)
          .toColor();
      notifyListeners();
    } catch (err) {
      debugPrint('Не удалось получить цвет обложки: $err');
    } finally {
      if (key == _artworkColorPending) _artworkColorPending = null;
    }
  }

  void preloadPalettes(Iterable<String> urls) {
    for (final url in urls) {
      if (url.isEmpty || _paletteCache.containsKey(url)) continue;
      unawaited(_preloadPalette(url));
    }
  }

  Future<void> _preloadPalette(String imageUrl) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        size: const Size(64, 64),
        maximumColorCount: 8,
      );
      _paletteCache[imageUrl] = palette;
      notifyListeners();
    } catch (e) {
      debugPrint('Preload palette error: $e');
    }
  }

  Future<void> skipNext() async {
    if (_isSkipping) return;
    _isSkipping = true;

    try {
      if (_sessionMode) {
        await _advanceSessionQueue();
        return;
      }

      _positionMs = 0;
      _positionAnchorAt = DateTime.now();
      notifyListeners();

      if (_isWindows || _isWeb) {
        if (_shuffleActive && _currentPlaylistId != null) {
          await _playRandomFromCurrentPlaylist();
        } else {
          await _apiService?.skipToNext();
          _pollForTrackChange();
        }
        return;
      }

      if (_shuffleActive && _currentPlaylistId != null) {
        await _playRandomFromCurrentPlaylist();
      } else {
        await SpotifySdk.skipNext();
      }
    } catch (e) {
      debugPrint('Skip next error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      _isSkipping = false;
      notifyListeners();
    }
  }

  Future<void> skipPrevious() async {
    if (_sessionMode && _sessionQueueIndex > 0) {
      await playSessionTrack(_sessionQueueIndex - 1);
      return;
    }

    _positionMs = 0;
    _positionAnchorAt = DateTime.now();
    notifyListeners();

    if (_isWindows || _isWeb) {
      try {
        if (_shuffleActive && _currentPlaylistId != null) {
          await _playRandomFromCurrentPlaylist();
        } else {
          await _apiService?.skipToPrevious();
          _pollForTrackChange();
        }
      } catch (e) {
        debugPrint('[Web/Windows] Skip previous error: $e');
      }
      return;
    }
    try {
      if (_shuffleActive && _currentPlaylistId != null) {
        await _playRandomFromCurrentPlaylist();
      } else {
        await SpotifySdk.skipPrevious();
      }
    } catch (e) {
      debugPrint('[Spotify] Skip previous error: $e');
    }
  }

  String _plainPlaylistId(String id) {
    if (id.contains(':')) return id.split(':').last;
    return id;
  }

  Future<void> _ensurePlaylistTracksLoaded() async {
    if (_currentPlaylistId == null || _currentPlaylistTracks != null) return;
    try {
      final id = _plainPlaylistId(_currentPlaylistId!);
      final tracks = await _apiService?.getPlaylistTracks(id);
      if (tracks != null) {
        for (int i = 0; i < tracks.length; i++) {
          if (tracks[i]['index'] == null) tracks[i]['index'] = i;
        }
        _currentPlaylistTracks = tracks;
      }
    } catch (e) {
      debugPrint('[PlaybackProvider] Could not load playlist tracks: $e');
    }
  }

  Future<void> _playRandomFromCurrentPlaylist() async {
    if (_currentPlaylistId == null) return;
    await _ensurePlaylistTracksLoaded();
    final tracks = _currentPlaylistTracks;
    if (tracks == null || tracks.isEmpty) return;

    final uris = <String>[];
    for (var t in tracks) {
      final u = t['uri'] as String?;
      if (u != null && u.isNotEmpty) uris.add(u);
    }
    if (uris.isEmpty) return;

    final currentUri = _currentTrack?['uri'] as String?;
    final rnd = Random();
    int index = rnd.nextInt(uris.length);
    int attempts = 0;
    while (uris[index] == currentUri && attempts < 6) {
      index = rnd.nextInt(uris.length);
      attempts++;
    }

    final sel = tracks[index];
    final selectedUri = uris[index];
    final trackMap = {
      'uri': selectedUri,
      'index': sel['index'] ?? index,
      'title': sel['name'] ?? sel['title'] ?? '',
      'artist': sel['artist'] ?? '',
      'imageUrl': sel['imageUrl'] ?? sel['album']?['images']?[0]?['url'],
    };

    _suppressAutoCorrection = true;
    Future.delayed(const Duration(seconds: 2), () {
      _suppressAutoCorrection = false;
    });

    try {
      final contextUri =
          _currentPlaylistId!.startsWith('spotify:') ? _currentPlaylistId! : 'spotify:playlist:${_currentPlaylistId!}';
      if (_isWindows || _isWeb) {
        await _apiService?.playTrack(selectedUri, contextUri: contextUri, offset: trackMap['index'] as int?);
        _currentTrack = trackMap;
        _isPlaying = true;
        notifyListeners();
      } else {
        await SpotifySdk.play(spotifyUri: contextUri);
        await Future.delayed(const Duration(milliseconds: 500));
        await SpotifySdk.skipToIndex(spotifyUri: contextUri, trackIndex: trackMap['index'] as int? ?? 0);
        _currentTrack = trackMap;
        _isPlaying = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PlaybackProvider] _playRandomFromCurrentPlaylist error: $e');
    }
  }

  Future<void> seekTo(int positionMs) async {
    _positionMs = positionMs;
    _positionAnchorAt = DateTime.now();
    notifyListeners();

    if (_sessionMode && _currentSessionId != null) {
      if (_isSeekingFromRemote) return;
      _socketService?.emit('session_command', {
        'sessionId': _currentSessionId,
        'action': 'seek',
        'positionMs': positionMs,
      });
      return;
    }

    try {
      if (_isWindows || _isWeb) {
        await _apiService?.seekToPosition(positionMs);
      } else {
        await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
      }
    } catch (e) {
      debugPrint('[Solo Seek] Ошибка: $e');
    }
  }

  Future<void> refreshAfterResume() async {
    try {
      if (_isWindows || _isWeb) {
        _startPolling();
        return;
      }

      if (!_isConnected) {
        final connected = await connect(silent: true);
        if (!connected) return;
      }
      _subscribeToPlayerState();
    } catch (err) {
      debugPrint('[Playback] не удалось восстановиться после возврата: $err');
    }
  }

  Future<void> stopAndClear() async {
    try {
      if (_isWindows || _isWeb) {
        await _apiService?.pausePlayback();
      } else {
        await SpotifySdk.pause();
      }
    } catch (err) {
      debugPrint('[Playback] не удалось остановить воспроизведение: $err');
    }
    stop();
  }

  Future<void> resetForLogout() async {
    await _playerStateSub?.cancel();
    _playerStateSub = null;

    stop();

    try {
      await SpotifySdk.disconnect();
    } catch (err) {
      debugPrint('[Spotify] Отключение при выходе не удалось: $err');
    }

    _isConnected = false;
    _durationMs = 0;
    _positionMs = 0;
    _lastActivePositionMs = 0;
    _lastActiveDurationMs = 0;
    _positionAnchorAt = null;
    paletteCache.clear();
    notifyListeners();
  }

  void stop() {
    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    if (_currentSessionId != null && _userId != null) {
      _socketService?.emit('leave_session', {'sessionId': _currentSessionId, 'userId': _userId});
    }
    _socketService?.setActiveSession(null);

    _sessionSubscriptions.cancelAll();

    SessionForegroundService.stop();
    _socketService = null;
    _currentSessionId = null;
    _isPlaying = false;
    _currentTrack = null;
    _isConnected = false;
    _currentImageBytes = null;
    _lastImageUri = null;
    _currentPlaylistId = null;
    _currentPlaylistTracks = null;
    _suppressAutoCorrection = false;
    _sessionMode = false;
    _sessionQueue = [];
    _sessionQueueIndex = -1;
    _queueEnded = false;
    _stopSessionUiTicker();
    _clearSyncAnchor();
    notifyListeners();
  }

  Future<void> setShuffle(bool enabled) async {
    debugPrint('[PlaybackProvider] setShuffle called, enabled=$enabled');
    try {
      if (_isWindows || _isWeb) {
        await _apiService?.setShuffle(enabled);
      } else {
        if (!_isConnected) await connect();
        await SpotifySdk.setShuffle(shuffle: enabled);
      }
      _shuffleActive = enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('[Spotify] setShuffle error: $e');
      _shuffleActive = enabled;
      notifyListeners();
    }
  }

  Future<void> cycleRepeatMode() async {
    debugPrint('[PlaybackProvider] cycleRepeatMode called, current mode=$_repeatMode');
    String newMode;
    switch (_repeatMode) {
      case 'off':
        newMode = 'context';
        break;
      case 'context':
        newMode = 'track';
        break;
      default:
        newMode = 'off';
    }
    try {
      if (_isWindows || _isWeb) {
        await _apiService?.setRepeatMode(newMode);
      } else {
        if (!_isConnected) await connect();
        final sdkMode = newMode == 'off'
            ? RepeatMode.off
            : newMode == 'context'
                ? RepeatMode.context
                : RepeatMode.track;
        await SpotifySdk.setRepeatMode(repeatMode: sdkMode);
      }
      _repeatMode = newMode;
      notifyListeners();
    } catch (e) {
      debugPrint('[Spotify] cycleRepeatMode error: $e');
      _repeatMode = newMode;
      notifyListeners();
    }
  }

  void handleServerPrepare(dynamic data) async {
    if (data is! Map) return;

    final trackId = data['trackId'] as String?;
    if (trackId == null) return;

    debugPrint('[SyncPlay] Сервер скомандовал развернуть трек: $trackId');

    _preparedTrackId = trackId;
    _isReadySent = false;

    _pollingTimer?.cancel();
    _isPlaying = false;
    _lastActivePositionMs = 0;
    _lastActiveDurationMs = 0;
    notifyListeners();

    final spotifyUri = 'spotify:track:$trackId';
    final bool isMobile = !_isWindows && !_isWeb;

    if (isMobile) {
      try {
        await SpotifySdk.play(spotifyUri: spotifyUri);
        await SpotifySdk.pause();
      } catch (e) {
        debugPrint('[SyncM] Error preparing track via SDK: $e');
      }
    } else {
      try {
        if (_preMuteVolume == null) {
          final state = await _apiService?.getPlayerState();
          final vol = (state?['device']?['volume_percent'] as num?)?.toInt();
          _preMuteVolume = (vol != null && vol > 0) ? vol : 100;
        }
        await _apiService?.setVolume(0);
      } catch (e) {
        debugPrint('[SyncM] Volume mute error: $e');
      }

      try {
        await _apiService?.playTrack(spotifyUri);
        await Future.delayed(const Duration(milliseconds: 250));
        await _apiService?.pausePlayback();
        _isReadySent = true;
        _socketService?.emit('client_ready', {
          'sessionId': _currentSessionId,
          'trackId': trackId,
        });
      } catch (e) {
        debugPrint('[SyncM] Error preparing track via API: $e');
        await _restoreVolumeIfMuted();
        final msg = e is ApiException
            ? e.userMessage
            : 'Откройте Spotify и запустите любой трек, затем повторите.';
        onPrepareError?.call(msg);
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    _sessionUiTicker?.cancel();
    _sessionSeekingTimer?.cancel();
    _advanceResetTimer?.cancel();

    _sessionSubscriptions.cancelAll();
    _playerStateSub?.cancel();

    super.dispose();
  }
}