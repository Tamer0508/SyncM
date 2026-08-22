import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncm/providers/auth_provider.dart';
import 'package:syncm/utils/artwork_color_store.dart';
import 'package:syncm/utils/local_store.dart';

/// Проверяем ровно то, ради чего эти слои существуют: данные, известные с
/// прошлого запуска, доступны синхронно — до первого кадра и без сети.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ArtworkColorStore.resetForTest();
  });

  Future<void> initStore(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await LocalStore.init();
  }

  group('LocalStore', () {
    test('объект переживает запись и чтение', () async {
      await initStore({});

      await LocalStore.saveMap(StoreKeys.me, {'id': 'u1', 'displayName': 'Аня'});

      expect(LocalStore.readMap(StoreKeys.me), {'id': 'u1', 'displayName': 'Аня'});
    });

    test('битая запись не роняет чтение', () async {
      await initStore({'flutter.${StoreKeys.profiles}': 'не json'});

      expect(LocalStore.readMap(StoreKeys.profiles), isNull);
    });
  });

  group('ArtworkColorStore', () {
    test('сохранённый цвет доступен синхронно после restore', () async {
      const url = 'https://example.test/avatar.jpg';
      await initStore({
        'flutter.${StoreKeys.artworkColors}': jsonEncode({url: 0xFF336699}),
      });

      ArtworkColorStore.restore();

      expect(ArtworkColorStore.cached(url), const Color(0xFF336699));
    });

    test('неизвестная картинка не выдумывает цвет', () async {
      await initStore({});
      ArtworkColorStore.restore();

      expect(ArtworkColorStore.cached('https://example.test/none.jpg'), isNull);
      expect(ArtworkColorStore.cached(null), isNull);
      expect(ArtworkColorStore.cached(''), isNull);
    });

    test('remember кладёт цвет в память сразу', () async {
      await initStore({});
      ArtworkColorStore.restore();

      const url = 'https://example.test/cover.jpg';
      ArtworkColorStore.remember(url, const Color(0xFF102030));

      expect(ArtworkColorStore.cached(url), const Color(0xFF102030));
    });
  });

  group('AuthProvider', () {
    test('поднимает профиль и токен из снимка до первого кадра', () async {
      await initStore({
        'flutter.syncm_auth_token': 'token-123',
        'flutter.${StoreKeys.me}': jsonEncode({
          'id': 'u1',
          'displayName': 'Аня',
          'avatarUrl': 'https://example.test/avatar.jpg',
        }),
      });

      final auth = AuthProvider();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.user?.displayName, 'Аня');
      // Токен обязан подняться вместе с профилем: иначе первый экран уйдёт
      // в сеть без авторизации и получит 401.
      expect(auth.cookie, 'token-123');
    });

    test('без токена снимок не поднимается', () async {
      await initStore({
        'flutter.${StoreKeys.me}': jsonEncode({'id': 'u1', 'displayName': 'Аня'}),
      });

      final auth = AuthProvider();

      expect(auth.isLoggedIn, isFalse);
    });
  });
}
