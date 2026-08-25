import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/scheduler.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_phase.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/session_foreground_service.dart';
import '../utils/artwork_color_store.dart';
import '../utils/image_cache.dart';
import '../utils/app_globals.dart';
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
  // Защита от наложения REST-запросов: таймер тикает независимо от того,
  // вернулся ли предыдущий ответ.
  bool _playerStateRequestInFlight = false;
  bool _trackChangeRequestInFlight = false;
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

  int _autoCorrectionGeneration = 0;

  bool _playlistEnded = false;

  int _lastQueuePosition = -1;

  String? _autoAdvanceGuardUri;

  String? _lastRequestedUri;

  static const int _trackEndLeadMs = 700;

  String? _pendingTrackUri;
  DateTime? _pendingSince;
  Timer? _pendingResolveTimer;

  /// Трек, метаданные которого уже дополнены данными очереди: повторно
  /// искать его в очереди на каждом событии SDK не нужно.
  String? _queueEnrichedUri;

  static const _pendingTrackTimeout = Duration(milliseconds: 1500);

  void _markPendingTrack(String? uri) {
    _pendingTrackUri = uri;
    _pendingSince = uri == null ? null : DateTime.now();
    _pendingResolveTimer?.cancel();
    _pendingResolveTimer = null;

    if (uri != null) {
      _currentImageBytes = null;
      _lastImageUri = null;
      _pendingResolveTimer = Timer(_pendingTrackTimeout, _resolvePendingTrack);
      notifyListeners();
    }
  }

  /// SDK присылает состояние только по событиям. Если запрошенный трек так и
  /// не начался, новых событий не будет — и экран до самой паузы показывал бы
  /// нажатый трек вместо звучащего. По истечении окна ожидания состояние
  /// забирается принудительно, чтобы метаданные соответствовали звуку.
  Future<void> _resolvePendingTrack() async {
    _pendingResolveTimer = null;
    if (_disposed || _pendingTrackUri == null) return;

    _markPendingTrack(null);
    if (_isWindows || _isWeb || !_isConnected) return;

    try {
      final state = await SpotifySdk.getPlayerState();
      if (state != null && !_disposed) await _handlePlayerState(state);
    } catch (e) {
      debugPrint('[Spotify] Не удалось перечитать состояние плеера: $e');
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

  bool get playlistEnded => _playlistEnded;

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

  /// Позиция меняется несколько раз в секунду. Она вынесена в отдельный
  /// notifier, чтобы прогресс-бар не перестраивал весь UI, подписанный на
  /// провайдер: слушают его только те виджеты, которым нужна позиция.
  final ValueNotifier<int> positionNotifier = ValueNotifier<int>(0);

  /// Цвет обложки: слушают только фон и мини-плеер.
  final ValueNotifier<Color?> artworkColorNotifier = ValueNotifier<Color?>(null);

  /// Увеличивается, когда в кэш палитр добавляется новый цвет. Нужен, чтобы
  /// готовая палитра перестраивала только фон/цветных потребителей.
  final ValueNotifier<int> paletteVersion = ValueNotifier<int>(0);

  bool _disposed = false;

  /// Единственный визуальный тикер позиции. Источник истины — якоря
  /// (_positionAnchorAt / _syncAnchorServerTime), таймер лишь просит UI
  /// перечитать вычисленное значение, поэтому дрейф не накапливается.
  Timer? _positionTicker;
  static const _positionTickInterval = Duration(milliseconds: 250);

  void _publishPosition() {
    if (_disposed) return;
    final value = positionMs;
    if (positionNotifier.value != value) positionNotifier.value = value;
  }

  void _syncPositionTicker() {
    if (_disposed) {
      _positionTicker?.cancel();
      _positionTicker = null;
      return;
    }

    final bool shouldRun = _isPlaying && !(_sessionMode && _sessionPaused);

    if (shouldRun) {
      _positionTicker ??= Timer.periodic(_positionTickInterval, (_) {
        _publishPosition();
        _checkSoloTrackEnd();
      });
    } else {
      _positionTicker?.cancel();
      _positionTicker = null;
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    // Любое изменение состояния может сдвинуть позицию или запустить/
    // остановить воспроизведение — держим тикер и позицию в актуальном
    // состоянии здесь, а не в двух десятках мест.
    _publishPosition();
    _syncPositionTicker();
    super.notifyListeners();
  }

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

  /// Кэш палитр ограничен: оптимизация FPS не должна превращаться в
  /// бесконечный рост памяти.
  static const int _paletteCacheLimit = 60;

  /// Изображения, для которых PaletteGenerator уже работает. Проверки
  /// containsKey по кэшу недостаточно: расчёт асинхронный и может ещё идти,
  /// поэтому повторные запросы переиспользуют тот же Future.
  final Map<String, Future<PaletteGenerator?>> _palettePending = {};

  /// Кладёт готовую палитру в общий кэш (с ограничением размера) и сообщает
  void _cachePalette(String key, PaletteGenerator palette) {
    if (!_paletteCache.containsKey(key) &&
        _paletteCache.length >= _paletteCacheLimit) {
      _paletteCache.remove(_paletteCache.keys.first);
    }
    _paletteCache[key] = palette;
    if (!_disposed) paletteVersion.value++;
  }

  /// O(1)-поиск по очереди: trackKey -> index. Индексы строятся один раз при
  /// смене очереди вместо indexWhere на каждом событии Spotify.
  final Map<String, int> _sessionQueueIndexByKey = {};
  final Map<String, int> _playlistIndexByKey = {};

  static void _rebuildQueueIndex(
    Map<String, int> index,
    List<dynamic>? tracks,
  ) {
    index.clear();
    if (tracks == null) return;
    for (int i = 0; i < tracks.length; i++) {
      final key = _trackKeyOf(tracks[i]);
      // Первое вхождение выигрывает — так же, как вёл себя indexWhere.
      if (key != null) index.putIfAbsent(key, () => i);
    }
  }

  void _setSessionQueue(List<Map<String, dynamic>> tracks) {
    _sessionQueue = tracks;
    _rebuildQueueIndex(_sessionQueueIndexByKey, tracks);
    _invalidateNeighbourCache();
  }

  void _setPlaylistTracks(List<dynamic>? tracks) {
    _currentPlaylistTracks = tracks;
    _rebuildQueueIndex(_playlistIndexByKey, tracks);
    _invalidateNeighbourCache();
  }

  /// Индекс трека в очереди. Для известных очередей — O(1) по карте, для
  /// чужих списков сохраняется прежний последовательный поиск.
  int _indexInQueue(List<dynamic> tracks, String? key) {
    if (key == null) return -1;
    if (identical(tracks, _sessionQueue)) {
      return _sessionQueueIndexByKey[key] ?? -1;
    }
    if (identical(tracks, _currentPlaylistTracks)) {
      return _playlistIndexByKey[key] ?? -1;
    }
    return tracks.indexWhere((t) => _trackKeyOf(t) == key);
  }

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
      // Позиция в контексте Spotify приходит с сервера и переживает
      // нормализацию: по ней переключается плеер.
      if (t['contextIndex'] != null) 'contextIndex': t['contextIndex'],
    };
  }

  int? _positionOfCurrentIfStillValid(Map<String, dynamic> track, String uri) {
    final index = track['index'];
    final tracks = _currentPlaylistTracks;
    if (index is! int || tracks == null) return null;
    if (index < 0 || index >= tracks.length) return null;
    return _trackKeyOf(tracks[index]) == _trackKeyOf({'uri': uri})
        ? index
        : null;
  }

  static int? _contextIndexOf(Map<String, dynamic> track) {
    final ctx = track['contextIndex'];
    if (ctx is num && ctx >= 0) return ctx.toInt();
    final index = track['index'];
    if (index is num && index >= 0) return index.toInt();
    return null;
  }

  void setSessionQueue(List<dynamic> tracks) {
    final mapped = <Map<String, dynamic>>[];
    for (int i = 0; i < tracks.length; i++) {
      final track = mapSessionTrack(tracks[i], i);
      if ((track['uri'] as String?)?.isNotEmpty == true) mapped.add(track);
    }
    _setSessionQueue(mapped);
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
      // Второго вызова onSessionPlaybackStarted здесь нет: playSessionTrack
      // уже сообщил о старте. Повторный вызов был лишним поводом открыть
      // экран трека ещё раз и вдобавок падал на пустой очереди, если
      // playSessionTrack вышел из-за неверного index.
      await playSessionTrack(index, syncToSession: false);
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
        _advancingToUri = track['uri'] as String?;
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
        _advancingToUri = null;
      }
    } catch (e) {
      debugPrint('[SyncM] _advanceSessionQueue error: $e');
      _isAdvancingQueue = false;
      _advancingToUri = null;
    }
  }

  Timer? _advanceResetTimer;

  /// Трек, на который переключается очередь. Нужен, чтобы снять
  /// _isAdvancingQueue по факту старта нового трека, а не по таймауту.
  String? _advancingToUri;

  void _scheduleAdvanceFlagReset() {
    _advanceResetTimer?.cancel();

    // Сторожевой таймер: срабатывает, только если подтверждение о старте
    // нового трека так и не пришло (обрыв связи, отказ SDK).
    _advanceResetTimer = Timer(const Duration(milliseconds: 3500), () {
      _isAdvancingQueue = false;
      _advancingToUri = null;
    });
  }

  /// Переход очереди подтверждён: новый трек реально играет. Подтверждаем
  /// только на играющем состоянии — на паузе _lastActivePositionMs ещё
  /// хранит конец прошлого трека, и снятие флага вызвало бы второй advance.
  void _confirmQueueAdvance(String trackUri) {
    if (!_isAdvancingQueue) return;

    final target = _advancingToUri;
    if (target == null) return;
    if (_trackKeyOf({'uri': trackUri}) != _trackKeyOf({'uri': target})) return;

    _advanceResetTimer?.cancel();
    _advanceResetTimer = null;
    _isAdvancingQueue = false;
    _advancingToUri = null;
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
      }
      // Вне сессии позиция никуда не «дописывается»: значение считается из
      // якоря (_positionAnchorAt) реальным временем, а тикер позиции сам
      // обновляет UI. Прибавление ровно 500 мс за тик давало искусственный
      // дрейф, потому что таймер срабатывает не ровно раз в 500 мс.

      tickCount++;
      if (tickCount % 6 == 0 && !_sessionMode) {
        // Предыдущий REST-запрос ещё не вернулся — второй параллельный
        // запрос состояния плеера не нужен.
        if (_playerStateRequestInFlight) return;
        _playerStateRequestInFlight = true;
        try {
          final state = await _apiService?.getPlayerState();
          if (state == null) return;
          if (_sessionPaused) return;
          await _updateFromPlayerState(state);
        } catch (e) {
          debugPrint('[Polling] error: $e');
        } finally {
          _playerStateRequestInFlight = false;
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
    _syncPositionTicker();
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
        // Не «дать время», а ждать назначенный сервером момент старта:
        // это и есть механизм синхронного запуска у всех участников.
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
      final index = _indexInQueue(_sessionQueue, _trackKeyOf({'uri': uri}));

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
        // Окно, в котором прилетает эхо собственной перемотки: снимаем флаг
        // позже события, иначе своя же позиция уедет обратно на сервер.
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

  void _setSyncAnchor(int positionMs, int serverTime) {
    _syncAnchorPositionMs = positionMs;
    _syncAnchorServerTime = serverTime;
    _positionMs = positionMs;
    // Якорь сервера остаётся единственным источником истины для позиции
    // в сессии; общий тикер лишь показывает вычисленное по нему значение.
    _publishPosition();
  }

  void _clearSyncAnchor() {
    _syncAnchorServerTime = null;
    _publishPosition();
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
    final index = _indexInQueue(_sessionQueue, _trackKeyOf({'uri': fullUri}));
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
          scope: 'app-remote-control,user-modify-playback-state,user-read-playback-state,playlist-read-private,streaming',
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
          scope: 'app-remote-control,user-modify-playback-state,user-read-playback-state,playlist-read-private,streaming',
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
    _playerStateSub = SpotifySdk.subscribePlayerState().listen(
      _handlePlayerState,
      onError: (err) => debugPrint('[Spotify] PlayerState stream error: $err'),
    );
  }

  bool get _ownsQueue =>
      _sessionMode || (_currentPlaylistTracks?.isNotEmpty ?? false);

  bool _syncPlaybackOptions(PlayerState state) {
    if (_ownsQueue) return false;

    final options = state.playbackOptions;
    final String mode = switch (options.repeatMode.name) {
      'track' => 'track',
      'context' => 'context',
      _ => 'off',
    };

    final bool changed =
        options.isShuffling != _shuffleActive || mode != _repeatMode;
    _shuffleActive = options.isShuffling;
    _repeatMode = mode;
    if (changed) _invalidateNeighbourCache();
    return changed;
  }

  Future<void> _handlePlayerState(PlayerState state) async {
    final incomingUri = state.track?.uri;
    if (incomingUri != null && _shouldIgnoreSdkTrack(incomingUri)) return;

    final bool wasPlaying = _isPlaying;
    final bool optionsChanged = _syncPlaybackOptions(state);
    final int previousDuration = _durationMs;
    final int previousActivePositionMs = _lastActivePositionMs;
    final int previousActiveDurationMs = _lastActiveDurationMs;

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

      final imageUriId = state.track!.imageUri.raw;
      final trackChanged = trackUri != _currentTrack?['uri'];
      final imageChanged = imageUriId != _lastImageUri;
      final title = state.track!.name;
      final artist = state.track!.artist.name;

      if (trackChanged) {
        _releaseSkipLock(notify: false);
        _queueEnrichedUri = null;
        _autoAdvanceGuardUri = null;
      }
      if (!state.isPaused) _confirmQueueAdvance(trackUri);

      final fromQueue =
          _queueEnrichedUri == trackUri ? null : _findInQueue(trackUri);
      if (fromQueue != null) _queueEnrichedUri = trackUri;

      final bool metadataChanged = trackChanged ||
          fromQueue != null ||
          _currentTrack?['title'] != title ||
          _currentTrack?['artist'] != artist;

      if (metadataChanged) {
        final previous = trackChanged
            ? const <String, dynamic>{}
            : (_currentTrack ?? const <String, dynamic>{});
        final keptIndex = _positionOfCurrentIfStillValid(previous, trackUri);

        _currentTrack = {
          ...previous,
          if (fromQueue != null) ...fromQueue,
          if (keptIndex != null) 'index': keptIndex,
          'title': title,
          'artist': artist,
          'uri': trackUri,
        };
      }

      final bool visualChanged = metadataChanged ||
          optionsChanged ||
          wasPlaying != _isPlaying ||
          previousDuration != _durationMs;

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
      } else if (visualChanged) {
        notifyListeners();
      } else {
        // Изменилась только позиция — обновляем её слушателей, а не весь UI.
        _publishPosition();
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

      if (trackChanged) {
        try {
          await _keepPlaybackInsideQueue(
            trackUri,
            previousPositionMs: previousActivePositionMs,
            previousDurationMs: previousActiveDurationMs,
          );
        } catch (e) {
          debugPrint('[PlaybackProvider] Error keeping playback in queue: $e');
        }
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> playTrack(Map<String, dynamic> track,
      {String? playlistId,
      List<dynamic>? knownPlaylistTracks,
      int? positionMs,
      bool fromSession = false,
      bool announceToSession = true}) async {
    final uri = track['uri'] as String?;
    if (uri == null) return;

    _markPendingTrack(uri);
    _lastRequestedUri = uri;
    _playlistEnded = false;

    _positionMs = positionMs ?? 0;
    _positionAnchorAt = DateTime.now();
    _durationMs = (track['durationMs'] as num?)?.toInt() ?? 0;

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
            offset: _contextIndexOf(track),
            offsetUri: contextUri != null ? uri : null,
          );

          if (positionMs != null && positionMs > 0) {
            // Web API отвечает на /play до того, как устройство реально
            // начало трек; seek сразу после этого отбрасывается.
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
              _setPlaylistTracks(knownPlaylistTracks);
            } else {
              try {
                final tracks = await _apiService?.getPlaylistTracks(playlistId);
                _setPlaylistTracks(tracks);
              } catch (e) {
                debugPrint('[PlaybackProvider] Failed to prefetch playlist tracks: $e');
              }
            }
          } else {
            _currentPlaylistId = null;
            _setPlaylistTracks(knownPlaylistTracks);
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
          // SDK принимает skipToIndex только после того, как контекст
          // плейлиста реально загружен; без паузы индекс игнорируется.
          await Future.delayed(const Duration(milliseconds: 500));
        }

        await SpotifySdk.skipToIndex(
          spotifyUri: contextUri,
          trackIndex: _contextIndexOf(track) ?? 0,
        );

        unawaited(_ensureRequestedTrackStarted(uri, positionMs: positionMs));
      } else {
        await SpotifySdk.play(spotifyUri: uri);
      }

      if (positionMs != null && positionMs > 0) {
        // seekTo сразу после play SDK теряет: трек ещё не начал играть.
        await Future.delayed(const Duration(milliseconds: 300));
        await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
      }

      if (playlistId != null) {
        _currentPlaylistId = playlistId.startsWith('spotify:') ? playlistId : 'spotify:playlist:$playlistId';
        if (knownPlaylistTracks != null) {
          _setPlaylistTracks(knownPlaylistTracks);
        } else {
          try {
            final tracks = await _apiService?.getPlaylistTracks(playlistId);
            _setPlaylistTracks(tracks);
          } catch (e) {
            debugPrint('[PlaybackProvider] Failed to prefetch playlist tracks: $e');
          }
        }
      } else {
        _currentPlaylistId = null;
        _setPlaylistTracks(knownPlaylistTracks);
      }

      _currentTrack = track;
      _isPlaying = true;

      if (announceToSession &&
          _currentSessionId != null &&
          !_sessionMode &&
          !_isRemoteSync) {
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

  Future<void> _ensureRequestedTrackStarted(String uri, {int? positionMs}) async {
    if (_isWindows || _isWeb) return;

    for (final delay in const [
      Duration(milliseconds: 600),
      Duration(milliseconds: 700),
    ]) {
      await Future.delayed(delay);
      if (_disposed) return;
      // Пользователь успел нажать другой трек — проверять больше нечего.
      if (_pendingTrackUri != null && _pendingTrackUri != uri) return;

      PlayerState? state;
      try {
        state = await SpotifySdk.getPlayerState();
      } catch (e) {
        debugPrint('[Spotify] Не удалось проверить запущенный трек: $e');
        return;
      }

      final playing = state?.track?.uri;
      if (playing == null) continue;
      if (playing == uri) {
        _markPendingTrack(null);
        await _handlePlayerState(state!);
        return;
      }

      if (state!.playbackOptions.isShuffling) break;
    }

    if (_disposed) return;
    if (_pendingTrackUri != null && _pendingTrackUri != uri) return;

    debugPrint('[Spotify] skipToIndex попал не в тот трек — включаем по uri');
    try {
      await SpotifySdk.play(spotifyUri: uri);
      if (positionMs != null && positionMs > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
      }
    } catch (e) {
      debugPrint('[Spotify] Резервный запуск по uri не удался: $e');
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

    final String? incomingUri = state['item']?['uri'] as String?;
    if (_pendingTrackUri != null && incomingUri != null) {
      if (incomingUri != _pendingTrackUri) return;
      _markPendingTrack(null);
    }

    final String? previousUri = _currentTrack?['uri'] as String?;
    final int? previousIndex = _currentTrack?['index'] as int?;
    final int previousPositionMs = _positionMs;
    final int previousDurationMs = _durationMs;
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
        if (track['uri'] == previousUri && previousIndex != null)
          'index': previousIndex,
      };
      _currentImageBytes = null;

      if (newImageUrl != null && !_paletteCache.containsKey(newImageUrl)) {
        _preloadPalette(newImageUrl);
      }

      final uri = _currentTrack?['uri'] as String?;
      if (uri != null && uri != previousUri) {
        // Сторож снимается только при переходе на действительно новый трек.
        // Если состояние откатилось на тот, с которого мы уже ушли (Web API
        // отвечает с задержкой), снятие сторожа заново разрешало автопереход,
        // и очередь прокручивалась по одному и тому же концу трека.
        if (uri != _autoAdvanceGuardUri) _autoAdvanceGuardUri = null;
        try {
          await _keepPlaybackInsideQueue(
            uri,
            previousPositionMs: previousPositionMs,
            previousDurationMs: previousDurationMs,
          );
        } catch (e) {
          debugPrint('[PlaybackProvider] Error keeping playback in queue: $e');
        }
      }
    }
    notifyListeners();
  }

  void _pollForTrackChange() {
    final oldUri = _currentTrack?['uri'];
    _trackChangeTimer?.cancel();
    _trackChangeRequestInFlight = false;
    int attempts = 0;
    _trackChangeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      // Тик пропускается, пока предыдущий запрос не вернулся: иначе к
      // Spotify уходит очередь параллельных одинаковых запросов.
      if (_trackChangeRequestInFlight) return;

      attempts++;
      if (attempts > 10) {
        timer.cancel();
        return;
      }

      _trackChangeRequestInFlight = true;
      try {
        final state = await _apiService?.getPlayerState();
        if (state == null) return;
        final track = state['item'];
        final newUri = track?['uri'];
        if (newUri != null && newUri != oldUri) {
          timer.cancel();
          _releaseSkipLock();
          _updateFromPlayerState(state);
        }
      } catch (e) {
        debugPrint('[Poll] error: $e');
      } finally {
        _trackChangeRequestInFlight = false;
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

    final found = _indexInQueue(tracks, key);
    if (found < 0) return null;

    return mapSessionTrack(tracks[found], found);
  }

  ({List<dynamic> tracks, int position})? get _activeQueue {
    if (_sessionMode) {
      if (_sessionQueue.isEmpty) return null;

      final key = _trackKeyOf(_currentTrack);
      if (key != null) {
        final found = _indexInQueue(_sessionQueue, key);
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
    final index = _currentTrack?['index'] as int?;

    if (key != null &&
        index != null &&
        index >= 0 &&
        index < tracks.length &&
        _trackKeyOf(tracks[index]) == key) {
      return _rememberQueuePosition(index);
    }

    if (key != null) {
      final found = _indexInQueue(tracks, key);
      if (found >= 0) {
        _currentTrack?['index'] = found;
        return _rememberQueuePosition(found);
      }
    }

    if (index != null && index >= 0 && index < tracks.length) {
      return _rememberQueuePosition(index);
    }

    return null;
  }

  int _rememberQueuePosition(int position) {
    _lastQueuePosition = position;
    return position;
  }

  // Соседей по очереди спрашивают по нескольку раз за кадр (фон, пейджер,
  // прогрев обложек). Нормализуем трек один раз на состояние очереди, чтобы
  // не создавать новую Map на каждый вызов геттера.
  int? _neighbourCacheToken;
  Map<String, dynamic>? _cachedPreviousTrack;
  Map<String, dynamic>? _cachedNextTrack;

  void _invalidateNeighbourCache() => _neighbourCacheToken = null;

  Map<String, dynamic>? _queueNeighbour(int offset) {
    if (!canControlQueue) return null;

    if (_shuffleActive) return null;

    final queue = _activeQueue;
    if (queue == null) return null;

    final token = Object.hash(
      identityHashCode(queue.tracks),
      queue.tracks.length,
      queue.position,
      _repeatMode,
    );

    if (token != _neighbourCacheToken) {
      _neighbourCacheToken = token;
      _cachedPreviousTrack = _normalizedNeighbour(queue, -1);
      _cachedNextTrack = _normalizedNeighbour(queue, 1);
    }

    return offset > 0 ? _cachedNextTrack : _cachedPreviousTrack;
  }

  Map<String, dynamic>? _normalizedNeighbour(
    ({List<dynamic> tracks, int position}) queue,
    int offset,
  ) {
    final target = _resolveQueueIndex(queue, offset, automatic: false);
    if (target == null || target == queue.position) return null;

    return mapSessionTrack(queue.tracks[target], target);
  }

  Future<void> goToNext() => _skip(1);

  Future<void> goToPrevious() => _skip(-1);

  Future<void> handleTrackCompleted() => _stepQueue(1, automatic: true);

  String? get currentPlaylistId => _currentPlaylistId;

  int? get currentQueueIndex =>
      _sessionMode ? _sessionQueueIndex : _queuePosition;

  int? _resolveQueueIndex(
    ({List<dynamic> tracks, int position}) queue,
    int direction, {
    required bool automatic,
  }) {
    final int length = queue.tracks.length;
    if (length == 0) return null;

    final int position = queue.position.clamp(0, length - 1);

    if (automatic && _repeatMode == 'track') return position;

    if (_shuffleActive) return _randomQueueIndex(length, position);

    final int target = position + direction;
    if (target >= 0 && target < length) return target;

    if (_repeatMode != 'off') return target < 0 ? length - 1 : 0;

    if (direction < 0) return position;

    return null;
  }

  int _randomQueueIndex(int length, int current) {
    if (length <= 1) return 0;

    final rnd = Random();
    int index = rnd.nextInt(length);
    int attempts = 0;
    while (index == current && attempts < 6) {
      index = rnd.nextInt(length);
      attempts++;
    }
    return index;
  }

  Future<bool> _stepQueue(int direction, {required bool automatic}) async {
    if (!canControlQueue) return false;

    if (_sessionMode) {
      if (direction > 0) {
        await _advanceSessionQueue();
      } else if (_sessionQueueIndex > 0) {
        await playSessionTrack(_sessionQueueIndex - 1);
      }
      return true;
    }

    if (_currentPlaylistId != null && _currentPlaylistTracks == null) {
      await _ensurePlaylistTracksLoaded();
    }

    final queue = _activeQueue;
    if (queue == null) {
      return _currentPlaylistId != null || _currentPlaylistTracks != null;
    }

    final target = _resolveQueueIndex(queue, direction, automatic: automatic);
    if (target == null) {
      await _stopAtPlaylistEnd();
      return true;
    }

    await _playQueueIndex(queue.tracks, target);
    return true;
  }

  Future<void> _playQueueIndex(List<dynamic> tracks, int index) async {
    if (index < 0 || index >= tracks.length) return;

    final track = mapSessionTrack(tracks[index], index);
    if ((track['uri'] as String?)?.isNotEmpty != true) return;

    _playlistEnded = false;
    _lastQueuePosition = index;

    _autoAdvanceGuardUri = _currentTrack?['uri'] as String? ?? _autoAdvanceGuardUri;

    final generation = ++_autoCorrectionGeneration;
    _suppressAutoCorrection = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (generation == _autoCorrectionGeneration) {
        _suppressAutoCorrection = false;
      }
    });

    await playTrack(
      track,
      playlistId: _currentPlaylistId == null
          ? null
          : _plainPlaylistId(_currentPlaylistId!),
      knownPlaylistTracks: tracks,
    );
  }

  Future<void> _stopAtPlaylistEnd() async {
    _playlistEnded = true;
    _isPlaying = false;
    _positionAnchorAt = null;
    _releaseSkipLock(notify: false);
    notifyListeners();

    try {
      if (_isWindows || _isWeb) {
        await _apiService?.pausePlayback();
      } else {
        await SpotifySdk.pause();
      }
    } catch (e) {
      debugPrint('[Playback] Не удалось остановить плеер в конце плейлиста: $e');
    }
  }

  bool _spotifyContinuesQueueAfter(
      ({List<dynamic> tracks, int position}) queue) {
    if (_repeatMode == 'track') return true;

    if (_currentPlaylistId == null) return false;

    if (_shuffleActive) return true;

    return queue.position < queue.tracks.length - 1;
  }

  void _checkSoloTrackEnd() {
    if (_sessionMode || !_isPlaying || _playlistEnded) return;
    if (_isSkipping || _suppressAutoCorrection) return;
    if (_pendingTrackUri != null) return;
    if (_durationMs <= 0) return;

    final uri = _currentTrack?['uri'] as String?;
    if (uri == null || uri == _autoAdvanceGuardUri) return;

    final queue = _activeQueue;
    if (queue == null) return;
    if (_spotifyContinuesQueueAfter(queue)) return;

    if (positionMs < _durationMs - _trackEndLeadMs) return;

    _autoAdvanceGuardUri = uri;
    unawaited(handleTrackCompleted());
  }

  static const int _outsideQueueToleranceMs = 5000;

  Future<void> _keepPlaybackInsideQueue(
    String uri, {
    required int previousPositionMs,
    required int previousDurationMs,
  }) async {
    if (_sessionMode || _suppressAutoCorrection || !canControlQueue) return;

    if (_lastRequestedUri != null &&
        _trackKeyOf({'uri': uri}) == _trackKeyOf({'uri': _lastRequestedUri})) {
      return;
    }

    final tracks = _currentPlaylistTracks;
    if (tracks == null || tracks.isEmpty) return;
    if (_indexInQueue(tracks, _trackKeyOf({'uri': uri})) >= 0) return;

    final position = _lastQueuePosition;
    if (position < 0 || position >= tracks.length) return;

    if (previousDurationMs <= 0) return;
    if (previousPositionMs < previousDurationMs - _outsideQueueToleranceMs) {
      return;
    }

    final target = _resolveQueueIndex(
      (tracks: tracks, position: position),
      1,
      automatic: true,
    );

    debugPrint('[Playback] Spotify ушёл из плейлиста — возвращаем очередь');

    if (target == null) {
      await _stopAtPlaylistEnd();
      return;
    }

    await _playQueueIndex(tracks, target);
  }

  Color? dominantColorForUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return _paletteCache[url]?.dominantColor?.color;
  }

  Color? mutedColorForUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    // Палитра этого запуска или цвет, сохранённый с прошлого: фон плеера
    // должен быть правильным с первого кадра, а не после расчёта.
    final base = _paletteCache[url]?.dominantColor?.color ??
        ArtworkColorStore.cached(url);
    if (base == null) return null;

    return _shadeArtworkColor(base);
  }

  static Color _shadeArtworkColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.6))
        .withLightness(0.28)
        .toColor();
  }

  /// Только ближайшие соседи: следующий трек важнее предыдущего, всё, что
  /// дальше, греть незачем — это лишние загрузки и лишние палитры.
  List<String> get neighbourArtworkUrls {
    if (_shuffleActive) return const [];

    final next = nextQueueTrack;
    final previous = previousQueueTrack;
    if (next == null && previous == null) return const [];

    final urls = <String>[];
    final nextUrl = next?['imageUrl'] as String?;
    if (nextUrl != null && nextUrl.isNotEmpty) urls.add(nextUrl);

    final previousUrl = previous?['imageUrl'] as String?;
    if (previousUrl != null && previousUrl.isNotEmpty) urls.add(previousUrl);

    return urls;
  }

  void _setArtworkColor(Color? color) {
    if (_artworkColor == color) return;
    _artworkColor = color;
    if (_disposed) return;

    // Цвет обложки — точечное обновление: перестраиваются только фон и
    // мини-плеер, а не весь UI, подписанный на провайдер. ensureArtworkColor
    // вызывается из build, поэтому сброс цвета переносим за кадр.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) artworkColorNotifier.value = _artworkColor;
      });
      return;
    }

    artworkColorNotifier.value = color;
  }

  void ensureArtworkColor() {
    final track = _currentTrack;
    if (track == null) {
      if (_artworkColor != null) {
        _setArtworkColor(null);
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
    if (url != null && url.isNotEmpty) {
      final known = ArtworkColorStore.cached(url);
      if (known != null) {
        if (key != _artworkColorPending) return;
        _artworkColorKey = key;
        _setArtworkColor(_shadeArtworkColor(known));
        _artworkColorPending = null;
        return;
      }
    }

    final ImageProvider provider;
    if (bytes != null) {
      provider = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      provider = AppImageCache.provider(url);
    } else {
      return;
    }

    try {
      final palette = await _generatePalette(key, provider);
      if (palette == null) return;

      if (key != _artworkColorPending) return;

      final base = palette.dominantColor?.color;
      if (base == null) return;

      _artworkColorKey = key;
      if (url != null && url.isNotEmpty) ArtworkColorStore.remember(url, base);

      _setArtworkColor(_shadeArtworkColor(base));
    } catch (err) {
      debugPrint('Не удалось получить цвет обложки: $err');
    } finally {
      if (key == _artworkColorPending) _artworkColorPending = null;
    }
  }

  /// Одна картинка — максимум один одновременно работающий PaletteGenerator:
  /// повторные запросы получают тот же Future, а не второй тяжёлый расчёт.
  Future<PaletteGenerator?> _generatePalette(String key, ImageProvider provider) {
    final cached = _paletteCache[key];
    if (cached != null) return Future<PaletteGenerator?>.value(cached);

    final running = _palettePending[key];
    if (running != null) return running;

    final future = _runPaletteGeneration(key, provider);
    _palettePending[key] = future;
    return future;
  }

  Future<PaletteGenerator?> _runPaletteGeneration(
    String key,
    ImageProvider provider,
  ) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(64, 64),
        maximumColorCount: 8,
      );
      final dominant = palette.dominantColor?.color;
      if (dominant != null && key.startsWith('http')) {
        ArtworkColorStore.remember(key, dominant);
      }
      // Готовая палитра не перестраивает весь UI: об этом узнают только
      // потребители цвета (paletteVersion / artworkColorNotifier).
      _cachePalette(key, palette);
      return palette;
    } catch (err) {
      debugPrint('[SyncM] Палитра обложки не рассчиталась: $err');
      return null;
    } finally {
      _palettePending.remove(key);
    }
  }


  Future<PaletteGenerator?> paletteFor({
    String? imageUrl,
    Uint8List? imageBytes,
    String? fallbackKey,
  }) {
    final String? url =
        (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null;
    final String? key = url ?? fallbackKey;
    if (key == null) return Future<PaletteGenerator?>.value(null);

    final ImageProvider? image = url != null
        ? AppImageCache.provider(url)
        : (imageBytes != null ? MemoryImage(imageBytes) : null);
    if (image == null) return Future<PaletteGenerator?>.value(null);

    return _generatePalette(key, image);
  }

  void preloadPalettes(Iterable<String> urls) {
    for (final url in urls) {
      if (url.isEmpty ||
          _paletteCache.containsKey(url) ||
          _palettePending.containsKey(url)) {
        continue;
      }
      _preloadPalette(url);
    }
  }

  /// Палитра считается на UI-изоляте, поэтому предзагрузка соседей ставится
  /// в очередь планировщика с низким приоритетом: во время drag/spring кадры
  /// важнее, чем цвет соседней обложки.
  void _preloadPalette(String imageUrl) {
    SchedulerBinding.instance.scheduleTask<void>(
      () {
        if (_disposed || _paletteCache.containsKey(imageUrl)) return;
        unawaited(_generatePalette(imageUrl, AppImageCache.provider(imageUrl)));
      },
      Priority.idle,
    );
  }

  Timer? _skipLockTimer;

  /// Замок скипа снимается по факту смены трека (событие player state или
  /// REST-поллинг). Таймер — только страховка, если событие не придёт.
  static const _skipLockTimeout = Duration(milliseconds: 1500);

  void _acquireSkipLock() {
    _isSkipping = true;
    _skipLockTimer?.cancel();
    _skipLockTimer = Timer(_skipLockTimeout, _releaseSkipLock);
  }

  void _releaseSkipLock({bool notify = true}) {
    _skipLockTimer?.cancel();
    _skipLockTimer = null;
    if (!_isSkipping) return;
    _isSkipping = false;
    if (notify) notifyListeners();
  }

  Future<void> skipNext() => _skip(1);

  Future<void> skipPrevious() => _skip(-1);

  /// Переключение трека пользователем.
  ///
  /// Раньше отсюда сразу уходила команда Spotify, и на последнем треке
  /// плейлиста «следующим» становился его автоплей. Теперь решение всегда
  /// принимает очередь; к плееру напрямую обращаемся, только если очереди
  /// нет вовсе — трек играет сам по себе, вне какого-либо плейлиста.
  Future<void> _skip(int direction) async {
    if (_isSkipping) return;
    _acquireSkipLock();

    try {
      _positionMs = 0;
      _positionAnchorAt = DateTime.now();
      _autoAdvanceGuardUri = null;
      notifyListeners();

      if (await _stepQueue(direction, automatic: false)) return;

      await _skipExternally(direction);
    } catch (e) {
      debugPrint('[Playback] Skip error: $e');
      _releaseSkipLock();
    }
  }

  Future<void> _skipExternally(int direction) async {
    if (_isWindows || _isWeb) {
      if (direction > 0) {
        await _apiService?.skipToNext();
      } else {
        await _apiService?.skipToPrevious();
      }
      _pollForTrackChange();
      return;
    }

    if (direction > 0) {
      await SpotifySdk.skipNext();
    } else {
      await SpotifySdk.skipPrevious();
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
        _setPlaylistTracks(tracks);
      }
    } catch (e) {
      debugPrint('[PlaybackProvider] Could not load playlist tracks: $e');
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
    _setPlaylistTracks(null);
    _suppressAutoCorrection = false;
    _playlistEnded = false;
    _lastQueuePosition = -1;
    _autoAdvanceGuardUri = null;
    _sessionMode = false;
    _setSessionQueue([]);
    _sessionQueueIndex = -1;
    _queueEnded = false;
    _syncPositionTicker();
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
        // Пауза сразу после /play не доходит до устройства: трек должен
        // успеть встать в позицию 0, иначе client_ready уйдёт впустую.
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
            : appL10n?.playbackOpenSpotifyHint ??
                'Откройте Spotify и запустите любой трек, затем повторите.';
        onPrepareError?.call(msg);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    _positionTicker?.cancel();
    _positionTicker = null;
    _sessionSeekingTimer?.cancel();
    _advanceResetTimer?.cancel();
    _skipLockTimer?.cancel();
    _pendingResolveTimer?.cancel();

    _sessionSubscriptions.cancelAll();
    _playerStateSub?.cancel();

    positionNotifier.dispose();
    artworkColorNotifier.dispose();
    paletteVersion.dispose();

    super.dispose();
  }
}
