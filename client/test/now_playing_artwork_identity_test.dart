import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/appearance_provider.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/screens/player/artwork_pager.dart';
import 'package:syncm/screens/player/now_playing.dart';

String? centeredTrackId(WidgetTester tester) {
  final tiles = tester.widgetList<FractionalTranslation>(
    find.descendant(
      of: find.byType(ArtworkPager),
      matching: find.byType(FractionalTranslation),
    ),
  );

  for (final tile in tiles) {
    if (tile.translation.dx.abs() > 0.001) continue;
    final key = tile.key;
    if (key is ValueKey<String>) return key.value;
  }
  return null;
}

ArtworkSlot _slot(String trackId) => ArtworkSlot(
      trackId: trackId,
      source: ArtworkSource(url: 'https://example.com/$trackId.png'),
    );

Map<String, dynamic> _track(String id) => {
      'uri': 'spotify:track:$id',
      'title': 'Track $id',
      'artist': 'Artist',
      'imageUrl': 'https://example.com/$id.png',
      'durationMs': 200000,
    };

class _SlowPlayback extends PlaybackProvider {
  _SlowPlayback(this._current, this._next, this._previous);

  Map<String, dynamic>? _current;
  Map<String, dynamic>? _next;
  Map<String, dynamic>? _previous;

  bool _switching = false;
  int nextCalls = 0;

  @override
  Map<String, dynamic>? get currentTrack => _current;

  @override
  Map<String, dynamic>? get nextQueueTrack => _next;

  @override
  Map<String, dynamic>? get previousQueueTrack => _previous;

  @override
  bool get isSwitchingTrack => _switching;

  @override
  int get durationMs => 200000;

  @override
  bool get isPlaying => true;

  @override
  Uint8List? get currentImageBytes => null;

  @override
  List<String> get neighbourArtworkUrls => const [];

  @override
  void ensureArtworkColor() {}

  @override
  Future<PaletteGenerator?> paletteFor({
    String? imageUrl,
    Uint8List? imageBytes,
    String? fallbackKey,
  }) =>
      Future<PaletteGenerator?>.value(null);

  @override
  Future<void> goToNext() async {
    nextCalls++;
    _switching = true;
    notifyListeners();
  }

  @override
  Future<void> goToPrevious() async {
    _switching = true;
    notifyListeners();
  }

  void confirm({
    required String current,
    String? next,
    String? previous,
  }) {
    _current = _track(current);
    _next = next == null ? null : _track(next);
    _previous = previous == null ? null : _track(previous);
    _switching = false;
    notifyListeners();
  }
}

Widget _pagerHost({
  required GlobalKey<ArtworkPagerState> key,
  required ValueNotifier<double> progress,
  required String current,
  required bool Function() onNext,
  ArtworkSlot? next,
  ArtworkSlot? previous,
  bool switching = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: ArtworkPager(
            key: key,
            size: 300,
            current: _slot(current),
            previous: previous,
            next: next,
            switching: switching,
            progress: progress,
            onNext: onNext,
            onPrevious: () => true,
          ),
        ),
      ),
    ),
  );
}

Future<void> swipeArtwork(WidgetTester tester, {required int direction}) async {
  final gesture =
      await tester.startGesture(tester.getCenter(find.byType(ArtworkPager)));

  for (var step = 0; step < 10; step++) {
    await gesture.moveBy(Offset(-28.0 * direction, 0));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pump();
}

Widget _screenHost(PlaybackProvider playback) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
      ChangeNotifierProvider<AppearanceProvider>(
        create: (_) => AppearanceProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: const NowPlayingScreen(),
    ),
  );
}

void main() {
  group('обложка привязана к треку', () {
    testWidgets(
        'A-001: после свайпа обложка прежнего трека не возвращается в центр',
        (tester) async {
      final key = GlobalKey<ArtworkPagerState>();
      final progress = ValueNotifier<double>(0);

      Widget host({required String current, required bool switching}) =>
          _pagerHost(
            key: key,
            progress: progress,
            current: current,
            switching: switching,
            previous: _slot('z'),
            next: current == 'a' ? _slot('b') : _slot('c'),
            onNext: () => true,
          );

      await tester.pumpWidget(host(current: 'a', switching: false));
      expect(centeredTrackId(tester), 'artwork.track.a');

      expect(key.currentState!.animateTo(1), isTrue);
      await tester.pumpAndSettle();

      expect(centeredTrackId(tester), 'artwork.track.b');

      for (var frame = 0; frame < 40; frame++) {
        await tester.pumpWidget(host(current: 'a', switching: true));
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          centeredTrackId(tester),
          'artwork.track.b',
          reason: 'на кадре $frame в центре оказалась чужая обложка '
              '${centeredTrackId(tester)}',
        );
      }

      await tester.pumpWidget(host(current: 'b', switching: false));
      await tester.pumpAndSettle();

      expect(centeredTrackId(tester), 'artwork.track.b');
      expect(progress.value, 0);

      progress.dispose();
    });

    testWidgets('A-002: отклонённая команда оставляет в центре текущий трек',
        (tester) async {
      final key = GlobalKey<ArtworkPagerState>();
      final progress = ValueNotifier<double>(0);
      var calls = 0;

      await tester.pumpWidget(_pagerHost(
        key: key,
        progress: progress,
        current: 'a',
        next: _slot('b'),
        onNext: () {
          calls++;
          return false;
        },
      ));

      expect(key.currentState!.animateTo(1), isTrue);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(centeredTrackId(tester), 'artwork.track.a');
      expect(progress.value, 0);

      progress.dispose();
    });

    testWidgets('A-003: элемент плитки переживает подтверждение трека',
        (tester) async {
      final key = GlobalKey<ArtworkPagerState>();
      final progress = ValueNotifier<double>(0);

      await tester.pumpWidget(_pagerHost(
        key: key,
        progress: progress,
        current: 'a',
        previous: _slot('z'),
        next: _slot('b'),
        onNext: () => true,
      ));

      Element elementFor(String trackId) => tester.element(
            find.byKey(ValueKey<String>('artwork.track.$trackId')),
          );

      final before = elementFor('b');

      expect(key.currentState!.animateTo(1), isTrue);
      await tester.pumpAndSettle();

      await tester.pumpWidget(_pagerHost(
        key: key,
        progress: progress,
        current: 'b',
        previous: _slot('a'),
        next: _slot('c'),
        onNext: () => true,
      ));
      await tester.pumpAndSettle();

      expect(identical(elementFor('b'), before), isTrue);

      progress.dispose();
    });

    testWidgets('A-004: медленный провайдер не показывает чужую обложку',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pb = _SlowPlayback(_track('a'), _track('b'), null);
      addTearDown(pb.dispose);

      await tester.pumpWidget(_screenHost(pb));
      await tester.pumpAndSettle();

      expect(centeredTrackId(tester), 'artwork.track.spotify:track:a');

      await swipeArtwork(tester, direction: 1);
      await tester.pumpAndSettle();

      expect(pb.nextCalls, 1);

      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(centeredTrackId(tester), 'artwork.track.spotify:track:b');
      }

      pb.confirm(current: 'b', next: 'c', previous: 'a');
      await tester.pumpAndSettle();

      expect(centeredTrackId(tester), 'artwork.track.spotify:track:b');
      expect(pb.currentTrack!['uri'], 'spotify:track:b');
    });

    testWidgets('A-005: подряд A -> B -> C обложка идёт за треком',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pb = _SlowPlayback(_track('a'), _track('b'), null);
      addTearDown(pb.dispose);

      await tester.pumpWidget(_screenHost(pb));
      await tester.pumpAndSettle();

      for (final step in const [('b', 'c', 'a'), ('c', 'd', 'b')]) {
        await swipeArtwork(tester, direction: 1);
        await tester.pumpAndSettle();

        expect(centeredTrackId(tester), 'artwork.track.spotify:track:${step.$1}');

        pb.confirm(current: step.$1, next: step.$2, previous: step.$3);
        await tester.pumpAndSettle();

        expect(centeredTrackId(tester), 'artwork.track.spotify:track:${step.$1}');
        expect(pb.currentTrack!['uri'], 'spotify:track:${step.$1}');
      }
    });

    testWidgets('A-006: быстрые свайпы не отправляют команду в пустоту',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pb = _SlowPlayback(_track('a'), _track('b'), null);
      addTearDown(pb.dispose);

      await tester.pumpWidget(_screenHost(pb));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        await swipeArtwork(tester, direction: 1);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(pb.nextCalls, 1);
      expect(centeredTrackId(tester), 'artwork.track.spotify:track:b');

      pb.confirm(current: 'b', next: 'c', previous: 'a');
      await tester.pumpAndSettle();

      expect(centeredTrackId(tester), 'artwork.track.spotify:track:b');
    });
  });
}
