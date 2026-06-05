import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:palette_generator/palette_generator.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:spotify_sdk/models/image_uri.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import '../services/api_service.dart';
import '../config.dart';

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

  IO.Socket? _socket;
  String? _currentSessionId;
  String? _userId;

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
  bool _isRemoteSync = false;
  bool _queueEnded = false;
  bool _isAdvancingQueue = false;
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

    if (syncToSession && !_isRemoteSync && _currentSessionId != null) {
      _socket?.emit('session_play', {
        'sessionId': _currentSessionId,
        'spotifyUri': track['uri'],
        'trackIndex': index,
        'tracks': _sessionQueue,
        'addedById': _userId,
      });
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
      final index = data['trackIndex'] as int? ?? 0;
      await playSessionTrack(index, syncToSession: false);
      onSessionPlaybackStarted?.call(_sessionQueue[index]);
    } finally {
      _isRemoteSync = false;
    }
  }

  Future<void> _advanceSessionQueue() async {
    if (!_sessionMode || _sessionQueue.isEmpty || _isAdvancingQueue) return;
    _isAdvancingQueue = true;
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
    if (_isWindows || _isWeb) {
      try {
        await _apiService?.pausePlayback();
      } catch (_) {}
    } else {
      try {
        await SpotifySdk.pause();
      } catch (_) {}
    }
    notifyListeners();
  }

  void _checkSessionTrackEnd() {
    if (!_sessionMode || _queueEnded || !_isPlaying || _isAdvancingQueue) return;
    if (_durationMs > 0 && _positionMs >= _durationMs - 900) {
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
      if (tickCount % 6 == 0) {
        try {
          final state = await _apiService?.getPlayerState();
          if (state == null) return;
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

  void initSocket(String sessionId, String userId) {
    if (_socket != null && _socket!.connected && _currentSessionId == sessionId) {
      return;
    }

    _socket?.disconnect();
    _socket?.dispose();

    _currentSessionId = sessionId;
    _userId = userId;

    _socket = IO.io(
        _socketUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableReconnection()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(2000)
            .build());

    _socket!.onConnect((_) {
      _socket!.emit('authenticate', {'token': userId});
      _socket!.emit('join_session', {'sessionId': sessionId});
    });

    _socket!.onDisconnect((_) => print('[Socket] Disconnected'));
    _socket!.onConnectError((err) => print('[Socket] Connect error: $err'));

    _socket!.on('play', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (map['spotifyUri'] != _currentTrack?['uri']) {
        playTrack({'uri': map['spotifyUri']}, positionMs: map['position_ms'] as int?);
      }
    });

    _socket!.on('pause', (_) async {
      if (_isPlaying) {
        if (_isWindows || _isWeb) {
          try { await _apiService?.pausePlayback(); } catch (_) {}
        } else {
          try { await SpotifySdk.pause(); } catch (_) {}
        }
        _isPlaying = false;
        notifyListeners();
      }
    });

    _socket!.on('next_track', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (_sessionMode) {
        _advanceSessionQueue();
      } else {
        playTrack({'uri': map['spotifyUri']});
      }
    });

    _socket!.on('seek', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      seekTo(map['position_ms'] as int? ?? 0);
    });

    _socket!.on('session_play', (data) {
      if (data is Map) handleSessionPlayEvent(Map<String, dynamic>.from(data));
    });

    _socket!.on('tracks-added', (data) {
      if (data is Map) onTracksAdded?.call(Map<String, dynamic>.from(data));
    });
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

      if (state.track != null) {
        final trackUri = state.track!.uri;
        final imageUriId = state.track!.imageUri.raw;
        final trackChanged = trackUri != _currentTrack?['uri'];

        _currentTrack = {
          ..._currentTrack ?? {},
          'title': state.track!.name,
          'artist': state.track!.artist.name,
          'uri': trackUri,
        };

        if (trackChanged && _currentSessionId != null && !_sessionMode) {
          _socket?.emit('next_track', {'sessionId': _currentSessionId, 'spotifyUri': trackUri});
        }

        if (_sessionMode && state.isPaused && state.track != null) {
          final dur = state.track!.duration;
          if (dur > 0 && state.playbackPosition >= dur - 1200) {
            _advanceSessionQueue();
          }
        }

        // If shuffle is enabled and we are inside a playlist, make sure the
        // new track belongs to that playlist; if not, correct it.
        if (trackChanged && _shuffleActive && _currentPlaylistId != null && !_suppressAutoCorrection) {
          try {
            await _ensurePlaylistTracksLoaded();
            final found = _currentPlaylistTracks?.any((t) => (t['uri'] as String?) == trackUri) ?? false;
            if (!found) {
              // Fire-and-forget correction
              _playRandomFromCurrentPlaylist();
            }
          } catch (e) {
            print('[PlaybackProvider] Error validating track against playlist: $e');
          }
        }

        if (trackChanged && imageUriId != _lastImageUri) {
          _lastImageUri = imageUriId;
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
            print('[Spotify] Image fetch error: $e');
          }
        } else {
          notifyListeners();
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

          // remember current playlist context and prefetch tracks for shuffle logic
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
        final contextUri = playlistId.startsWith('spotify:')
            ? playlistId
            : 'spotify:playlist:$playlistId';
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

      // remember current playlist context and prefetch tracks for shuffle logic
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
        _socket?.emit('play', {
          'sessionId': _currentSessionId,
          'spotifyUri': uri,
          'position_ms': positionMs ?? 0
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
    if (_isWindows || _isWeb) {
      try {
        if (_isPlaying) {
          await _apiService?.pausePlayback();
          _isPlaying = false;
        } else {
          await _apiService?.resumePlayback();
          _isPlaying = true;
        }
        notifyListeners();
      } catch (e) {
        print('[Web/Windows] Toggle error: $e');
      }
      return;
    }

    if (!_isConnected) await connect();
    try {
      if (_isPlaying) {
        await SpotifySdk.pause();
        _isPlaying = false;
        _socket?.emit('pause', {'sessionId': _currentSessionId});
      } else {
        await SpotifySdk.resume();
        _isPlaying = true;
        _socket?.emit('play', {
          'sessionId': _currentSessionId,
          'spotifyUri': _currentTrack?['uri'],
          'position_ms': _positionMs
        });
      }
      notifyListeners();
    } catch (e) {
      print('[Spotify] Toggle error: $e');
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
        'artist':
            (track['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '',
        'imageUrl': newImageUrl,
        'uri': track['uri'],
      };
      _currentImageBytes = null;

      if (newImageUrl != null && !_paletteCache.containsKey(newImageUrl)) {
        _preloadPalette(newImageUrl);
      }

      // If shuffle is active and we have a playlist context, ensure the new
      // track belongs to that playlist; otherwise pick a random one from it.
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
    if (_sessionMode) {
      await _advanceSessionQueue();
      return;
    }

    _positionMs = 0;
    notifyListeners();

    if (_isWindows || _isWeb) {
      try {
        // If shuffle is active and we have a playlist context, pick a random
        // track from the playlist to ensure we stay inside the playlist.
        if (_shuffleActive && _currentPlaylistId != null) {
          await _playRandomFromCurrentPlaylist();
        } else {
          await _apiService?.skipToNext();
          _pollForTrackChange();
        }
      } catch (e) {
        print('[Web/Windows] Skip next error: $e');
      }
      return;
    }

    try {
      if (_shuffleActive && _currentPlaylistId != null) {
        await _playRandomFromCurrentPlaylist();
      } else {
        await SpotifySdk.skipNext();
      }
    } catch (e) {
      print('[Spotify] Skip next error: $e');
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
        // For previous, if shuffle is active we also pick a random track
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
        // Ensure index exists for each track
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

    // Construct a minimal track map for UI
    final sel = tracks[index];
    final selectedUri = uris[index];
    final trackMap = {
      'uri': selectedUri,
      'index': sel['index'] ?? index,
      'title': sel['name'] ?? sel['title'] ?? '',
      'artist': sel['artist'] ?? '',
      'imageUrl': sel['imageUrl'] ?? sel['album']?['images']?[0]?['url'] ?? null,
    };

    // Prevent recursive corrections for a short time
    _suppressAutoCorrection = true;
    Future.delayed(const Duration(seconds: 2), () {
      _suppressAutoCorrection = false;
    });

    try {
      final contextUri = _currentPlaylistId!.startsWith('spotify:')
          ? _currentPlaylistId!
          : 'spotify:playlist:${_currentPlaylistId!}';
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

  Future<void> seekTo(int ms) async {
    if (_isWindows || _isWeb) {
      try {
        await _apiService?.seekToPosition(ms);
        _positionMs = ms;
        notifyListeners();
      } catch (e) {
        print('[Web/Windows] Seek error: $e');
      }
      return;
    }
    try {
      await SpotifySdk.seekTo(positionedMilliseconds: ms);
      _positionMs = ms;
      _socket?.emit('seek', {'sessionId': _currentSessionId, 'position_ms': ms});
      notifyListeners();
    } catch (e) {
      print('[Spotify] Seek error: $e');
    }
  }

  void stop() {
    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    if (_currentSessionId != null && _userId != null) {
      _socket?.emit('leave_session', {'sessionId': _currentSessionId, 'userId': _userId});
    }
    _socket?.disconnect();
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
      // всё равно обновляем локально, чтобы кнопка переключилась
      _shuffleActive = enabled;
      notifyListeners();
    }
  }

  Future<void> cycleRepeatMode() async {
    print(
        '[PlaybackProvider] cycleRepeatMode called, current mode=$_repeatMode');
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

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _trackChangeTimer?.cancel();
    _socket?.disconnect();
    super.dispose();
  }
}