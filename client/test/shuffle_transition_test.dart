import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/services/api_service.dart';

/// Один свайп — одно переключение трека.
///
/// Тесты гоняют windows-ветку провайдера: там всё воспроизведение идёт через
/// ApiService, поэтому команды к плееру видно как обычные HTTP-запросы и их
/// можно пересчитать. Нативная ветка (SpotifySdk) в тестах недоступна, но
/// правило одно и то же — команда воспроизведения на одно действие.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late ApiService api;
  late List<String> calls;

  final tracks = List.generate(
    20,
    (i) => {
      'uri': 'spotify:track:t$i',
      'index': i,
      'name': 'Track $i',
      'artist': 'Artist',
    },
  );

  setUpAll(() {
    // Плагины в тестовой среде отсутствуют: провайдер по пути к плееру
    // трогает кэш изображений (path_provider) и настройки задержки.
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

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');

      // Плеер сообщает трек из того же плейлиста: автокоррекция «трек не из
      // плейлиста» в такой ситуации срабатывать не должна.
      final body = request.uri.path == '/spotify/player'
          ? jsonEncode({
              'is_playing': true,
              'progress_ms': 1000,
              'item': {
                'uri': 'spotify:track:t3',
                'name': 'Track 3',
                'artists': [
                  {'name': 'Artist'}
                ],
                'duration_ms': 200000,
              },
            })
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

  Future<PlaybackProvider> playingFromPlaylist() async {
    final pb = PlaybackProvider();
    pb.setApiService(api);

    await pb.playTrack(
      Map<String, dynamic>.from(tracks.first),
      playlistId: 'playlist1',
      knownPlaylistTracks: tracks,
    );

    await pb.setShuffle(true);
    expect(pb.shuffleActive, isTrue);

    calls.clear();
    return pb;
  }

  int playCommands() => calls.where((c) => c == 'POST /spotify/play').length;

  test('свайп при включённом Shuffle даёт ровно одну команду плееру', () async {
    final pb = await playingFromPlaylist();

    await pb.skipNext();
    // Даём фону шанс прислать второе переключение, если оно есть.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      playCommands(),
      1,
      reason: 'одно действие пользователя — одно переключение, а не два: $calls',
    );

    pb.dispose();
  });

  test('трек меняется ровно один раз', () async {
    final pb = await playingFromPlaylist();

    // Стартовый трек в список не попадает — считаем только переключения
    // после свайпа.
    final seen = <String>[pb.currentTrack?['uri'] as String? ?? ''];
    void listener() {
      final uri = pb.currentTrack?['uri'] as String?;
      if (uri != null && seen.last != uri) seen.add(uri);
    }

    pb.addListener(listener);
    await pb.skipNext();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    pb.removeListener(listener);

    final transitions = seen.skip(1).toList();
    expect(transitions.length, 1, reason: 'подряд показанные треки: $seen');
    expect(transitions.single, isNot('spotify:track:t0'));

    pb.dispose();
  });

  test('быстрые повторные свайпы не ставят переключения в очередь', () async {
    final pb = await playingFromPlaylist();

    await Future.wait([pb.skipNext(), pb.skipNext(), pb.skipNext()]);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      playCommands(),
      1,
      reason: 'замок скипа должен схлопнуть очередь свайпов: $calls',
    );

    pb.dispose();
  });

  _guardInvariant();

  test('случайный трек выбирается внутри текущего плейлиста', () async {
    final pb = await playingFromPlaylist();

    await pb.skipNext();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final uri = pb.currentTrack?['uri'] as String?;
    expect(tracks.map((t) => t['uri']), contains(uri));

    pb.dispose();
  });
}

/// Сторожевой тест на архитектурный инвариант.
///
/// Баг двойного переключения был не в логике выбора трека, а в том, что
/// случайный выбор рассылал команды плееру сам: сначала перезапускал контекст
/// плейлиста, а через полсекунды прыгал на нужный индекс. Две команды — два
/// переключения на экране.
///
/// Windows-ветку выше проверить запросами можно, нативную (SpotifySdk) — нет:
/// это статические вызовы плагина. Поэтому инвариант закреплён по исходнику:
/// команды воспроизведения отдаёт только playTrack, у которого есть и защита
/// от лишнего перезапуска контекста, и подавление промежуточных событий SDK.
void _guardInvariant() {
  test('случайный выбор не отдаёт команды плееру сам', () {
    final source =
        File('lib/providers/playback_provider.dart').readAsStringSync();

    const start = 'Future<void> _playRandomFromCurrentPlaylist() async {';
    final from = source.indexOf(start);
    expect(from, isNot(-1), reason: 'метод переименован — обнови тест');

    final rest = source.substring(from + start.length);
    final end = rest.indexOf('\n  Future<');
    final full = end == -1 ? rest : rest.substring(0, end);

    // Комментарии выбрасываем: в них эти вызовы упоминаются как раз затем,
    // чтобы объяснить, почему их здесь быть не должно.
    final body = full
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    expect(
      body,
      isNot(contains('SpotifySdk.play(')),
      reason: 'перезапуск контекста здесь и был вторым переключением',
    );
    expect(body, isNot(contains('SpotifySdk.skipToIndex(')));
    expect(body, isNot(contains('_apiService?.playTrack(')));
    expect(
      body,
      contains('await playTrack('),
      reason: 'воспроизведение должно идти через общую точку входа',
    );
  });
}
