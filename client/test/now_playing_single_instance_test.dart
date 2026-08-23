import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/providers/appearance_provider.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/screens/player/now_playing.dart';

/// Экран трека читает у провайдера только состояние текущего трека —
/// подменять сеть и SDK ради этого теста не нужно.
class _StubPlayback extends PlaybackProvider {
  _StubPlayback(this._track);

  Map<String, dynamic> _track;

  @override
  Map<String, dynamic>? get currentTrack => _track;

  @override
  int get durationMs => 180000;

  void switchTrack(Map<String, dynamic> track) {
    _track = track;
    notifyListeners();
  }
}

Widget _host(PlaybackProvider playback, {required GlobalKey<NavigatorState> key}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
      ChangeNotifierProvider<AppearanceProvider>(
        create: (_) => AppearanceProvider(),
      ),
    ],
    child: MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: Center(child: Text('session'))),
    ),
  );
}

void main() {
  testWidgets('смена трека не кладёт второй экран трека поверх первого',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final playback = _StubPlayback({
      'uri': 'spotify:track:a',
      'title': 'Track A',
      'artist': 'Artist',
    });

    await tester.pumpWidget(_host(playback, key: navigator));

    final context = navigator.currentContext!;

    // Первое открытие — из сессии.
    unawaited(NowPlayingScreen.open(context, title: 'Track A'));
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingScreen), findsOneWidget);
    expect(NowPlayingScreen.isOpen, isTrue);

    // Next/свайп: провайдер сменил трек и снова позвал открыть плеер.
    playback.switchTrack({
      'uri': 'spotify:track:b',
      'title': 'Track B',
      'artist': 'Artist',
    });
    unawaited(NowPlayingScreen.open(context, title: 'Track B'));
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingScreen), findsOneWidget);

    // Ещё несколько переключений подряд ничего не накапливают.
    for (final uri in ['c', 'd', 'e']) {
      playback.switchTrack({
        'uri': 'spotify:track:$uri',
        'title': 'Track $uri',
        'artist': 'Artist',
      });
      unawaited(NowPlayingScreen.open(context, title: 'Track $uri'));
      await tester.pumpAndSettle();
    }

    expect(find.byType(NowPlayingScreen), findsOneWidget);
  });

  testWidgets('после закрытия экран трека можно открыть снова',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final playback = _StubPlayback({
      'uri': 'spotify:track:a',
      'title': 'Track A',
      'artist': 'Artist',
    });

    await tester.pumpWidget(_host(playback, key: navigator));

    unawaited(NowPlayingScreen.open(navigator.currentContext!, title: 'Track A'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingScreen), findsNothing);
    expect(NowPlayingScreen.isOpen, isFalse);

    unawaited(NowPlayingScreen.open(navigator.currentContext!, title: 'Track A'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  });
}
