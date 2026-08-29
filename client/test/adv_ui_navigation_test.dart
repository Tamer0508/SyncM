import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/models/user.dart';
import 'package:syncm/providers/auth_provider.dart';
import 'package:syncm/providers/friends_provider.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/providers/playlists_provider.dart';
import 'package:syncm/providers/session_provider.dart';
import 'package:syncm/providers/theme_provider.dart';
import 'package:syncm/screens/home/home_screen.dart';
import 'package:syncm/screens/playlist/playlist_tracks_screen.dart';
import 'package:syncm/theme.dart';

class _StubAuth extends AuthProvider {
  @override
  User? get user => const User(id: 'u1', displayName: 'Тестер');

  @override
  bool get isLoggedIn => true;

  @override
  bool get loading => false;
}

class _StubFriends extends FriendsProvider {
  @override
  Future<void> fetchFriends({bool refresh = false, int limit = 20}) async {}

  @override
  Future<void> fetchIncomingRequests({bool refresh = false, int limit = 20}) async {}
}

class _StubSessions extends SessionProvider {
  @override
  Future<void> fetchMySessions() async {}

  @override
  Future<void> fetchInvites() async {}
}

class _StubPlayback extends PlaybackProvider {
  @override
  Map<String, dynamic>? get currentTrack => null;

  @override
  bool get isPlaying => false;
}

class _StubPlaylists extends PlaylistsProvider {
  _StubPlaylists(this._items);

  final List<Map<String, dynamic>> _items;

  @override
  List<Map<String, dynamic>> get custom => _items;

  @override
  List<Map<String, dynamic>> get spotify => const [];

  @override
  bool get loadingCustom => false;

  @override
  bool get loadingSpotify => false;

  @override
  Future<void> loadAll({bool refresh = false}) async {}

  @override
  Future<void> loadCustom({bool refresh = false}) async {}

  @override
  Future<void> loadSpotify({bool refresh = false}) async {}

  @override
  Map<String, dynamic>? byId(String id) {
    for (final item in _items) {
      if (item['id'] == id) return item;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>?> tracksOf(
    String playlistId, {
    required bool isCustom,
    bool refresh = false,
  }) async =>
      const [];
}

class _PushCounter extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.remove(route);
  }

  int get named =>
      pushed.where((r) => r.settings.name != null && r.settings.name != '/').length;
}

const _playlists = [
  {'id': 'p1', 'name': 'Первый', 'isCustom': true, 'trackCount': 2},
  {'id': 'p2', 'name': 'Второй', 'isCustom': true, 'trackCount': 5},
];

Future<_PushCounter> _pumpHome(WidgetTester tester, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final observer = _PushCounter();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _StubAuth()),
        ChangeNotifierProvider<FriendsProvider>(create: (_) => _StubFriends()),
        ChangeNotifierProvider<SessionProvider>(create: (_) => _StubSessions()),
        ChangeNotifierProvider<PlaybackProvider>(create: (_) => _StubPlayback()),
        ChangeNotifierProvider<PlaylistsProvider>(
          create: (_) => _StubPlaylists(
            _playlists.map(Map<String, dynamic>.from).toList(),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        theme: AppTheme.build(
          brightness: Brightness.light,
          accent: AccentColor.values.first,
          compact: false,
          reduceMotion: reduceMotion,
        ),
        locale: const Locale('en'),
        navigatorObservers: [observer],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Center(child: Text('=${settings.name}'))),
        ),
        home: const HomeScreen(),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return observer;
}

Future<void> _tapTwice(WidgetTester tester, Finder finder, {Duration gap = const Duration(milliseconds: 16)}) async {
  await tester.tap(finder, warnIfMissed: false);
  if (gap > Duration.zero) await tester.pump(gap);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('повторное касание аватара не должно открывать второй профиль',
      (tester) async {
    final observer = await _pumpHome(tester);

    await _tapTwice(tester, find.byTooltip('Profile').first, gap: Duration.zero);
    await tester.pumpAndSettle();

    debugPrint('PUSHCOUNT=${observer.pushed.length} named=${observer.named}');
    expect(observer.named, 1,
        reason: 'в стопке ${observer.named} экранов профиля вместо одного');
  });

  testWidgets('повторное касание плейлиста не должно открывать его дважды',
      (tester) async {
    await _pumpHome(tester);

    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Первый'), findsOneWidget);

    await _tapTwice(tester, find.text('Первый'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistTracksScreen), findsOneWidget,
        reason: 'экран плейлиста лёг в стопку дважды: назад придётся нажимать '
            'два раза, второй раз — по уже несуществующему списку');
  });
}
