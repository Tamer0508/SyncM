import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/services/api_service.dart';
import 'package:syncm/services/media_session_bridge.dart';

void main() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late ApiService api;
  late List<String> calls;
  late List<MethodCall> session;
  late Map<String, dynamic> playerState;

  const channel = MethodChannel('syncm/media_session');

  final tracks = List.generate(
    3,
    (i) => {
      'uri': 'spotify:track:t$i',
      'index': i,
      'name': 'Track $i',
      'title': 'Track $i',
      'artist': 'Artist',
      'durationMs': 200000,
    },
  );

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('syncm_media').path,
    );
  });

  setUp(() async {
    HttpOverrides.global = null;
    calls = [];
    session = [];
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      session.add(call);
      return null;
    });

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');
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
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await server.close(force: true);
  });

  /// Провайдер с играющим треком и уже подключённым мостом.
  Future<PlaybackProvider> playing() async {
    // Конструктор подключает мост; playTrack должен идти уже по windows-ветке.
    final pb = PlaybackProvider();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    pb.setApiService(api);
    await pb.playTrack(
      Map<String, dynamic>.from(tracks[0]),
      knownPlaylistTracks: tracks,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return pb;
  }

  void restorePlatform() =>
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

  List<MethodCall> named(String method) =>
      session.where((c) => c.method == method).toList();

  /// Дёргает мост так же, как это делает нативная сторона.
  Future<void> command(String action, [int? value]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('command', {'action': action, 'value': value}),
      ),
      (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('состояние уходит в карточку', () {
    test('M-001: старт трека отдаёт метаданные один раз и играющее состояние',
        () async {
      final pb = await playing();
      restorePlatform();

      final setTrack = named('setTrack');
      expect(setTrack, hasLength(1));
      expect(setTrack.single.arguments['trackId'], 'spotify:track:t0');
      expect(setTrack.single.arguments['title'], 'Track 0');
      expect(setTrack.single.arguments['artist'], 'Artist');
      expect(setTrack.single.arguments['durationMs'], 200000);

      // Одно состояние, а не пара «ещё не играет» → «играет»: провайдер
      // сообщает о запуске сразу, не дожидаясь ответа плеера.
      final states = named('setPlaybackState');
      expect(states, hasLength(1));
      expect(states.single.arguments['isPlaying'], isTrue);
      // Плеер старт ещё не подтвердил — карточке говорим «буферизация», иначе
      // система начнёт отсчитывать прогресс от несуществующего момента.
      expect(states.single.arguments['buffering'], isTrue);
      expect(states.single.arguments['positionMs'], lessThan(1000));

      pb.dispose();
    });

    test('M-002: повторные уведомления без изменений не идут в канал',
        () async {
      final pb = await playing();
      final before = session.length;

      // Провайдер сообщает о себе снова, ничего не изменив.
      pb.notifyListeners();
      pb.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      restorePlatform();

      expect(session.length, before);
      pb.dispose();
    });

    test('M-003: перемотка обновляет состояние, хотя трек и play/pause те же',
        () async {
      final pb = await playing();
      final before = named('setPlaybackState').length;

      await pb.seekTo(120000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      restorePlatform();

      final states = named('setPlaybackState');
      expect(states.length, before + 1);
      expect(states.last.arguments['positionMs'], 120000);
      pb.dispose();
    });

    test('M-004: пауза уезжает в карточку', () async {
      final pb = await playing();

      await pb.togglePlay();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      restorePlatform();

      expect(named('setPlaybackState').last.arguments['isPlaying'], isFalse);
      pb.dispose();
    });

    test('M-014: Play/Pause меняет состояние до ответа Spotify, а не после',
        () async {
      final pb = await playing();
      expect(pb.isPlaying, isTrue);

      // Намеренно не ждём: кнопка не должна залипать на время round-trip.
      final command = pb.togglePlay();
      expect(pb.isPlaying, isFalse,
          reason: 'состояние обязано смениться в том же кадре');

      await command;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      restorePlatform();

      expect(calls.where((c) => c.contains('/spotify/pause')), hasLength(1));
      expect(named('setPlaybackState').last.arguments['isPlaying'], isFalse);
      pb.dispose();
    });

    test('M-015: серия Play/Pause не плодит конкурирующие команды', () async {
      final pb = await playing();
      calls.clear();

      // Пять нажатий подряд: наружу уходит не пять параллельных запросов, а
      // последовательность, и последнее намерение обязательно исполняется.
      final commands = [
        pb.togglePlay(),
        pb.togglePlay(),
        pb.togglePlay(),
        pb.togglePlay(),
        pb.togglePlay(),
      ];
      expect(pb.isPlaying, isFalse, reason: 'нечётное число нажатий');

      await Future.wait(commands);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      restorePlatform();

      final sent = calls
          .where((c) =>
              c.contains('/spotify/pause') || c.contains('/spotify/resume'))
          .toList();
      expect(sent, isNotEmpty);
      expect(sent.length, lessThanOrEqualTo(5));
      expect(sent.last, contains('/spotify/pause'));
      expect(pb.isPlaying, isFalse);
      pb.dispose();
    });

    test('M-016: тикер позиции сам по себе не гоняет состояние в канал',
        () async {
      final pb = await playing();
      final before = named('setPlaybackState').length;

      await Future<void>.delayed(const Duration(milliseconds: 700));
      restorePlatform();

      expect(named('setPlaybackState').length, before);
      pb.dispose();
    });

    test('M-005: остановка снимает карточку, а не оставляет старый трек',
        () async {
      final pb = await playing();

      pb.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      restorePlatform();

      expect(named('release'), hasLength(1));
      pb.dispose();
    });
  });

  group('команды карточки идут в существующую интеграцию', () {
    test('M-006: PLAY на играющем треке не ставит его на паузу', () async {
      final pb = await playing();
      calls.clear();

      await command('play');
      restorePlatform();

      expect(calls.where((c) => c.contains('/spotify/pause')), isEmpty);
      expect(calls.where((c) => c.contains('/spotify/resume')), isEmpty);
      pb.dispose();
    });

    test('M-007: PAUSE на играющем треке паузит через ApiService', () async {
      final pb = await playing();
      calls.clear();

      await command('pause');
      restorePlatform();

      expect(calls.where((c) => c.contains('/spotify/pause')), hasLength(1));
      expect(pb.isPlaying, isFalse);
      pb.dispose();
    });

    test('M-008: SEEK доходит до плеера с нужной позицией', () async {
      final pb = await playing();
      calls.clear();

      await command('seek', 90000);
      restorePlatform();

      expect(calls.where((c) => c.contains('/spotify/seek')), isNotEmpty);
      expect(pb.positionMs, greaterThanOrEqualTo(90000));
      pb.dispose();
    });

    test('M-009: NEXT переключает трек существующей очередью, а не своей',
        () async {
      final pb = await playing();
      calls.clear();

      await command('next');
      restorePlatform();

      expect(calls.where((c) => c == 'POST /spotify/play'), hasLength(1));
      expect(pb.currentTrack?['uri'], 'spotify:track:t1');
      pb.dispose();
    });

    test('M-010: серия NEXT не превращается в гонку команд', () async {
      final pb = await playing();
      calls.clear();

      await Future.wait([
        command('next'),
        command('next'),
        command('next'),
      ]);
      restorePlatform();

      // Защита _skip() пропускает одно переключение, а не три подряд.
      expect(calls.where((c) => c == 'POST /spotify/play'), hasLength(1));
      pb.dispose();
    });

    test('M-011: SHUFFLE из карточки идёт через существующий setShuffle',
        () async {
      final pb = await playing();
      calls.clear();

      await command('shuffle', 1);
      restorePlatform();

      expect(calls.where((c) => c.contains('/spotify/shuffle')), isNotEmpty);
      expect(pb.shuffleActive, isTrue);
      pb.dispose();
    });

    test('M-012: REPEAT докручивается до запрошенного режима', () async {
      final pb = await playing();

      // PlaybackStateCompat.REPEAT_MODE_ONE
      await command('repeat', 1);
      restorePlatform();

      expect(pb.repeatMode, 'track');
      pb.dispose();
    });
  });

  test('M-013: мост отпускает провайдер при dispose', () async {
    final pb = await playing();
    restorePlatform();

    pb.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(named('release'), isNotEmpty);
    // Мост больше не держит ссылку — повторный attach безопасен.
    MediaSessionBridge.instance.detach(pb);
  });
}
