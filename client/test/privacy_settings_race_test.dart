import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncm/models/user.dart';
import 'package:syncm/providers/auth_provider.dart';
import 'package:syncm/services/api_service.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late ApiService api;
  late AuthProvider auth;

  late Map<String, bool> stored;

  late List<Map<String, dynamic>> patches;
  late List<String?> keys;

  late Duration delay;

  late int failNext;

  late int failStatus;

  const open = {
    'isFriendsHidden': false,
    'isActivityHidden': false,
    'isOnlineHidden': false,
    'isSearchHidden': false,
  };
  const friendsOnly = {
    'isFriendsHidden': false,
    'isActivityHidden': false,
    'isOnlineHidden': false,
    'isSearchHidden': true,
  };
  const hidden = {
    'isFriendsHidden': true,
    'isActivityHidden': true,
    'isOnlineHidden': true,
    'isSearchHidden': true,
  };

  setUp(() async {
    stored = Map<String, bool>.from(open);
    patches = [];
    keys = [];
    delay = Duration.zero;
    failNext = 0;
    failStatus = 500;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'PATCH' && request.uri.path == '/auth/settings') {
        final raw = await utf8.decoder.bind(request).join();
        final patch = jsonDecode(raw) as Map<String, dynamic>;
        patches.add(patch);
        keys.add(request.headers.value('idempotency-key'));

        if (delay > Duration.zero) await Future<void>.delayed(delay);

        if (failNext > 0) {
          failNext--;
          request.response
            ..statusCode = failStatus
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'error': 'Не сохранилось'}));
          await request.response.close();
          return;
        }

        patch.forEach((key, value) => stored[key] = value as bool);
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(stored));
        await request.response.close();
        return;
      }

      if (request.uri.path == '/auth/me') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'id': 'u1',
            'displayName': 'Тест',
            ...stored,
          }));
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      await request.response.close();
    });

    api = ApiService.instance(
      baseUrl: 'http://${server.address.address}:${server.port}',
      timeout: const Duration(seconds: 5),
    );
    api.setCookie('test-token');

    auth = AuthProvider(api: api);
    auth.setUser(const User(id: 'u1', displayName: 'Тест'));
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('три быстрых нажатия подряд: побеждает последний выбор', () async {
    delay = const Duration(milliseconds: 60);

    final flush = auth.updateSettings(open);
    unawaited(auth.updateSettings(friendsOnly));
    unawaited(auth.updateSettings(hidden));

    expect(auth.user!.isOnlineHidden, isTrue);
    expect(auth.user!.isFriendsHidden, isTrue);

    await flush;

    expect(stored, hidden);
    expect(auth.user!.isFriendsHidden, isTrue);
    expect(auth.user!.isActivityHidden, isTrue);
    expect(auth.user!.isOnlineHidden, isTrue);
    expect(auth.user!.isSearchHidden, isTrue);

    expect(patches, hasLength(2));
    expect(patches.last, containsPair('isFriendsHidden', true));

    expect(keys.whereType<String>(), hasLength(2));
    expect(keys.toSet(), hasLength(2));
  });

  test('десять кликов подряд не превращаются в десять запросов', () async {
    delay = const Duration(milliseconds: 40);

    Future<void>? flush;
    for (var i = 0; i < 10; i++) {
      final next = auth.updateSettings(i.isEven ? open : hidden);
      flush ??= next;
    }
    await flush;

    expect(stored, hidden);
    expect(auth.user!.isOnlineHidden, isTrue);
    expect(patches.length, lessThanOrEqualTo(2));
    expect(keys.toSet(), hasLength(patches.length));
  });

  test('ошибка сервера: экран откатывается и ошибка доходит до вызова',
      () async {
    failNext = 1;
    failStatus = 500;

    await expectLater(
      auth.updateSettings(const {'isOnlineHidden': true}),
      throwsA(isA<ApiException>()),
    );

    expect(auth.user!.isOnlineHidden, isFalse);
    expect(stored['isOnlineHidden'], isFalse);
  });

  test('повтор после сбоя уходит с тем же ключом идемпотентности', () async {
    failNext = 1;
    failStatus = 503;

    await auth.updateSettings(const {'isOnlineHidden': true});

    expect(patches, hasLength(2));
    expect(keys.toSet(), hasLength(1));
    expect(stored['isOnlineHidden'], isTrue);
    expect(auth.user!.isOnlineHidden, isTrue);
  });

  test('перечитывание профиля во время отправки не откатывает выбор',
      () async {
    delay = const Duration(milliseconds: 150);

    final flush = auth.updateSettings(const {'isSearchHidden': true});

    await auth.fetchMe();
    expect(auth.user!.isSearchHidden, isTrue);

    await flush;
    expect(auth.user!.isSearchHidden, isTrue);
    expect(stored['isSearchHidden'], isTrue);
  });

  test('одиночное нажатие сохраняется', () async {
    await auth.updateSettings(const {'isActivityHidden': true});

    expect(patches, hasLength(1));
    expect(stored['isActivityHidden'], isTrue);
    expect(auth.user!.isActivityHidden, isTrue);
  });
}
