import 'package:flutter/foundation.dart'
    show TargetPlatform, Uint8List, defaultTargetPlatform, kIsWeb, debugPrint;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, MissingPluginException;

class MediaSessionCommand {
  const MediaSessionCommand(this.action, this.value);

  final String action;

  final int? value;
}

class MediaSessionService {
  const MediaSessionService._();

  static const MethodChannel _channel = MethodChannel('syncm/media_session');

  static final bool isSupported =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void Function(MediaSessionCommand command)? onCommand;
  static void Function()? onOpenNowPlaying;

  static bool _handlerInstalled = false;

  static Future<void> ready({
    required String channelName,
    required String channelDescription,
  }) async {
    if (!isSupported) return;
    if (!_handlerInstalled) {
      _channel.setMethodCallHandler(_handle);
      _handlerInstalled = true;
    }
    await _invoke('ready', {
      'channelName': channelName,
      'channelDescription': channelDescription,
    });
  }

  static Future<void> setTrack({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required int durationMs,
  }) =>
      _invoke('setTrack', {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
      });

  static Future<void> setArtwork(String trackId, Uint8List? bytes) =>
      _invoke('setArtwork', {'trackId': trackId, 'bytes': bytes});

  static Future<void> setPlaybackState({
    required bool isPlaying,
    required bool buffering,
    required int positionMs,
    required int durationMs,
    required bool shuffle,
    required String repeat,
  }) =>
      _invoke('setPlaybackState', {
        'isPlaying': isPlaying,
        'buffering': buffering,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'shuffle': shuffle,
        'repeat': repeat,
      });

  static Future<void> release() => _invoke('release', null);

  static Future<void> _invoke(String method, Map<String, dynamic>? args) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // Нативной стороны нет: тесты, headless-режим или уже уничтоженный
      // движок. Карточки там всё равно не бывает — молчим.
    } catch (e) {
      debugPrint('[MediaSession] $method не выполнен: $e');
    }
  }

  static Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'command':
        final args = call.arguments;
        if (args is! Map) return;
        final action = args['action'];
        if (action is! String) return;
        final raw = args['value'];
        onCommand?.call(
          MediaSessionCommand(action, raw is num ? raw.toInt() : null),
        );
        break;
      case 'openNowPlaying':
        onOpenNowPlaying?.call();
        break;
    }
  }
}
