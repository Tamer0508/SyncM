import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late ApiService api;
  late List<String> calls;
  late List<Map<String, dynamic>> playBodies;
  late Map<String, dynamic>? playerState;

  List<Map<String, dynamic>> playlistOf(int count) => List.generate(
        count,
        (i) => {
          'uri': 'spotify:track:t$i',
          'index': i,
          'name': 'Track $i',
          'artist': 'Artist',
        },
      );

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('syncm_test').path,
    );
  });

  setUp(() async {
    HttpOverrides.global = null;
    calls = [];
    playBodies = [];
    playerState = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');

      if (request.uri.path == '/spotify/play') {
        final raw = await utf8.decoder.bind(request).join();
        if (raw.isNotEmpty) {
          playBodies.add(json.decode(raw) as Map<String, dynamic>);
        }
      }

      final body = request.uri.path == '/spotify/player'
          ? jsonEncode(playerState ?? {'is_playing': false})
          : jsonEncode({'success': true});

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(body);
      await request.response.close();
    });

    api = ApiService.instance(
      baseUrl: 'http://${server.address.address}:${server.port}',
      timeout: const Duration(seconds: 5),
    );
    api.setCookie('test-token');

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await server.close(force: true);
  });

  Future<PlaybackProvider> playingSpotifyPlaylist(
    List<Map<String, dynamic>> tracks,
    int index,
  ) async {
    final pb = PlaybackProvider();
    pb.setApiService(api);
    await pb.playTrack(
      Map<String, dynamic>.from(tracks[index]),
      playlistId: 'playlist1',
      knownPlaylistTracks: tracks,
    );
    calls.clear();
    playBodies.clear();
    return pb;
  }

  Future<PlaybackProvider> playingCustomPlaylist(
    List<Map<String, dynamic>> tracks,
    int index,
  ) async {
    final pb = PlaybackProvider();
    pb.setApiService(api);
    await pb.playTrack(
      Map<String, dynamic>.from(tracks[index]),
      playlistId: null,
      knownPlaylistTracks: tracks,
    );
    calls.clear();
    playBodies.clear();
    return pb;
  }

  Future<void> setRepeat(PlaybackProvider pb, String mode) async {
    while (pb.repeatMode != mode) {
      await pb.cycleRepeatMode();
    }
    calls.clear();
  }

  bool askedSpotifyForNextTrack() =>
      calls.contains('POST /spotify/next') ||
      calls.contains('POST /spotify/previous');

  String? uriOf(PlaybackProvider pb) => pb.currentTrack?['uri'] as String?;

  test('playlist_last_track_manual_skip_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingSpotifyPlaylist(tracks, 2);

    expect(pb.repeatMode, 'off');
    expect(pb.shuffleActive, isFalse);

    await pb.goToNext();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse,
        reason: 'следующий трек выбирает плейлист, а не Spotify: $calls');
    expect(pb.playlistEnded, isTrue, reason: 'плейлист должен завершиться');
    expect(calls, contains('PUT /spotify/pause'));

    expect(uriOf(pb), 'spotify:track:t2');
    expect(pb.currentPlaylistId, 'spotify:playlist:playlist1');
    expect(pb.currentQueueIndex, 2);
    expect(pb.repeatMode, 'off');

    pb.dispose();
  });

  test('playlist_last_track_completion_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingSpotifyPlaylist(tracks, 2);

    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(playBodies, isEmpty,
        reason: 'при выключенном repeat конец плейлиста ничего не запускает');
    expect(pb.playlistEnded, isTrue);
    expect(uriOf(pb), 'spotify:track:t2');
    expect(pb.currentPlaylistId, 'spotify:playlist:playlist1');

    pb.dispose();
  });

  test('playlist_repeat_wraparound_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingSpotifyPlaylist(tracks, 2);
    await setRepeat(pb, 'context');

    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(uriOf(pb), 'spotify:track:t0', reason: 'C -> A');
    expect(pb.currentQueueIndex, 0);
    expect(pb.currentPlaylistId, 'spotify:playlist:playlist1');
    expect(pb.repeatMode, 'context', reason: 'repeat не должен сбрасываться');
    expect(pb.playlistEnded, isFalse);

    calls.clear();
    final pb2 = await playingSpotifyPlaylist(tracks, 2);
    await setRepeat(pb2, 'context');
    await pb2.goToNext();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(uriOf(pb2), 'spotify:track:t0');
    expect(pb2.repeatMode, 'context');

    pb.dispose();
    pb2.dispose();
  });

  test('playlist_repeat_one_repeats_the_same_track_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingSpotifyPlaylist(tracks, 2);
    await setRepeat(pb, 'track');

    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(uriOf(pb), 'spotify:track:t2', reason: 'C -> C');
    expect(pb.repeatMode, 'track');

    await pb.goToNext();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(tracks.map((t) => t['uri']), contains(uriOf(pb)));

    pb.dispose();
  });

  test('spotify_playlist_last_track_test', () async {
    final tracks = playlistOf(4);

    for (final mode in ['off', 'context', 'track']) {
      final pb = await playingSpotifyPlaylist(tracks, 3);
      await setRepeat(pb, mode);
      playBodies.clear();

      await pb.handleTrackCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(askedSpotifyForNextTrack(), isFalse,
          reason: 'repeat=$mode ушёл к Spotify: $calls');
      final uri = uriOf(pb);
      expect(tracks.map((t) => t['uri']), contains(uri),
          reason: 'repeat=$mode вывел из плейлиста: $uri');
      expect(pb.repeatMode, mode, reason: 'repeat=$mode сбросился');

      pb.dispose();
    }
  });

  test('custom_playlist_last_track_test', () async {
    final tracks = playlistOf(4);

    for (final mode in ['off', 'context', 'track']) {
      final pb = await playingCustomPlaylist(tracks, 3);
      await setRepeat(pb, mode);
      playBodies.clear();

      await pb.handleTrackCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(askedSpotifyForNextTrack(), isFalse,
          reason: 'repeat=$mode ушёл к Spotify: $calls');
      final uri = uriOf(pb);
      expect(tracks.map((t) => t['uri']), contains(uri),
          reason: 'repeat=$mode вывел из плейлиста: $uri');
      expect(pb.repeatMode, mode, reason: 'repeat=$mode сбросился');
      expect(pb.currentPlaylistId, isNull,
          reason: 'у плейлиста SyncM контекста Spotify нет и быть не должно');

      pb.dispose();
    }

    final pb = await playingCustomPlaylist(tracks, 3);
    await setRepeat(pb, 'context');
    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(uriOf(pb), 'spotify:track:t0');
    pb.dispose();
  });

  test('custom_playlist_manual_skip_stays_inside_playlist_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingCustomPlaylist(tracks, 2);

    await pb.goToNext();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(pb.playlistEnded, isTrue);
    expect(uriOf(pb), 'spotify:track:t2');

    pb.dispose();
  });

  test('single_track_playlist_repeat_test', () async {
    final tracks = playlistOf(1);

    final off = await playingCustomPlaylist(tracks, 0);
    await off.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(off.playlistEnded, isTrue, reason: 'A -> END');
    off.dispose();

    for (final mode in ['context', 'track']) {
      calls.clear();
      final pb = await playingCustomPlaylist(tracks, 0);
      await setRepeat(pb, mode);
      playBodies.clear();

      await pb.handleTrackCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
      expect(uriOf(pb), 'spotify:track:t0', reason: 'repeat=$mode: A -> A');
      expect(pb.playlistEnded, isFalse);
      pb.dispose();
    }
  });

  test('two_track_playlist_all_repeat_modes_test', () async {
    final tracks = playlistOf(2);

    final expected = {
      'off': null,
      'context': 'spotify:track:t0',
      'track': 'spotify:track:t1',
    };

    for (final entry in expected.entries) {
      calls.clear();
      final pb = await playingCustomPlaylist(tracks, 1);
      await setRepeat(pb, entry.key);

      await pb.handleTrackCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
      if (entry.value == null) {
        expect(pb.playlistEnded, isTrue, reason: 'repeat=${entry.key}');
      } else {
        expect(uriOf(pb), entry.value, reason: 'repeat=${entry.key}');
      }
      pb.dispose();
    }
  });

  test('empty_playlist_does_not_start_a_random_track_test', () async {
    final pb = PlaybackProvider();
    pb.setApiService(api);
    await pb.playTrack(
      {'uri': 'spotify:track:t0', 'index': 0, 'name': 'Track 0'},
      playlistId: 'playlist1',
      knownPlaylistTracks: const <Map<String, dynamic>>[],
    );
    calls.clear();
    playBodies.clear();

    await pb.goToNext();
    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(askedSpotifyForNextTrack(), isFalse,
        reason: 'пустой плейлист — не повод включать чужой трек: $calls');
    expect(playBodies, isEmpty);

    pb.dispose();
  });

  test('repeat_mode_persistence_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingSpotifyPlaylist(tracks, 0);
    await setRepeat(pb, 'context');

    final seen = <String?>[uriOf(pb)];
    for (var i = 0; i < 5; i++) {
      await pb.handleTrackCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      seen.add(uriOf(pb));
      expect(pb.repeatMode, 'context',
          reason: 'repeat сбросился на шаге $i: $seen');
      expect(pb.currentPlaylistId, 'spotify:playlist:playlist1',
          reason: 'playlistId потерялся на шаге $i');
    }

    expect(seen, [
      'spotify:track:t0',
      'spotify:track:t1',
      'spotify:track:t2',
      'spotify:track:t0',
      'spotify:track:t1',
      'spotify:track:t2',
    ]);
    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');

    pb.dispose();
  });

  test('shuffle_off_does_not_escape_playlist_test', () async {
    final tracks = playlistOf(5);

    for (final pb in [
      await playingSpotifyPlaylist(tracks, 4),
      await playingCustomPlaylist(tracks, 4),
    ]) {
      expect(pb.shuffleActive, isFalse);
      calls.clear();

      for (var i = 0; i < 3; i++) {
        await pb.goToNext();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(askedSpotifyForNextTrack(), isFalse,
            reason: 'шаг $i ушёл к Spotify: $calls');
        final uri = uriOf(pb);
        expect(tracks.map((t) => t['uri']), contains(uri),
            reason: 'шаг $i вывел из плейлиста: $uri');
      }

      await pb.goToPrevious();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
      expect(pb.currentQueueIndex, 3);

      pb.dispose();
    }
  });

  test('shuffle_on_stays_inside_playlist_test', () async {
    final tracks = playlistOf(6);

    for (final pb in [
      await playingSpotifyPlaylist(tracks, 5),
      await playingCustomPlaylist(tracks, 5),
    ]) {
      await pb.setShuffle(true);
      calls.clear();

      for (var i = 0; i < 4; i++) {
        await pb.handleTrackCompleted();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
        expect(tracks.map((t) => t['uri']), contains(uriOf(pb)),
            reason: 'shuffle вывел из плейлиста на шаге $i');
        expect(pb.shuffleActive, isTrue);
      }

      pb.dispose();
    }
  });

  test('switching_playlists_does_not_mix_queues_test', () async {
    final first = playlistOf(2);
    final second = List.generate(
      2,
      (i) => {
        'uri': 'spotify:track:s$i',
        'index': i,
        'name': 'Second $i',
        'artist': 'Artist',
      },
    );

    final pb = await playingCustomPlaylist(first, 1);
    await setRepeat(pb, 'context');

    await pb.playTrack(
      Map<String, dynamic>.from(second.first),
      playlistId: null,
      knownPlaylistTracks: second,
    );
    calls.clear();

    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(uriOf(pb), 'spotify:track:s1',
        reason: 'очередь второго плейлиста не должна смешиваться с первой');

    await pb.handleTrackCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(uriOf(pb), 'spotify:track:s0', reason: 'закольцовка внутри второго');
    expect(first.map((t) => t['uri']), isNot(contains(uriOf(pb))));

    pb.dispose();
  });

  test('next_track_preview_follows_repeat_mode_test', () async {
    final tracks = playlistOf(3);
    final pb = await playingSpotifyPlaylist(tracks, 2);

    expect(pb.nextQueueTrack, isNull,
        reason: 'при выключенном repeat за последним треком ничего нет');

    await setRepeat(pb, 'context');
    expect(pb.nextQueueTrack?['uri'], 'spotify:track:t0',
        reason: 'закольцованный плейлист показывает первый трек следующим');

    pb.dispose();
  });

  test('position_watcher_triggers_playlist_end_test', () async {
    final tracks = playlistOf(3);
    playerState = {
      'is_playing': true,
      'progress_ms': 2000,
      'item': {
        'uri': 'spotify:track:t2',
        'name': 'Track 2',
        'artists': [
          {'name': 'Artist'}
        ],
        'duration_ms': 3000,
      },
    };

    final pb = await playingCustomPlaylist(tracks, 2);
    await setRepeat(pb, 'context');

    await Future<void>.delayed(const Duration(milliseconds: 4500));

    expect(askedSpotifyForNextTrack(), isFalse, reason: '$calls');
    expect(uriOf(pb), 'spotify:track:t0',
        reason: 'естественное окончание должно закольцевать плейлист: $calls');

    pb.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('spotify_autoplay_is_pulled_back_into_playlist_test', () async {
    final tracks = playlistOf(3);

    playerState = {
      'is_playing': true,
      'progress_ms': 2900,
      'item': {
        'uri': 'spotify:track:t2',
        'name': 'Track 2',
        'artists': [
          {'name': 'Artist'}
        ],
        'duration_ms': 3000,
      },
    };

    final pb = await playingSpotifyPlaylist(tracks, 2);
    await setRepeat(pb, 'track');

    await Future<void>.delayed(const Duration(milliseconds: 3600));

    playerState = {
      'is_playing': true,
      'progress_ms': 500,
      'item': {
        'uri': 'spotify:track:outsider',
        'name': 'Outsider',
        'artists': [
          {'name': 'Someone Else'}
        ],
        'duration_ms': 200000,
      },
    };

    await Future<void>.delayed(const Duration(milliseconds: 3600));

    expect(uriOf(pb), isNot('spotify:track:outsider'),
        reason: 'чужой трек должен быть заменён треком плейлиста: $calls');
    expect(tracks.map((t) => t['uri']), contains(uriOf(pb)));
    expect(pb.repeatMode, 'track', reason: 'repeat не должен сбрасываться');

    pb.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
