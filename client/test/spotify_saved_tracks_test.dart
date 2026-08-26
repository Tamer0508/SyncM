

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/auth_provider.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/providers/playlists_provider.dart';
import 'package:syncm/screens/playlist/playlist_tracks_screen.dart';
import 'package:syncm/services/api_service.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/utils/local_store.dart';
import 'package:syncm/widgets/track_card.dart';

class _FakePlaylists extends PlaylistsProvider {
  _FakePlaylists(this._saved);

  final List<Map<String, dynamic>>? _saved;

  @override
  Future<List<Map<String, dynamic>>?> savedTracks({bool refresh = false}) async =>
      _saved;

  @override
  Future<List<Map<String, dynamic>>?> tracksOf(
    String playlistId, {
    required bool isCustom,
    bool refresh = false,
  }) async {
    fail('Любимые треки запрошены как плейлист: id="$playlistId"');
  }

  @override
  Map<String, dynamic>? byId(String playlistId) =>
      fail('Любимые треки искали в списке плейлистов: id="$playlistId"');
}

class _RecordingPlayback extends PlaybackProvider {
  int calls = 0;
  String? lastPlaylistId;
  List<dynamic>? lastQueue;

  @override
  bool get isConnected => true;

  @override
  Future<void> playTrack(
    Map<String, dynamic> track, {
    String? playlistId,
    List<dynamic>? knownPlaylistTracks,
    int? positionMs,
    bool fromSession = false,
    bool announceToSession = true,
  }) async {
    calls++;
    lastPlaylistId = playlistId;
    lastQueue = knownPlaylistTracks;
  }
}

List<Map<String, dynamic>> _tracks(int count) => List.generate(
      count,
      (i) => {
        'id': 't$i',
        'uri': 'spotify:track:t$i',
        'name': 'Трек $i',
        'artist': 'Исполнитель',
        'album': 'Альбом',
        'imageUrl': null,
        'durationMs': 200000,
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late ApiService api;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('syncm_test').path,
    );
  });

  setUp(() async {
    HttpOverrides.global = null;

    SharedPreferences.setMockInitialValues({'settings:auto_open_player': false});
    await LocalStore.init();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = request.uri.path == '/playlists/liked' ? '[]' : '{}';
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
    await server.close(force: true);
  });

  Future<_RecordingPlayback> pumpSaved(
    WidgetTester tester,
    List<Map<String, dynamic>>? saved,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final playback = _RecordingPlayback();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaylistsProvider>.value(
                value: _FakePlaylists(saved)),
            ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => AuthProvider(api: api)),
          ],
          child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: const Locale('ru'),
            theme: AppTheme.build(
              brightness: Brightness.light,
              accent: AccentColor.values.first,
              compact: false,
              reduceMotion: true,
            ),
            home: const PlaylistTracksScreen.spotifySaved(
              playlistName: 'Любимые треки',
            ),
          ),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });

    await tester.pump();
    return playback;
  }

  testWidgets('список берётся у savedTracks, а не у плейлиста',
      (tester) async {
    await pumpSaved(tester, _tracks(3));

    expect(tester.takeException(), isNull);
    expect(find.byType(TrackCard), findsNWidgets(3));
    expect(find.text('Трек 0'), findsOneWidget);
  });

  testWidgets('трек запускается очередью приложения, без контекста Spotify',
      (tester) async {
    final playback = await pumpSaved(tester, _tracks(4));

    await tester.runAsync(() async {
      await tester.tap(find.text('Трек 1'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });

    expect(playback.calls, 1);
    // Ключевое: контекста нет. С ним Spotify после последнего любимого трека
    // ушёл бы в автоплей, а «дальше» перестало бы держаться списка.
    expect(playback.lastPlaylistId, isNull);
    expect(playback.lastQueue, hasLength(4));
  });

  testWidgets('пустой список объясняется, а не выглядит ошибкой',
      (tester) async {
    await pumpSaved(tester, const <Map<String, dynamic>>[]);

    expect(tester.takeException(), isNull);
    expect(find.byType(TrackCard), findsNothing);
    expect(
      find.text('Здесь появятся треки, которые вы сохраните в Spotify.'),
      findsOneWidget,
    );
    expect(find.text('Нет треков'), findsNothing);
  });

  testWidgets('неподключённый Spotify не выдаётся за чужой плейлист',
      (tester) async {
    await pumpSaved(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });
}
