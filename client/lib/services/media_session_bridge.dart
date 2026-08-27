import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../providers/playback_provider.dart';
import '../screens/player/now_playing.dart';
import '../theme.dart';
import '../utils/app_globals.dart';
import '../utils/image_cache.dart';
import 'media_session_service.dart';

class MediaSessionBridge {
  MediaSessionBridge._();

  static final MediaSessionBridge instance = MediaSessionBridge._();

  PlaybackProvider? _provider;
  bool _wired = false;

  // Снимок того, что уже уехало в MediaSession.
  bool _sessionActive = false;
  String _uri = '';
  String _title = '';
  String _artist = '';
  String _album = '';
  int _duration = 0;
  bool _isPlaying = false;
  bool _buffering = false;
  bool _shuffle = false;
  String _repeat = 'off';
  int _pushedDuration = 0;
  int _pushedPosition = 0;
  DateTime? _pushedAt;
  String? _artworkUri;

  String? _artworkLoadingUri;

  bool _permissionAsked = false;

  static const int _positionToleranceMs = 800;

  void attach(PlaybackProvider provider) {
    if (!MediaSessionService.isSupported) return;
    if (identical(_provider, provider)) return;

    _detachListeners(_provider);
    _provider = provider;
    provider.addListener(_onPlaybackChanged);
    provider.positionNotifier.addListener(_onPositionTick);

    if (!_wired) {
      _wired = true;
      MediaSessionService.onCommand = _handleCommand;
      MediaSessionService.onOpenNowPlaying = _openNowPlaying;
    }

    unawaited(_announceReady());
    _onPlaybackChanged();
  }

  void detach(PlaybackProvider provider) {
    if (!identical(_provider, provider)) return;
    _detachListeners(provider);
    _provider = null;
    _resetSnapshot();
    unawaited(MediaSessionService.release());
  }

  void _detachListeners(PlaybackProvider? provider) {
    if (provider == null) return;
    provider.removeListener(_onPlaybackChanged);
    provider.positionNotifier.removeListener(_onPositionTick);
  }

  Future<void> _announceReady() async {
    final l = appL10n;
    await MediaSessionService.ready(
      channelName: l?.mediaChannelName ?? 'Playback',
      channelDescription: l?.mediaChannelDescription ?? '',
    );
  }


  void _onPlaybackChanged() {
    final provider = _provider;
    if (provider == null) return;

    final track = provider.currentTrack;
    if (track == null) {
      if (_sessionActive) {
        _resetSnapshot();
        unawaited(MediaSessionService.release());
      }
      return;
    }

    final uri = (track['uri'] as String?) ?? '';
    if (uri.isEmpty) return;

    final title = (track['title'] as String?) ?? '';
    final artist = (track['artist'] as String?) ?? '';
    final album = (track['album'] as String?) ?? '';
    final duration = provider.durationMs;

    final trackChanged = !_sessionActive ||
        uri != _uri ||
        title != _title ||
        artist != _artist ||
        album != _album ||
        duration != _duration;

    if (trackChanged) {
      final firstTrack = !_sessionActive;
      _sessionActive = true;
      _uri = uri;
      _title = title;
      _artist = artist;
      _album = album;
      _duration = duration;
      _artworkUri = null;
      _artworkLoadingUri = null;

      unawaited(MediaSessionService.setTrack(
        trackId: uri,
        title: title,
        artist: artist,
        album: album,
        durationMs: duration,
      ));

      if (firstTrack) unawaited(_ensureNotificationPermission());
    }

    _pushArtworkIfNeeded(provider, uri, track);
    _pushPlaybackIfNeeded(provider, force: trackChanged);
  }

  void _onPositionTick() {
    final provider = _provider;
    if (provider == null || !_sessionActive) return;
    if (provider.currentTrack?['uri'] != _uri) return;
    _pushPlaybackIfNeeded(provider);
  }

  void _pushArtworkIfNeeded(
    PlaybackProvider provider,
    String uri,
    Map<String, dynamic> track,
  ) {
    // Одна обложка на трек: первый добравшийся источник и выигрывает.
    if (_artworkUri == uri) return;

    final bytes = provider.currentImageBytes;
    if (bytes != null) {
      _artworkUri = uri;
      _artworkLoadingUri = null;
      unawaited(MediaSessionService.setArtwork(uri, bytes));
      return;
    }

    if (_artworkLoadingUri == uri) return;
    final url = track['imageUrl'] as String?;
    if (url == null || url.isEmpty || url.startsWith('data:')) return;

    _artworkLoadingUri = uri;
    unawaited(_loadArtworkFromCache(uri, url));
  }

  Future<void> _loadArtworkFromCache(String uri, String url) async {
    try {
      final file = await AppImageCache.manager.getSingleFile(url);
      final bytes = await file.readAsBytes();

      // Пока файл читался, трек мог смениться или SDK мог отдать свои байты.
      if (_uri != uri || _artworkUri == uri || !_sessionActive) return;

      _artworkUri = uri;
      await MediaSessionService.setArtwork(uri, bytes);
    } catch (e) {
      debugPrint('[MediaSession] Обложку из кэша получить не удалось: $e');
    } finally {
      if (_artworkLoadingUri == uri) _artworkLoadingUri = null;
    }
  }

  void _pushPlaybackIfNeeded(PlaybackProvider provider, {bool force = false}) {
    final isPlaying = provider.isPlaying;
    final buffering = provider.isSwitchingTrack;
    final shuffle = provider.shuffleActive;
    final repeat = provider.repeatMode;
    final duration = provider.durationMs;
    final position = provider.positionMs;

    final drifted =
        (position - _extrapolatedPosition()).abs() > _positionToleranceMs;

    if (!force &&
        isPlaying == _isPlaying &&
        buffering == _buffering &&
        shuffle == _shuffle &&
        repeat == _repeat &&
        duration == _pushedDuration &&
        !drifted) {
      return;
    }

    _isPlaying = isPlaying;
    _buffering = buffering;
    _shuffle = shuffle;
    _repeat = repeat;
    _pushedDuration = duration;
    _pushedPosition = position;
    _pushedAt = DateTime.now();

    unawaited(MediaSessionService.setPlaybackState(
      isPlaying: isPlaying,
      buffering: buffering,
      positionMs: position,
      durationMs: duration,
      shuffle: shuffle,
      repeat: repeat,
    ));
  }

  int _extrapolatedPosition() {
    final pushedAt = _pushedAt;
    if (pushedAt == null) return -1 << 20;
    if (!_isPlaying || _buffering) return _pushedPosition;
    return _pushedPosition + DateTime.now().difference(pushedAt).inMilliseconds;
  }

  void _resetSnapshot() {
    _sessionActive = false;
    _uri = '';
    _title = '';
    _artist = '';
    _album = '';
    _duration = 0;
    _isPlaying = false;
    _shuffle = false;
    _repeat = 'off';
    _buffering = false;
    _pushedDuration = 0;
    _pushedPosition = 0;
    _pushedAt = null;
    _artworkUri = null;
    _artworkLoadingUri = null;
  }


  void _handleCommand(MediaSessionCommand command) {
    final provider = _provider;
    if (provider == null) return;

    switch (command.action) {
      case 'play':
        // togglePlay() переключает, а система просит конкретное состояние:
        // если Spotify уже играет, повторный PLAY не должен его остановить.
        if (!provider.isPlaying) unawaited(provider.togglePlay());
        break;
      case 'pause':
        if (provider.isPlaying) unawaited(provider.togglePlay());
        break;
      case 'next':
        // Защита от гонки при частых нажатиях уже внутри _skip().
        unawaited(provider.skipNext());
        break;
      case 'previous':
        unawaited(provider.skipPrevious());
        break;
      case 'seek':
        final position = command.value;
        if (position != null) unawaited(provider.seekTo(position));
        break;
      case 'shuffle':
        unawaited(provider.setShuffle(command.value == 1));
        break;
      case 'repeat':
        unawaited(_applyRepeat(provider, command.value));
        break;
      case 'stop':
        if (provider.isPlaying) unawaited(provider.togglePlay());
        _resetSnapshot();
        unawaited(MediaSessionService.release());
        break;
    }
  }

  /// У провайдера есть только циклический переключатель режима повтора —
  /// заводить ради карточки второй сеттер незачем, достаточно докрутить цикл.
  Future<void> _applyRepeat(PlaybackProvider provider, int? mode) async {
    // PlaybackStateCompat: 0 — NONE, 1 — ONE, 2 — ALL, 3 — GROUP.
    final target = switch (mode) {
      1 => 'track',
      2 || 3 => 'context',
      _ => 'off',
    };
    for (var i = 0; i < 3 && provider.repeatMode != target; i++) {
      await provider.cycleRepeatMode();
    }
  }

  /// Тап по карточке открывает Now Playing существующим механизмом SyncM.
  void _openNowPlaying() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final view = View.maybeOf(context);
    if (view != null) {
      final width = view.physicalSize.width / view.devicePixelRatio;
      if (AppLayout.of(width).showNowPlayingPanel) return;
    }

    final track = _provider?.currentTrack;
    unawaited(NowPlayingScreen.open(
      context,
      title: track?['title'] as String?,
      artist: track?['artist'] as String?,
      artworkUrl: track?['imageUrl'] as String?,
    ));
  }

  Future<void> _ensureNotificationPermission() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e) {
      debugPrint('[MediaSession] Разрешение на уведомления не получено: $e');
    }
  }
}
