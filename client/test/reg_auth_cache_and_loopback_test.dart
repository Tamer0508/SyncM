import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncm/services/api_service.dart';
import 'package:syncm/services/oauth_loopback.dart';

Future<void> _hit(Uri uri) async {
  final client = HttpClient();
  try {
    final res = await (await client.getUrl(uri)).close();
    await res.drain<void>();
  } catch (_) {
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('кэш API и смена аккаунта', () {
    late HttpServer server;
    late List<String> servedTokens;
    late ApiService api;

    setUp(() async {
      servedTokens = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      unawaited(() async {
        await for (final request in server) {
          final auth = request.headers.value('Authorization') ?? 'none';
          servedTokens.add(auth);
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode([
              {'name': 'история для $auth'}
            ]));
          await request.response.close();
        }
      }());

      api = ApiService.instance(
        baseUrl: 'http://127.0.0.1:${server.port}',
        timeout: const Duration(seconds: 10),
      );
    });

    tearDown(() async => server.close(force: true));

    test('повторный запрос того же пользователя берётся из кэша', () async {
      api.setCookie('token-A');

      final first = await api.getPlayHistory();
      final second = await api.getPlayHistory();

      expect(first, equals(second));
      expect(
        servedTokens,
        hasLength(1),
        reason: 'кэш обязан продолжать работать — исправление не должно было его отключить',
      );
    });

    test('второй пользователь не читает кэш первого', () async {
      api.setCookie('token-A');
      final forA = await api.getPlayHistory();

      api.setCookie('token-B');
      final forB = await api.getPlayHistory();

      expect(forA.first['name'], contains('token-A'));
      expect(forB.first['name'], contains('token-B'));
      expect(servedTokens, hasLength(2), reason: 'для нового аккаунта нужен новый запрос');
    });

    test('второй пользователь не присоединяется к запросу первого', () async {
      api.setCookie('token-A');
      final pendingA = api.getPlayHistory();

      api.setCookie('token-B');
      final forB = await api.getPlayHistory();
      final forA = await pendingA;

      expect(
        forB.first['name'],
        contains('token-B'),
        reason: '_inFlight делится по владельцу токена — присоединиться к чужому запросу нельзя',
      );
      expect(forA.first['name'], contains('token-A'));
    });

    test('refresh обходит кэш и идёт на сервер', () async {
      api.setCookie('token-A');
      await api.getPlayHistory();
      await api.getPlayHistory(refresh: true);

      expect(servedTokens, hasLength(2));
    });
  });

  group('локальный OAuth-сервер', () {
    tearDown(() async => stopOAuthLoopback());

    test('настоящий колбэк по своему пути принимается', () async {
      const port = 45881;

      final result = await runOAuthLoopback(
        port: port,
        path: '/callback',
        timeout: const Duration(seconds: 5),
        onServerReady: (redirectUri) async {
          expect(redirectUri, 'http://localhost:$port/callback');
          await _hit(Uri.parse('$redirectUri?token=REAL_TOKEN'));
        },
      );

      expect(
        result?['token'],
        'REAL_TOKEN',
        reason: 'штатный вход обязан работать после ужесточения проверок',
      );
    });

    test('колбэк с cookie вместо token тоже принимается', () async {
      const port = 45882;

      final result = await runOAuthLoopback(
        port: port,
        path: '/callback',
        timeout: const Duration(seconds: 5),
        onServerReady: (redirectUri) async {
          await _hit(Uri.parse('$redirectUri?cookie=REAL_COOKIE'));
        },
      );

      expect(result?['cookie'], 'REAL_COOKIE');
    });

    test('посторонние запросы не мешают дождаться настоящего колбэка', () async {
      const port = 45883;

      final result = await runOAuthLoopback(
        port: port,
        path: '/callback',
        timeout: const Duration(seconds: 5),
        onServerReady: (redirectUri) async {
          await _hit(Uri.parse('http://localhost:$port/'));
          await _hit(Uri.parse('http://localhost:$port/favicon.ico'));
          await _hit(Uri.parse('http://localhost:$port/evil?token=ATTACKER'));
          await _hit(Uri.parse('http://localhost:$port/callback'));
          await _hit(Uri.parse('$redirectUri?token=REAL_TOKEN'));
        },
      );

      expect(
        result?['token'],
        'REAL_TOKEN',
        reason: 'шум не должен ни завершать вход досрочно, ни подменять токен',
      );
    });

    test('порт освобождается после завершения', () async {
      const port = 45884;

      await runOAuthLoopback(
        port: port,
        path: '/callback',
        timeout: const Duration(seconds: 5),
        onServerReady: (redirectUri) async {
          await _hit(Uri.parse('$redirectUri?token=T'));
        },
      );

      final again = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      addTearDown(() async => again.close(force: true));
      expect(again.port, port);
    });
  });
}
