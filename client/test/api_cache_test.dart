import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncm/services/api_service.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late ApiService api;
  var sessionHits = 0;
  var playlistHits = 0;

  setUp(() async {
    sessionHits = 0;
    playlistHits = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/sessions') sessionHits++;
      if (request.uri.path == '/playlists') playlistHits++;

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode([
          {'id': 's1', 'name': 'Сессия'}
        ]));
      await request.response.close();
    });

    api = ApiService.instance(
      baseUrl: 'http://${server.address.address}:${server.port}',
      timeout: const Duration(seconds: 5),
    );
    api.setCookie('test-token');
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('GET доходит до сервера и возвращает данные', () async {
    final sessions = await api.getMySessions();

    expect(sessions, hasLength(1));
    expect(sessionHits, 1);
  });

  test('одновременные запросы схлопываются в один', () async {
    final results = await Future.wait([
      api.getMyPlaylists(),
      api.getMyPlaylists(),
      api.getMyPlaylists(),
    ]);

    expect(results, hasLength(3));
    expect(playlistHits, 1, reason: 'три запроса должны стать одним');
  });

  test('повторный запрос в пределах TTL не идёт в сеть', () async {
    await api.getMyPlaylists();
    await api.getMyPlaylists();

    expect(playlistHits, 1);
  });

  test('refresh обходит кэш', () async {
    await api.getMyPlaylists();
    await api.getMyPlaylists(refresh: true);

    expect(playlistHits, 2);
  });

  test('несколько последовательных запросов не залипают на общем клиенте', () async {
    for (var i = 0; i < 5; i++) {
      final data = await api.getMySessions(  );
      expect(data, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 3100));
    }

    expect(sessionHits, 5);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
