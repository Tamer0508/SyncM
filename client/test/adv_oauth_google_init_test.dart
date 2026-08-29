import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _libDir = Directory('lib');

List<({String file, String call})> _initializeCallSites() {
  final sites = <({String file, String call})>[];
  final pattern = RegExp(r'GoogleSignIn\.instance\.initialize\s*\(');

  for (final entity in _libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();

    for (final match in pattern.allMatches(source)) {
      var depth = 0;
      var end = match.end - 1;
      for (var i = match.end - 1; i < source.length; i++) {
        if (source[i] == '(') depth++;
        if (source[i] == ')') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      sites.add((
        file: entity.path.replaceAll(r'\', '/'),
        call: source.substring(match.start, end + 1),
      ));
    }
  }
  return sites;
}

void main() {
  test('Google Sign-In инициализируется из одного места', () {
    final sites = _initializeCallSites();

    expect(
      sites.map((s) => s.file).toList(),
      hasLength(1),
      reason: 'GoogleSignIn.instance.initialize() вызывается из нескольких файлов '
          'с разной конфигурацией. Плагин инициализируется один раз — выигрывает '
          'тот вызов, который стартовал первым, и он недетерминирован '
          '(login_screen делает это в initState без await, google_sign — по нажатию кнопки). '
          'Найдено: ${sites.map((s) => s.file).toSet().join(', ')}',
    );
  });

  test('каждая инициализация передаёт serverClientId', () {
    final sites = _initializeCallSites();
    expect(sites, isNotEmpty, reason: 'вызовы initialize не найдены — тест устарел');

    final without =
        sites.where((s) => !s.call.contains('serverClientId')).map((s) => s.file).toList();

    expect(
      without,
      isEmpty,
      reason: 'Без serverClientId нативный Google Sign-In не выдаёт idToken. '
          'Инициализация без него побеждает в гонке — googleUser.authentication.idToken '
          'приходит null, а _onGoogleSignInSuccess молча делает return, '
          'и вход не происходит без единого сообщения пользователю. '
          'Файлы без serverClientId: ${without.join(', ')}',
    );
  });
}
