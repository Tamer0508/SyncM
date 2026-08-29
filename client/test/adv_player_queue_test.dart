import 'dart:async';
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

  late Map<String, dynamic> playerState;

  final tracks = List.generate(
    6,
    (i) => {
      'uri': 'spotify:track:t$i',
      'index': i,
      'name': 'Track $i',
      'artist': 'Artist',
      'durationMs': 200000,
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
    playerState = {
      'is_playing': true,
      'progress_ms': 1000,
      'item': {
        'uri': 'spotify:track:t0',
        'name': 'Track 0',
        'artists': [
          {'name': 'Artist'}
        ],
        'duration_ms': 200000,
      },
    };

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');
      if (request.uri.path == '/spotify/play') {
        final raw = await utf8.decodeStream(request);
        try {
          playBodies.add(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          playBodies.add(<String, dynamic>{});
        }
      }

      final body = request.uri.path == '/spotify/player'
          ? jsonEncode(playerState)
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

  List<String> playedUris() =>
      playBodies.map((b) => '${b['uri'] ?? b['spotifyUri'] ?? ''}').toList();

  Future<PlaybackProvider> playingCustomPlaylist({int startIndex = 0}) async {
    final pb = PlaybackProvider();
    pb.setApiService(api);
    await pb.playTrack(
      Map<String, dynamic>.from(tracks[startIndex]),
      knownPlaylistTracks: tracks,
    );
    calls.clear();
    playBodies.clear();
    return pb;
  }

  group('позиция при смене трека', () {
    test('P-001: playTrack не сбрасывает позицию и длительность прошлого трека',
        () async {
      final pb = PlaybackProvider();
      pb.setApiService(api);

      await pb.playTrack(
        Map<String, dynamic>.from(tracks[0]),
        knownPlaylistTracks: tracks,
      );

      unawaited(pb.seekTo(195000));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await pb.playTrack(
        Map<String, dynamic>.from(tracks[3]),
        knownPlaylistTracks: tracks,
      );

      expect(
        pb.positionMs,
        lessThan(2000),
        reason: 'новый трек начинается с нуля, а прогресс-бар показывает '
            'позицию предыдущего: ${pb.positionMs}',
      );

      pb.dispose();
    });
  });

  group('автопереход по концу трека', () {
    test(
        'P-002: устаревшая позиция прокручивает очередь дальше без окончания трека',
        () async {
      final pb = await playingCustomPlaylist();

      playerState = {
        'is_playing': true,
        'progress_ms': 199500,
        'item': {
          'uri': 'spotify:track:t0',
          'name': 'Track 0',
          'artists': [
            {'name': 'Artist'}
          ],
          'duration_ms': 200000,
        },
      };

      await Future<void>.delayed(const Duration(milliseconds: 9000));

      final played = playedUris().where((u) => u.isNotEmpty).toList();
      expect(
        played,
        hasLength(lessThanOrEqualTo(1)),
        reason: 'после автоперехода позиция нового трека осталась от старого, '
            'и очередь прокручивается каждые ~2 c: $played',
      );

      pb.dispose();
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  group('дубликаты в очереди', () {
    test('P-003: повтор трека в плейлисте сбивает позицию очереди', () async {
      final dup = [
        {'uri': 'spotify:track:a', 'index': 0, 'name': 'A'},
        {'uri': 'spotify:track:b', 'index': 1, 'name': 'B'},
        {'uri': 'spotify:track:a', 'index': 2, 'name': 'A'},
        {'uri': 'spotify:track:c', 'index': 3, 'name': 'C'},
      ];

      final pb = PlaybackProvider();
      pb.setApiService(api);

      await pb.playTrack(
        {'uri': 'spotify:track:a', 'index': 2, 'title': 'A'},
        knownPlaylistTracks: dup,
      );

      expect(pb.currentQueueIndex, 2);

      playerState = {
        'is_playing': true,
        'progress_ms': 1000,
        'item': {
          'uri': 'spotify:track:a',
          'name': 'A',
          'artists': [
            {'name': 'Artist'}
          ],
          'duration_ms': 200000,
        },
      };
      await pb.refreshAfterResume();
      await Future<void>.delayed(const Duration(milliseconds: 3400));

      expect(
        pb.currentQueueIndex,
        2,
        reason: 'играет второе вхождение A — позиция очереди не должна '
            'перепрыгивать на первое',
      );

      pb.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('границы очереди', () {
    test('P-004: Next на последнем треке без repeat останавливает плейлист',
        () async {
      final pb = await playingCustomPlaylist(startIndex: 5);

      await pb.skipNext();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(pb.playlistEnded, isTrue);
      expect(pb.isPlaying, isFalse);

      pb.dispose();
    });

    test('P-005: Previous на первом треке не выходит за границу', () async {
      final pb = await playingCustomPlaylist();

      await pb.skipPrevious();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(pb.currentQueueIndex, 0);

      pb.dispose();
    });

    test('P-006: очередь из одного трека — Next не роняет провайдер', () async {
      final single = [
        {'uri': 'spotify:track:only', 'index': 0, 'name': 'Only'}
      ];
      final pb = PlaybackProvider();
      pb.setApiService(api);
      await pb.playTrack(
        Map<String, dynamic>.from(single.first),
        knownPlaylistTracks: single,
      );
      calls.clear();

      await pb.skipNext();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(pb.playlistEnded, isTrue);
      pb.dispose();
    });
  });

  group('repeat / shuffle', () {
    test('P-008: repeat=context на последнем треке возвращает в начало',
        () async {
      final pb = await playingCustomPlaylist(startIndex: 5);
      await pb.cycleRepeatMode();
      expect(pb.repeatMode, 'context');
      calls.clear();
      playBodies.clear();

      await pb.skipNext();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(pb.currentQueueIndex, 0);
      expect(pb.playlistEnded, isFalse);

      pb.dispose();
    });

    test('P-009: повторное включение shuffle не ломает позицию очереди',
        () async {
      final pb = await playingCustomPlaylist(startIndex: 2);

      await pb.setShuffle(true);
      await pb.setShuffle(false);
      await pb.setShuffle(true);

      expect(pb.currentQueueIndex, 2);
      expect(pb.nextQueueTrack, isNull, reason: 'при shuffle соседей нет');

      pb.dispose();
    });
  });
}
