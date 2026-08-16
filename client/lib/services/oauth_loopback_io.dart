

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

HttpServer? _server;

bool get supportsOAuthLoopback => true;
Future<void> stopOAuthLoopback() async {
  final server = _server;
  if (server == null) return;
  _server = null;
  try {
    await server.close(force: true);
  } catch (err) {
    debugPrint('Не удалось закрыть локальный сервер авторизации: $err');
  }
}

Future<Map<String, String?>?> runOAuthLoopback({
  required int port,
  required Future<void> Function(String redirectUri) onServerReady,
  Duration timeout = const Duration(minutes: 2),
  String path = '/callback',
  String responseHtml =
      '<html><body><h2>Готово! Вкладку можно закрыть.</h2></body></html>',
}) async {
  await stopOAuthLoopback();

  final completer = Completer<Map<String, String?>?>();
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
    shared: true,
  );
  _server = server;

  StreamSubscription<HttpRequest>? subscription;

  Future<void> finish(Map<String, String?>? result) async {
    await subscription?.cancel();
    subscription = null;
    await stopOAuthLoopback();
    if (!completer.isCompleted) completer.complete(result);
  }

  subscription = server.listen((request) async {
    final uri = request.requestedUri;
    final response = request.response;
    response.headers.set('Content-Type', 'text/html; charset=utf-8');
    response.write(responseHtml);
    try {
      await response.close();
    } catch (err) {
      debugPrint('Не удалось ответить на OAuth-редирект: $err');
    }

    await finish({
      'token': uri.queryParameters['token'],
      'cookie': uri.queryParameters['cookie'],
    });
  }, onError: (Object err) {
    debugPrint('Ошибка локального сервера авторизации: $err');
    finish(null);
  });

  try {
    await onServerReady('http://localhost:$port$path');
  } catch (err) {
    // Ссылку открыть не удалось — держать порт занятым незачем.
    await finish(null);
    rethrow;
  }

  return completer.future.timeout(timeout, onTimeout: () async {
    await finish(null);
    return null;
  });
}