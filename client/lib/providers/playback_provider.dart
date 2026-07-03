import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:palette_generator/palette_generator.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import '../services/api_service.dart';
import '../config.dart';
import '../services/socket_service.dart';

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
  bool _isAdvancingQueue = false; // Защита от спама переключений
  // Последние известные позиция/длительность ДО паузы (Android/spotify_sdk).
  // Нужны, т.к. state.playbackPosition в момент самой паузы после
  // естественного завершения трека часто уже сброшен в 0.
  int _lastActivePositionMs = 0;
  int _lastActiveDurationMs = 0;
  // Сохранённая громкость на время "preview-play" при подготовке трека
  // (Windows/Web). См. handleServerPrepare и обработчик session_start.
  int? _preMuteVolume;

  SocketService? _socketService;
  String? _currentSessionId;
  String? _userId;
  String? _preparedTrackId;
  bool _isReadySent = false;
  bool _isSeekingFromRemote = false;
  bool _isSkipping = false;
  DateTime? _lastToggle;

  bool _shuffleActive = false;
  String _repeatMode = 'off';

  // Current Spotify playlist context (when playing from a playlist)
  String? _currentPlaylistId;
  List<dynamic>? _currentPlaylistTracks;
  // Prevents automatic correction loops when we programmatically switch tracks
  bool _suppressAutoCorrection = false;

  // Session queue playback
  List<Map<String, dynamic>> _sessionQueue = [];
  int _sessionQueueIndex = -1;
  bool _sessionMode = false;
  bool _sessionPaused = false;
  bool _isHost = false;
  bool _isRemoteSync = false;
  bool _queueEnded = false;
  SessionTracksCallback? onTracksAdded;
  SessionPlaybackCallback? onSessionPlaybackStarted;

  List<Map<String, dynamic>> get sessionQueue => List.unmodifiable(_sessionQueue);
  int get sessionQueueIndex => _sessionQueueIndex;
  bool get sessionMode => _sessionMode;
  bool get queueEnded => _queueEnded;

  Map<String, dynamic>? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isConnected => _isConnected;
  int get durationMs => _durationMs;
  int get positionMs => _positionMs;
  Uint8List? get currentImageBytes => _currentImageBytes;

  bool get shuffleActive => _shuffleActive;
  String get repeatMode => _repeatMode;
  bool get repeatActive => _repeatMode != 'off';

  final Map<String, PaletteGenerator> _paletteCache = {};
  Map<String, PaletteGenerator> get paletteCache => _paletteCache;

  static const _clientId = '809ce8e069a64cb5970c20e356024786';
  static const _redirectUrl = 'syncm://callback';

  String get _socketUrl => _apiService?.baseUrl ?? Config.baseUrl;

  void setApiService(ApiService api) {
    _apiService = api;
  }

  static Map<String, dynamic> mapSessionTrack(dynamic raw, int index) {
    final t = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      'id': t['id'],
      'uri': t['spotifyUri'] ?? t['uri'],
      'title': t['trackName'] ?? t['title'] ?? t['name'] ?? '',
      'artist': t['artistName'] ?? t['artist'] ?? '',
      'imageUrl': t['imageUrl'],
      'durationMs': t['durationMs'],
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

    // Сразу обновляем позицию/длительность чтобы _checkSessionTrackEnd
    // не сработал повторно на старых значениях предыдущего трека
    _positionMs = positionMs ?? 0;
    _durationMs = (track['durationMs'] as num?)?.toInt() ?? 0;
    notifyListeners();

    if (syncToSession && !_isRemoteSync && _currentSessionId != null) {
      final trackId = (track['uri'] as String).split(':').last;
      _socketService?.emit('session_prepare', {
        'sessionId': _currentSessionId,
        'trackId': trackId,
        'durationMs': track['durationMs'],
      });
      // Не вызываем playTrack напрямую — пусть session_start запустит воспроизведение
      // для всех участников включая хоста. Иначе трек играет трижды:
      // 1) прямой вызов, 2) handleServerPrepare (play+pause), 3) session_start.
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
    // _isAdvancingQueue уже установлен вызывающей стороной
    // (_checkSessionTrackEnd или _subscribeToPlayerState) перед вызовом этого метода
    try {
      final next = _sessionQueueIndex + 1;
      if (next < _sessionQueue.length) {
        await playSessionTrack(next, syncToSession: true);
      } else {
        await _stopAtQueueEnd();
      }
    } finally {
      _isAdvancingQueue = false;
    }
  }

  Future<void> _stopAtQueueEnd() async {
    _queueEnded = true;
    _isPlaying = false;
    _sessionPaused = true;
    await _restoreVolumeIfMuted(); // страховка на случай прерванного хендшейка
    if (_isWindows || _isWeb) {
      try {
        await _apiService?.pausePlayback();
      } catch (_) {}
    } else {
      try {
        await SpotifySdk.pause();
      } catch (_) {}
    }
    // Раньше при завершении очереди мы останавливали только СВОЙ (хостский)
    // плеер и никого не оповещали — из-за этого у остальных участников
    // музыка продолжала играть до бесконечности. Рассылаем паузу всем через
    // тот же session_command, что использует togglePlay.
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
      _isAdvancingQueue = true; // Ставим флаг ДО вызова async метода
      _advanceSessionQueue();
    }
  }

  void _startPolling() {
    if (_apiService == null) return;

    _pollingTimer?.cancel();
    int tickCount = 0;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isPlaying) return;

      if (_isPlaying && _durationMs > 0) {
        _positionMs = (_positionMs + 500).clamp(0, _durationMs);
        _checkSessionTrackEnd();
        notifyListeners();
      }

      tickCount++;
      // В режиме сессии позицию/длительность/трек ведёт исключительно сервер
      // (session_start/session_sync) и локальный тикер выше. "Сырой" опрос
      // Spotify Device API здесь опасен: во время хендшейка перехода на
      // следующий трек (session_prepare → client_ready → session_start)
      // физическое устройство ещё доигрывает СТАРЫЙ трек, и этот опрос может
      // затереть только что сброшенные _positionMs/_durationMs его
      // устаревшими значениями "конец трека" — из-за чего _checkSessionTrackEnd
      // срабатывает повторно и вызывает бесконечный скип очереди.
      if (tickCount % 6 == 0 && !_sessionMode) {
        try {
          final state = await _apiService?.getPlayerState();
          if (state == null) return;
          if (_sessionPaused) return;
          _isPlaying = state['is_playing'] ?? false;
          _positionMs = state['progress_ms'] ?? 0;
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
          print('[Polling] error: $e');
        }
      }
    });
  }

  void initSession(String sessionId, String userId, SocketService socketService, {bool isHost = false}) {
    _isHost = isHost;
    _currentSessionId = sessionId;
    _userId = userId;
    _socketService = socketService;

    // Сокет — общий синглтон, а SessionScreen может пересоздаваться
    // (повторный вход в экран, ребилд под другой layout, hot reload и т.п.).
    // Без явной очистки старые обработчики остаются висеть на сокете, и
    // ОДНО серверное событие (например session_prepare) обрабатывается
    // несколько раз подряд — это и вызывало повторные "скипы" трека.
    for (final event in const [
      'session_prepare',
      'session_start',
      'session_sync',
      'session_pause',
      'session_resume',
      'session_state',
      'session_play',
      'play',
      'seek',
      'tracks-added',
    ]) {
      socketService.off(event);
    }

    socketService.emit('join_session', {'sessionId': sessionId});

    // ─── Фаза 2: Получаем команду подготовить трек ─────────────────────────
    socketService.on('session_prepare', handleServerPrepare);

    // ─── Фаза 3: Синхронный старт ───────────────────────────────────────────
    socketService.on('session_start', (data) async {
      _sessionPaused = false;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final trackId = map['trackId'] as String?;
      final startAt = (map['startAt'] as num?)?.toInt(); // серверное время старта
      final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;

      if (trackId == null || startAt == null) return;

      // Переводим серверное время в локальное с защитой от double
      final dynamic rawLocalStart = socketService.serverToLocal(startAt);
      final int localStart = rawLocalStart is num ? rawLocalStart.round() : startAt;
      final now = DateTime.now().millisecondsSinceEpoch;
      final int delayMs = localStart - now;

      if (delayMs < -1000) {
        // Опоздали — режим восстановления
        final int actualPos = positionMs + (now - localStart).abs();
        await _playAtPosition(trackId, actualPos);
        await _restoreVolumeIfMuted();
        socketService.emit('resync', {'sessionId': sessionId});
        return;
      }

      // Ждём до localStart с высокоточным таймером
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      await _playAtPosition(trackId, positionMs);
      await _restoreVolumeIfMuted();
    });

    // ─── Фаза 4: Периодическая синхронизация ────────────────────────────────
    socketService.on('session_sync', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final positionMs = (map['positionMs'] as num?)?.toInt();
      final serverTime = (map['serverTime'] as num?)?.toInt();

      if (positionMs == null || serverTime == null || !_isPlaying) return;

      // Вычисляем ожидаемую позицию с защитой от double
      final dynamic rawCurrentServerTime = socketService.currentServerTime;
      final int currentServerTime =
          rawCurrentServerTime is num ? rawCurrentServerTime.round() : DateTime.now().millisecondsSinceEpoch;
      final int expectedPos = positionMs + (currentServerTime - serverTime);
      final int drift = (expectedPos - _positionMs).abs();

      // Если расхождение > 500мс — корректируем
      if (drift > 500 && _isPlaying) {
        _positionMs = expectedPos;
        notifyListeners();
        if (!_isWindows && !_isWeb && _isConnected) {
          // Мобильные
          SpotifySdk.seekTo(positionedMilliseconds: expectedPos).catchError((_) {});
        } else if (_isWindows || _isWeb) {
          // Раньше здесь корректировалась только цифра в UI (_positionMs выше),
          // а РЕАЛЬНОЕ воспроизведение в Spotify не трогалось вообще — из-за
          // этого дрейф между устройствами накапливался и никогда не лечился
          // сам собой в течение сессии. Теперь физически подтягиваем позицию
          // и на Windows/Web тоже, той же командой, что и ручная перемотка.
          final svc = _apiService;
          if (svc != null) {
            svc.seekToPosition(expectedPos).catchError((e) {
              print('[SyncM] session_sync авто-коррекция позиции не удалась: $e');
            });
          }
        }
      }
    });

    // ─── Фаза 5: Пауза от сервера ───────────────────────────────────────────
    socketService.on('session_pause', (data) async {
      print('[Socket] Получен session_pause: $data');
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final positionMs = (map['positionMs'] as num?)?.toInt();

      _isPlaying = false;
      _sessionPaused = true;
      if (positionMs != null) _positionMs = positionMs;
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
    });

    socketService.on('session_resume', (data) async {
      _sessionPaused = false;
      if (!_isPlaying) {
        // Получатель: нужно возобновить воспроизведение
        _isPlaying = true;
        notifyListeners();
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } catch (e) {
          print('[Socket] Resume error: $e');
        }
      } else {
        // Отправитель: уже возобновили локально в togglePlay, просто уведомляем UI
        notifyListeners();
      }
    });

    // ─── Фаза 6: Полное состояние при подключении/переподключении ──────────
    socketService.on('session_state', (data) async {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final state = map['state'] as String?;
      final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
      final serverTime = (map['serverTime'] as num?)?.toInt();
      final trackId = map['trackId'] as String?;

      if (trackId == null) return;

      if (state == 'playing' && serverTime != null) {
        // Вычисляем актуальную позицию с защитой от double
        final dynamic rawCurrentServerTime = socketService.currentServerTime;
        final int currentServerTime =
            rawCurrentServerTime is num ? rawCurrentServerTime.round() : DateTime.now().millisecondsSinceEpoch;
        final int actualPos = positionMs + (currentServerTime - serverTime);
        await _playAtPosition(trackId, actualPos);
      } else if (state == 'paused') {
        _positionMs = positionMs;
        _isPlaying = false;
        notifyListeners();
      }
    });

    // Обратная совместимость
    socketService.on('session_play', (data) {
      if (data is Map) handleSessionPlayEvent(Map<String, dynamic>.from(data));
    });

    // ─── Исправленный блок Паузы / Возобновления ───────────────────────────
    socketService.on('play', (data) async {
      _sessionPaused = false;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final String? uri = map['spotifyUri'] as String?;
      final int? pos = (map['position_ms'] as num?)?.toInt();

      if (uri == null) return;
      print('[Socket Play] Сервер приказал включить трек: $uri');

      // Ищем полную инфу о треке (с картинкой и именем), сохранённую в очереди сессии
      Map<String, dynamic> fullTrackData = {'uri': uri};
      final index = _sessionQueue.indexWhere((t) => t['uri'] == uri);

      if (index >= 0) {
        fullTrackData = Map<String, dynamic>.from(_sessionQueue[index]);
        _sessionQueueIndex = index;
      }

      if (uri != _currentTrack?['uri']) {
        // Меняем трек и принудительно прокидываем fullTrackData, чтобы обновилась картинка
        _currentTrack = fullTrackData;
        notifyListeners(); // Сразу перерисовываем UI (картинку)

        await playTrack(fullTrackData, positionMs: pos, fromSession: true);
      } else {
        // Если трек тот же — просто снимаем с паузы
        _isPlaying = true;
        notifyListeners();
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } catch (e) {
          print('Ошибка снятия с паузы в сессии: $e');
        }
      }
    });

    // ─── Исправленный блок Перемотки (Без зацикливания) ───────────────────
    socketService.on('seek', (data) async {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final int pos = (map['position_ms'] as num?)?.toInt() ?? 0;

      print('[Socket] Получена глобальная перемотка на: $pos мс');
      _isSeekingFromRemote = true;
      _positionMs = pos;
      notifyListeners();

      // ВАЖНО: Управляем плеером НАПРЯМУЮ, не вызывая метод кнопки seekTo(),
      // чтобы приложение не отправляло команду обратно на сервер
      try {
        if (!_isWindows && !_isWeb && _isConnected) {
          await SpotifySdk.seekTo(positionedMilliseconds: pos);
        } else if (_isWindows || _isWeb) {
          await _apiService?.seekToPosition(pos);
        }
      } catch (e) {
        print('[Socket Seek] Ошибка физической перемотки: $e');
      } finally {
        await Future.delayed(const Duration(milliseconds: 300));
        _isSeekingFromRemote = false;
      }
    });

    socketService.on('tracks-added', (data) {
      if (data is Map) onTracksAdded?.call(Map<String, dynamic>.from(data));
    });
  }

  // Возвращает громкость назад после того, как приглушали её на время
  // технического "preview-play" в handleServerPrepare (Windows/Web).
  Future<void> _restoreVolumeIfMuted() async {
    if (!_isWindows && !_isWeb) return;
    final vol = _preMuteVolume;
    if (vol == null) return;
    _preMuteVolume = null;
    try {
      await _apiService?.setVolume(vol);
    } catch (e) {
      print('[SyncM] Volume restore error: $e');
    }
  }

  // Вспомогательный метод воспроизведения в позиции
  Future<void> _playAtPosition(String uriOrId, int positionMs) async {
    // Принимаем и полный URI (spotify:track:xxx) и просто ID (xxx)
    final fullUri = uriOrId.startsWith('spotify:') ? uriOrId : 'spotify:track:$uriOrId';
    final index = _sessionQueue.indexWhere((t) => t['uri'] == fullUri);
    if (index < 0) return;

    _sessionMode = true;
    _sessionQueueIndex = index;
    _positionMs = positionMs;

    final track = Map<String, dynamic>.from(_sessionQueue[index]);
    await playTrack(track, positionMs: positionMs, fromSession: true);
  }

  // Предзагрузка трека (подготовка без воспроизведения)
  Future<void> _prepareTrack(Map<String, dynamic> track, int index) async {
    _preparedTrackId = track['uri'] as String?;
  }

  Future<bool> connect() async {
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
      notifyListeners();
      return _isConnected;
    } catch (e) {
      print('[Spotify] Connect error: $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  void _subscribeToPlayerState() {
    SpotifySdk.subscribePlayerState().listen((PlayerState state) async {
      _isPlaying = !state.isPaused;
      _durationMs = state.track?.duration ?? 0;
      _positionMs = state.playbackPosition;

      // Запоминаем последнюю позицию/длительность ДО паузы. Многие плееры
      // (включая Spotify SDK) при естественном завершении трека шлют
      // isPaused=true с playbackPosition, сброшенной в 0 — из-за этого
      // проверка "конец ли это трека" ниже не должна опираться на
      // state.playbackPosition в момент самой паузы, а на последнее известное
      // значение непосредственно перед ней.
      if (!state.isPaused) {
        _lastActivePositionMs = state.playbackPosition;
        if (state.track != null) _lastActiveDurationMs = state.track!.duration;
      }

      if (state.track != null) {
        final trackUri = state.track!.uri;
        final imageUriId = state.track!.imageUri.raw;
        final trackChanged = trackUri != _currentTrack?['uri'];
        final imageChanged = imageUriId != _lastImageUri;

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
            print('[Spotify] Ошибка скачивания обложки: $e');
            _currentImageBytes = null;
            notifyListeners();
          }
        } else {
          notifyListeners();
        }

        // Фаза 2.2: Проверка готовности
        if (_preparedTrackId != null && !_isReadySent) {
          final activeTrackId = trackUri.split(':').last;
          if (activeTrackId == _preparedTrackId && state.isPaused) {
            _isReadySent = true;
            print('[SyncPlay] Spotify загрузил трек. Отправляем client_ready');
            _socketService?.emit('client_ready', {
              'sessionId': _currentSessionId,
              'trackId': _preparedTrackId,
            });
          }
        }

        _currentTrack = {
          ..._currentTrack ?? {},
          'title': state.track!.name,
          'artist': state.track!.artist.name,
          'uri': trackUri,
        };

        if (trackChanged && _currentSessionId != null && !_sessionMode) {
          _socketService?.emit('next_track', {
            'sessionId': _currentSessionId,
            'spotifyUri': trackUri,
          });
        }

        // Автопереключение очереди — только если флаг ещё не стоит.
        // Исключаем случай, когда пауза вызвана НАМЕРЕННО из handleServerPrepare
        // (play+pause для предзагрузки следующего трека) — иначе это тоже
        // прочитается как "конец трека" и вызовет повторный/ложный скип.
        final bool isIntentionalPreparePause = _preparedTrackId != null && !_isReadySent;
        if (_sessionMode &&
            _isHost &&
            state.isPaused &&
            !_isAdvancingQueue &&
            !isIntentionalPreparePause) {
          final dur = _lastActiveDurationMs;
          if (dur > 0 && _lastActivePositionMs >= dur - 1200) {
            print('[SyncM] Трек завершился. Переключаем...');
            _isAdvancingQueue = true; // Ставим флаг ДО вызова async метода
            _advanceSessionQueue();
          }
        }

        // Shuffle коррекция только вне session mode
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
            print('[PlaybackProvider] Error validating track against playlist: $e');
          }
        }
      } else {
        notifyListeners();
      }
    }, onError: (err) => print('[Spotify] PlayerState stream error: $err'));
  }

  Future<void> playTrack(Map<String, dynamic> track,
      {String? playlistId, int? positionMs, bool fromSession = false}) async {
    final uri = track['uri'] as String?;
    if (uri == null) return;

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

          _currentTrack = track;
          _isPlaying = true;

          if (playlistId != null) {
            _currentPlaylistId = playlistId.startsWith('spotify:') ? playlistId : 'spotify:playlist:$playlistId';
            try {
              final tracks = await _apiService?.getPlaylistTracks(playlistId);
              _currentPlaylistTracks = tracks;
            } catch (e) {
              print('[PlaybackProvider] Failed to prefetch playlist tracks: $e');
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
          print('[Web/Windows] Play error: $e');
        }
        return;
      }

      if (playlistId != null) {
        final contextUri = playlistId.startsWith('spotify:') ? playlistId : 'spotify:playlist:$playlistId';
        await SpotifySdk.play(spotifyUri: contextUri);
        await Future.delayed(const Duration(milliseconds: 500));
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
        try {
          final tracks = await _apiService?.getPlaylistTracks(playlistId);
          _currentPlaylistTracks = tracks;
        } catch (e) {
          print('[PlaybackProvider] Failed to prefetch playlist tracks: $e');
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
      print('[Spotify] Play error: $e');
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
        print('[Spotify] Fallback play error: $e2');
      }
    }
  }

  Future<void> togglePlay() async {
    final now = DateTime.now();
    if (_lastToggle != null && now.difference(_lastToggle!) < const Duration(milliseconds: 500)) return;
    _lastToggle = now;

    if (_sessionMode && _currentSessionId != null) {
      if (_isPlaying) {
        print('[Socket] Пауза → session_command');
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
          print('[togglePlay] local pause error: $e');
        }
        _socketService?.emit('session_command', {
          'sessionId': _currentSessionId,
          'action': 'pause',
        });
      } else {
        print('[Socket] Возобновление → session_command');
        _sessionPaused = false;
        _isPlaying = true;
        notifyListeners();
        // Возобновляем локально немедленно, не ждём эха от сервера
        try {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } catch (e) {
          print('[togglePlay] local resume error: $e');
        }
        _socketService?.emit('session_command', {
          'sessionId': _currentSessionId,
          'action': 'resume',
        });
      }
      return;
    }

    // Соло-режим
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
      print('[Solo Play/Pause] Ошибка: $e');
    }
  }

  Future<void> _updateFromPlayerState(dynamic state) async {
    if (state == null) return;
    _isPlaying = state['is_playing'] ?? false;
    _positionMs = state['progress_ms'] ?? 0;
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
          print('[PlaybackProvider] Error checking playlist membership: $e');
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
        print('[Poll] error: $e');
      }
    });
  }

  Future<void> _preloadPalette(String imageUrl) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        size: const Size(200, 200),
        maximumColorCount: 16,
      );
      _paletteCache[imageUrl] = palette;
      notifyListeners();
    } catch (e) {
      print('Preload palette error: $e');
    }
  }

  Future<void> skipNext() async {
    if (_isSkipping) return; // Если уже в процессе скипа, игнорируем повторные вызовы
    _isSkipping = true;

    try {
      if (_sessionMode) {
        await _advanceSessionQueue();
        return;
      }

      _positionMs = 0;
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
        // Spotify сам переключает трек по окончании текущего.
        // Ручной вызов нужен только при нажатии на кнопку.
        await SpotifySdk.skipNext();
      }
    } catch (e) {
      print('Skip next error: $e');
    } finally {
      // Искусственная задержка, чтобы дать плееру время обновить метаданные
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
        print('[Web/Windows] Skip previous error: $e');
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
      print('[Spotify] Skip previous error: $e');
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
      print('[PlaybackProvider] Could not load playlist tracks: $e');
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
      print('[PlaybackProvider] _playRandomFromCurrentPlaylist error: $e');
    }
  }

  Future<void> seekTo(int positionMs) async {
    _positionMs = positionMs;
    notifyListeners();

    // Если мы в сессии — сначала физически перематываем СВОЙ плеер (сервер
    // рассылает 'seek' остальным участникам, но не отправителю — см. socket.js,
    // там используется socket.to(), исключающий текущий сокет), затем уведомляем
    // сервер, чтобы он разослал перемотку остальным.
    if (_sessionMode && _currentSessionId != null) {
      if (_isSeekingFromRemote) return; // Не отправляем обратно эхо от удалённой перемотки

      try {
        if (_isWindows || _isWeb) {
          await _apiService?.seekToPosition(positionMs);
        } else {
          await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
        }
      } catch (e) {
        // Частая причина сбоя здесь — временное отсутствие активного
        // устройства Spotify сразу после паузы (например, во время
        // хендшейка session_prepare/session_start). Раньше сервер отвечал
        // success:true ещё до реального запроса к Spotify, поэтому такие
        // сбои были не видны — ползунок визуально двигался, а звук нет.
        // Теперь ошибка доходит до клиента, и мы даём одну повторную попытку
        // с небольшой задержкой перед тем, как сдаться.
        print('[Session Seek] Ошибка локальной перемотки, повтор через 400мс: $e');
        try {
          await Future.delayed(const Duration(milliseconds: 400));
          if (_isWindows || _isWeb) {
            await _apiService?.seekToPosition(positionMs);
          } else {
            await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
          }
        } catch (e2) {
          print('[Session Seek] Повторная попытка тоже не удалась: $e2');
        }
      }

      _socketService?.emit('seek', {
        'sessionId': _currentSessionId,
        'position_ms': positionMs,
      });
      return;
    }

    // Соло-режим
    try {
      if (_isWindows || _isWeb) {
        await _apiService?.seekToPosition(positionMs);
      } else {
        await SpotifySdk.seekTo(positionedMilliseconds: positionMs);
      }
    } catch (e) {
      print('[Solo Seek] Ошибка: $e');
    }
  }

  void stop() {
    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    if (_currentSessionId != null && _userId != null) {
      _socketService?.emit('leave_session', {'sessionId': _currentSessionId, 'userId': _userId});
    }
    // Не вызываем _socketService?.disconnect() — это общий singleton-сокет,
    // используемый остальным приложением (друзья, presence и т.д.), и его
    // нельзя рвать только потому что пользователь ушёл с экрана сессии.
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
    notifyListeners();
  }

  Future<void> setShuffle(bool enabled) async {
    print('[PlaybackProvider] setShuffle called, enabled=$enabled');
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
      print('[Spotify] setShuffle error: $e');
      // Всё равно обновляем локально, чтобы кнопка переключилась
      _shuffleActive = enabled;
      notifyListeners();
    }
  }

  Future<void> cycleRepeatMode() async {
    print('[PlaybackProvider] cycleRepeatMode called, current mode=$_repeatMode');
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
      print('[Spotify] cycleRepeatMode error: $e');
      _repeatMode = newMode;
      notifyListeners();
    }
  }

  void handleServerPrepare(dynamic data) async {
    if (data is! Map) return;

    final trackId = data['trackId'] as String?;
    if (trackId == null) return;

    print('[SyncPlay] Сервер скомандовал развернуть трек: $trackId');

    _preparedTrackId = trackId;
    _isReadySent = false;

    // Останавливаем поллинг-таймер СРАЗУ. Иначе он продолжает тикать со
    // старого playTrack() (Windows/Web) поверх уже сброшенных на новый трек
    // _positionMs/_durationMs, пока идёт хендшейк session_prepare→client_ready→
    // session_start — и может спровоцировать повторный/ложный вызов
    // _checkSessionTrackEnd ещё до реального старта нового трека.
    _pollingTimer?.cancel();
    _isPlaying = false;
    // Сбрасываем "последнюю активную" позицию/длительность (Android-детектор
    // конца трека) здесь же, а не только при получении isPaused=false от SDK —
    // если SDK не пришлёт промежуточное "playing"-событие между play() и
    // pause() ниже, детектор мог бы иначе сработать повторно по устаревшим
    // значениям ПРЕДЫДУЩЕГО трека.
    _lastActivePositionMs = 0;
    _lastActiveDurationMs = 0;
    notifyListeners();

    final spotifyUri = 'spotify:track:$trackId';
    final bool isMobile = !_isWindows && !_isWeb;

    if (isMobile) {
      // Мобильные: SDK играет трек, потом ставим на паузу.
      // _subscribeToPlayerState отловит момент, когда трек загружен и на паузе,
      // и сам отправит client_ready.
      try {
        await SpotifySdk.play(spotifyUri: spotifyUri);
        await SpotifySdk.pause();
      } catch (e) {
        print('[SyncM] Error preparing track via SDK: $e');
      }
    } else {
      // Windows/Web: REST API — загружаем трек, ставим на паузу, сигналим готовность.
      // Перед этим приглушаем звук: play() здесь запускает РЕАЛЬНОЕ
      // воспроизведение на устройстве (у Spotify Web API нет метода
      // "загрузить, но не играть"), и раньше это было слышно как лишний,
      // несинхронный "первый запуск" трека перед настоящим стартом через
      // session_start. Громкость возвращается назад в обработчике
      // session_start, ровно к моменту настоящего синхронного старта.
      try {
        if (_preMuteVolume == null) {
          final state = await _apiService?.getPlayerState();
          final vol = (state?['device']?['volume_percent'] as num?)?.toInt();
          _preMuteVolume = (vol != null && vol > 0) ? vol : 100;
        }
        await _apiService?.setVolume(0);
      } catch (e) {
        print('[SyncM] Volume mute error: $e');
      }

      try {
        await _apiService?.playTrack(spotifyUri);
        // Раньше здесь ждали 800мс "на всякий случай" перед паузой — это и
        // создавало заметный слышимый "дёрг" при подготовке каждого трека
        // (Spotify реально играет почти секунду, потом пауза, потом ещё раз
        // настоящий синхронный старт). К этому моменту play() уже гарантированно
        // доставлен и принят Spotify (мы дожидаемся ответа самого запроса
        // строкой выше), так что 800мс — избыточный запас. Сокращаем окно
        // до минимума, достаточного чтобы Spotify успел отреагировать на play
        // прежде чем мы пришлём pause следом.
        await Future.delayed(const Duration(milliseconds: 250));
        await _apiService?.pausePlayback();
        _isReadySent = true;
        _socketService?.emit('client_ready', {
          'sessionId': _currentSessionId,
          'trackId': trackId,
        });
      } catch (e) {
        print('[SyncM] Error preparing track via API: $e');
        // Всё равно шлём client_ready, чтобы сессия не зависла
        if (!_isReadySent) {
          _isReadySent = true;
          _socketService?.emit('client_ready', {
            'sessionId': _currentSessionId,
            'trackId': trackId,
          });
        }
      }
    }
  }

  // Устаревшие слушатели, оставлены неиспользуемыми: события 'toggle_play' и
  // 'seek_track' не отправляются текущим бэкендом (там используются
  // 'session_pause'/'session_resume'/'seek'), поэтому эта функция сейчас
  // нигде не вызывается. Сохранена как есть, со исправленным локальным багом,
  // на случай если протокол вернётся к этим событиям.
  void _setupSessionSocketListeners() {
    if (_socketService == null) return;

    _socketService!.on('toggle_play', (data) async {
      print('[Socket] Получена команда toggle_play от сервера: $data');
      final bool remoteIsPlaying = data['isPlaying'] as bool;

      _isPlaying = remoteIsPlaying;

      try {
        if (_isPlaying) {
          if (_isWindows || _isWeb) {
            await _apiService?.resumePlayback();
          } else {
            await SpotifySdk.resume();
          }
        } else {
          if (_isWindows || _isWeb) {
            await _apiService?.pausePlayback();
          } else {
            await SpotifySdk.pause();
          }
        }
      } catch (e) {
        print('Ошибка синхронизации плеера при toggle_play: $e');
      }
      notifyListeners();
    });

    _socketService!.on('seek_track', (data) async {
      print('[Socket] Получена команда seek_track от сервера: $data');
      final int remotePosition = data['positionMs'] as int;

      _positionMs = remotePosition;

      try {
        if (_isWindows || _isWeb) {
          await _apiService?.seekToPosition(remotePosition);
        } else {
          await SpotifySdk.seekTo(positionedMilliseconds: remotePosition);
        }
      } catch (e) {
        print('Ошибка синхронизации плеера при seek_track: $e');
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    // Аналогично stop() — не трогаем общий singleton-сокет здесь.
    super.dispose();
  }
}