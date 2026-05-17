import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:spotify_sdk/models/image_uri.dart';

class PlaybackProvider extends ChangeNotifier {
  Map<String, dynamic>? _currentTrack;
  bool _isPlaying = false;
  bool _isConnected = false;
  int _durationMs = 0;
  int _positionMs = 0;
  Uint8List? _currentImageBytes;
  String? _lastImageUri; // отслеживаем URI обложки чтобы не мигать

  Map<String, dynamic>? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isConnected => _isConnected;
  int get durationMs => _durationMs;
  int get positionMs => _positionMs;
  Uint8List? get currentImageBytes => _currentImageBytes;

  static const _clientId = '809ce8e069a64cb5970c20e356024786';
  static const _redirectUrl = 'syncm://callback';

  Future<bool> connect() async {
    try {
      await SpotifySdk.getAccessToken(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
        scope: 'app-remote-control,user-modify-playback-state,user-read-playback-state,playlist-read-private',
      );

      _isConnected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
      );

      if (_isConnected) _subscribeToPlayerState();
      notifyListeners();
      return _isConnected;
    } catch (e) {
      print('Spotify connect error: $e');
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

        // Обновляем метаданные трека
        _currentTrack = {
          ..._currentTrack ?? {},
          'title': state.track!.name,
          'artist': state.track!.artist.name,
          'uri': trackUri,
        };

        // Загружаем обложку только если imageUri изменился
        if (trackChanged && imageUriId != _lastImageUri) {
          _lastImageUri = imageUriId;
          // НЕ сбрасываем _currentImageBytes сразу — держим старую до загрузки новой
          notifyListeners();

          try {
            final imageBytes = await SpotifySdk.getImage(
              imageUri: state.track!.imageUri,
              dimension: ImageDimension.large,
            );
            // Обновляем только если URI не изменился пока грузили
            if (_lastImageUri == imageUriId) {
              _currentImageBytes = imageBytes;
              notifyListeners();
            }
          } catch (e) {
            print('Image fetch error: $e');
          }
        } else {
          notifyListeners();
        }
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> playTrack(Map<String, dynamic> track, {String? playlistId}) async {
    final uri = track['uri'] as String?;
    if (uri == null) return;

    if (!_isConnected) {
      final connected = await connect();
      if (!connected) return;
    }

    try {
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

      _currentTrack = track;
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      print('Play error: $e');
      try {
        await SpotifySdk.play(spotifyUri: uri);
        _currentTrack = track;
        _isPlaying = true;
        notifyListeners();
      } catch (e2) {
        print('Fallback play error: $e2');
      }
    }
  }

  Future<void> togglePlay() async {
    try {
      if (_isPlaying) {
        await SpotifySdk.pause();
        _isPlaying = false;
      } else {
        await SpotifySdk.resume();
        _isPlaying = true;
      }
      notifyListeners();
    } catch (e) {
      _isPlaying = !_isPlaying;
      notifyListeners();
    }
  }

  Future<void> skipNext() async {
    try {
      await SpotifySdk.skipNext();
    } catch (e) {
      print('Skip next error: $e');
    }
  }

  Future<void> skipPrevious() async {
    try {
      await SpotifySdk.skipPrevious();
    } catch (e) {
      print('Skip previous error: $e');
    }
  }

  Future<void> seekTo(int ms) async {
    try {
      await SpotifySdk.seekTo(positionedMilliseconds: ms);
      _positionMs = ms;
      notifyListeners();
    } catch (e) {
      print('Seek error: $e');
    }
  }

  void stop() {
    _isPlaying = false;
    _currentTrack = null;
    _isConnected = false;
    _currentImageBytes = null;
    _lastImageUri = null;
    notifyListeners();
  }
}