import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:spotify_sdk/models/image_uri.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class PlaybackProvider extends ChangeNotifier {
  Map<String, dynamic>? _currentTrack;
  bool _isPlaying = false;
  bool _isConnected = false;
  int _durationMs = 0;
  int _positionMs = 0;
  Uint8List? _currentImageBytes;
  String? _lastImageUri;

  IO.Socket? _socket;
  String? _currentSessionId;
  String? _userId;

  Map<String, dynamic>? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isConnected => _isConnected;
  int get durationMs => _durationMs;
  int get positionMs => _positionMs;
  Uint8List? get currentImageBytes => _currentImageBytes;

  static const _clientId = '809ce8e069a64cb5970c20e356024786';
  static const _redirectUrl = 'syncm://callback';
  static const _serverUrl = 'http://YOUR_SERVER_IP:3000';

  void initSocket(String sessionId, String userId) {
    // Если уже подключены — не создаём новый сокет
    if (_socket != null && _socket!.connected && _currentSessionId == sessionId) {
      print('[Socket] Already connected to session $sessionId');
      return;
    }

    // Закрываем старый сокет если есть
    _socket?.disconnect();
    _socket?.dispose();

    _currentSessionId = sessionId;
    _userId = userId;

    _socket = IO.io(
        _serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableReconnection()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(2000)
            .build());

    _socket!.onConnect((_) {
      print('[Socket] Connected to WebSocket');
      _socket!.emit('authenticate', {'token': userId});
      _socket!.emit('join_session', {'sessionId': sessionId, 'userId': userId});
    });

    _socket!.onDisconnect((_) {
      print('[Socket] Disconnected');
    });

    _socket!.onConnectError((err) {
      print('[Socket] Connect error: $err');
    });

    _socket!.on('play', (data) {
      if (data['spotifyUri'] != _currentTrack?['uri']) {
        playTrack({'uri': data['spotifyUri']}, positionMs: data['position_ms']);
      }
    });

    _socket!.on('pause', (_) async {
      if (_isPlaying) {
        try {
          await SpotifySdk.pause();
        } catch (_) {}
        _isPlaying = false;
        notifyListeners();
      }
    });

    _socket!.on('next_track', (data) {
      playTrack({'uri': data['spotifyUri']});
    });

    _socket!.on('seek', (data) {
      seekTo(data['position_ms']);
    });
  }

  Future<bool> connect() async {
    try {
      print('[Spotify] Requesting access token...');
      await SpotifySdk.getAccessToken(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
        scope:
            'app-remote-control,user-modify-playback-state,user-read-playback-state,playlist-read-private,streaming',
      );

      print('[Spotify] Connecting to Spotify Remote...');
      _isConnected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
      );

      print('[Spotify] Connected: $_isConnected');

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

        if (trackChanged && _currentSessionId != null) {
          _socket?.emit('next_track', {
            'sessionId': _currentSessionId,
            'spotifyUri': trackUri,
          });
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
    }, onError: (err) {
      print('[Spotify] PlayerState stream error: $err');
    });
  }

  Future<void> playTrack(Map<String, dynamic> track,
      {String? playlistId, int? positionMs}) async {
    final uri = track['uri'] as String?;
    if (uri == null) {
      print('[Spotify] playTrack: uri is null');
      return;
    }

    // КРИТИЧНО: убеждаемся что подключены к SDK
    if (!_isConnected) {
      print('[Spotify] Not connected, trying to connect...');
      final connected = await connect();
      if (!connected) {
        print('[Spotify] Failed to connect, cannot play');
        return;
      }
    }

    try {
      print('[Spotify] Playing track: $uri');

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

      _currentTrack = track;
      _isPlaying = true;

      // Уведомляем других участников сессии
      if (_currentSessionId != null) {
        _socket?.emit('play', {
          'sessionId': _currentSessionId,
          'spotifyUri': uri,
          'position_ms': positionMs ?? 0
        });
      }

      notifyListeners();
    } catch (e) {
      print('[Spotify] Play error: $e');
      // Пробуем переподключиться и сыграть ещё раз
      try {
        print('[Spotify] Attempting reconnect...');
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
    if (!_isConnected) {
      await connect();
    }
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

  Future<void> skipNext() async {
    try {
      await SpotifySdk.skipNext();
    } catch (e) {
      print('[Spotify] Skip next error: $e');
    }
  }

  Future<void> skipPrevious() async {
    try {
      await SpotifySdk.skipPrevious();
    } catch (e) {
      print('[Spotify] Skip previous error: $e');
    }
  }

  Future<void> seekTo(int ms) async {
    try {
      await SpotifySdk.seekTo(positionedMilliseconds: ms);
      _positionMs = ms;
      _socket?.emit('seek', {
        'sessionId': _currentSessionId,
        'position_ms': ms
      });
      notifyListeners();
    } catch (e) {
      print('[Spotify] Seek error: $e');
    }
  }

  void stop() {
    if (_currentSessionId != null && _userId != null) {
      _socket?.emit('leave_session', {
        'sessionId': _currentSessionId,
        'userId': _userId
      });
    }
    _socket?.disconnect();
    _isPlaying = false;
    _currentTrack = null;
    _isConnected = false;
    _currentImageBytes = null;
    _lastImageUri = null;
    notifyListeners();
  }
}
