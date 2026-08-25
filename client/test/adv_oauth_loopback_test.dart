// Adversarial-тесты локального OAuth-сервера (Windows-вход через Google).
//
// Все тесты в этом файле НАМЕРЕННО падают на текущей реализации:
// они фиксируют ожидаемое корректное поведение, а не текущее.
//
// Атакуемый код: client/lib/services/oauth_loopback_io.dart
//                client/lib/screens/login/google_sign.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncm/services/oauth_loopback.dart';

/// Шлёт GET и молча глотает ошибки: нас интересует реакция сервера,
/// а не тело ответа.
Future<void> _hit(Uri uri) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    await res.drain<void>();
  } catch (_) {
    // соединение могло быть закрыто сервером — это нормально
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('OAuth loopback', () {
    tearDown(() async {
      await stopOAuthLoopback();
    });

    test('колбэк с чужого пути не должен приниматься за успешный вход', () async {
      const port = 45871;

      final result = await runOAuthLoopback(
        port: port,
        path: '/callback',
        timeout: const Duration(seconds: 3),
        onServerReady: (_) async {
          // Атака: любая веб-страница, открытая у жертвы, может увести
          // браузер на localhost с чужим токеном. Путь не совпадает с
          // тем, что был отдан провайдеру как redirect_uri.
          await _hit(Uri.parse('http://localhost:$port/anything?token=ATTACKER_TOKEN'));
        },
      );

      expect(
        result?['token'],
        isNot('ATTACKER_TOKEN'),
        reason: 'Сервер обязан принимать колбэк только по своему redirect-пути; '
            'иначе жертву можно залогинить в чужой аккаунт (login CSRF).',
      );
    });

    test('запрос без token/cookie не должен завершать вход', () async {
      const port = 45872;

      final result = await runOAuthLoopback(
        port: port,
        path: '/callback',
        timeout: const Duration(seconds: 3),
        onServerReady: (_) async {
          // Посторонний стук в порт: префетч браузера, антивирус,
          // старая вкладка. Полезной нагрузки нет.
          await _hit(Uri.parse('http://localhost:$port/callback'));
        },
      );

      final tokenless =
          result != null && result['token'] == null && result['cookie'] == null;

      expect(
        tokenless,
        isFalse,
        reason: 'Пустой колбэк не должен считаться результатом: сейчас он гасит '
            'локальный сервер, и настоящий редирект от провайдера приходить уже некуда.',
      );
    });

    test('порт локального сервера должен быть занят монопольно', () async {
      const port = 45873;

      // Сначала порт занимает посторонний процесс.
      final squatter = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      addTearDown(() async => squatter.close(force: true));

      Object? bindError;
      final done = Completer<void>();

      unawaited(
        runOAuthLoopback(
          port: port,
          timeout: const Duration(seconds: 2),
          onServerReady: (_) async {},
        ).then((_) {
          if (!done.isCompleted) done.complete();
        }).catchError((Object e) {
          bindError = e;
          if (!done.isCompleted) done.complete();
        }),
      );

      await done.future.timeout(const Duration(seconds: 6), onTimeout: () {});

      expect(
        bindError,
        isA<SocketException>(),
        reason: 'runOAuthLoopback биндится с shared: true и встаёт на уже занятый порт. '
            'Посторонний слушатель на 127.0.0.1 продолжает получать часть колбэков, '
            'то есть может перехватить токен входа.',
      );
    });
  });
}
