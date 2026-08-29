import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncm/services/api_service.dart';

void main() {
  test('ответ прошлого пользователя не должен оседать в кэше после смены аккаунта',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final firstRequestArrived = Completer<void>();
    final releaseFirstResponse = Completer<void>();
    var served = 0;

    unawaited(() async {
      await for (final request in server) {
        served++;
        final isFirst = served == 1;
        if (isFirst) {
          if (!firstRequestArrived.isCompleted) firstRequestArrived.complete();
          await releaseFirstResponse.future;
        }

        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode([
            {'name': isFirst ? 'USER_A_TRACK' : 'USER_B_TRACK'}
          ]));
        await request.response.close();
      }
    }());

    final api = ApiService.instance(
      baseUrl: 'http://127.0.0.1:${server.port}',
      timeout: const Duration(seconds: 10),
    );

    api.setCookie('token-user-A');
    final pendingForA = api.getPlayHistory();
    await firstRequestArrived.future;

    api.setCookie('');
    api.setCookie('token-user-B');

    releaseFirstResponse.complete();
    await pendingForA;

    final historyForB = await api.getPlayHistory();
    final names = historyForB.map((e) => e['name']).toList();

    expect(
      names,
      isNot(contains('USER_A_TRACK')),
      reason: 'clearCache() отработал ДО того, как завершился запрос предыдущего '
          'пользователя, а колбэк .then() в _cachedGet пишет ответ в _getCache '
          'безусловно — уже после очистки. Новый пользователь получает историю '
          'прослушиваний предыдущего.',
    );
    expect(names, contains('USER_B_TRACK'));
  });
}
