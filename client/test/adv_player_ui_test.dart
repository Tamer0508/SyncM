import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/appearance_provider.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/screens/player/artwork_pager.dart';
import 'package:syncm/screens/player/now_playing.dart';
import 'package:syncm/widgets/mini_player.dart';

class _StubPlayback extends PlaybackProvider {
  _StubPlayback({
    Map<String, dynamic>? track,
    int duration = 200000,
  })  : _track = track,
        _duration = duration;

  Map<String, dynamic>? _track;
  final int _duration;

  int nextCalls = 0;
  int previousCalls = 0;

  @override
  Map<String, dynamic>? get currentTrack => _track;

  @override
  int get durationMs => _duration;

  @override
  bool get isPlaying => true;

  @override
  Uint8List? get currentImageBytes => null;

  @override
  Map<String, dynamic>? get nextQueueTrack => null;

  @override
  Map<String, dynamic>? get previousQueueTrack => null;

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
  }

  @override
  Future<void> goToPrevious() async {
    previousCalls++;
  }

  void setTrack(Map<String, dynamic>? track) {
    _track = track;
    notifyListeners();
  }
}

Widget _host(PlaybackProvider pb, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackProvider>.value(value: pb),
      ChangeNotifierProvider<AppearanceProvider>(
        create: (_) => AppearanceProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: child,
    ),
  );
}

Future<void> _sized(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('мусорные данные трека', () {
    testWidgets('P-010: durationMs = 0 и позиция вне трека не ломают полосу',
        (tester) async {
      await _sized(tester, const Size(390, 844));

      final pb = _StubPlayback(
        track: {
          'uri': 'spotify:track:x',
          'title': 'Track',
          'artist': 'Artist',
        },
        duration: 0,
      );
      pb.positionNotifier.value = 987654321;

      await tester.pumpWidget(_host(pb, const Scaffold(body: MiniPlayer())));
      await tester.pump();

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      final value = bar.value;
      expect(value, isNotNull);
      expect(value!.isFinite, isTrue, reason: 'NaN/Infinity в прогресс-баре');
      expect(value, inInclusiveRange(0.0, 1.0));

      pb.dispose();
    });

    testWidgets('P-011: трек без title/artist показывает заглушку',
        (tester) async {
      await _sized(tester, const Size(390, 844));

      final pb = _StubPlayback(track: {'uri': 'spotify:track:x'});

      await tester.pumpWidget(_host(pb, const Scaffold(body: MiniPlayer())));
      await tester.pump();

      expect(tester.takeException(), isNull);
      pb.dispose();
    });

    testWidgets('P-012: очень длинное название/emoji/RTL не рвут мини-плеер',
        (tester) async {
      await _sized(tester, const Size(320, 568));

      final pb = _StubPlayback(
        track: {
          'uri': 'spotify:track:x',
          'title': '🎧 ${'Очень длинное название трека ' * 8} مرحبا بالعالم 🎶',
          'artist': '${'Исполнитель ' * 10} العربية',
        },
      );

      await tester.pumpWidget(_host(pb, const Scaffold(body: MiniPlayer())));
      await tester.pump();

      expect(tester.takeException(), isNull);
      pb.dispose();
    });

    testWidgets('P-013: экран трека переживает durationMs = 0', (tester) async {
      await _sized(tester, const Size(390, 844));

      final pb = _StubPlayback(
        track: {
          'uri': 'spotify:track:x',
          'title': 'Track',
          'artist': 'Artist',
        },
        duration: 0,
      );
      pb.positionNotifier.value = -5000;

      await tester.pumpWidget(_host(pb, const NowPlayingScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value.isFinite, isTrue);
      expect(slider.value, greaterThanOrEqualTo(slider.min));
      expect(slider.value, lessThanOrEqualTo(slider.max));

      pb.dispose();
    });
  });

  group('адаптивность', () {
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(1440, 900),
      Size(2560, 1440),
      Size(844, 390),
    ]) {
      testWidgets('P-014: экран трека без переполнений на ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        await _sized(tester, size);

        final pb = _StubPlayback(
          track: {
            'uri': 'spotify:track:x',
            'title': 'Довольно длинное название трека для проверки',
            'artist': 'Исполнитель',
          },
        );

        await tester.pumpWidget(_host(pb, const NowPlayingScreen()));
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull,
            reason: 'экран трека сломался на $size');

        pb.dispose();
      });

      testWidgets('P-015: мини-плеер без переполнений на ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        await _sized(tester, size);

        final pb = _StubPlayback(
          track: {
            'uri': 'spotify:track:x',
            'title': 'Довольно длинное название трека для проверки',
            'artist': 'Исполнитель',
          },
        );

        await tester.pumpWidget(_host(pb, const Scaffold(body: MiniPlayer())));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'мини-плеер сломался на $size');

        pb.dispose();
      });
    }
  });

  group('artwork pager', () {
    ArtworkSlot slot(String trackId, [String? url]) =>
        ArtworkSlot(trackId: trackId, source: ArtworkSource(url: url));

    Widget pagerHost({
      required GlobalKey<ArtworkPagerState> key,
      required ValueNotifier<double> progress,
      required bool Function() onNext,
      required bool Function() onPrevious,
      ArtworkSlot? next,
      ArtworkSlot? previous,
      String currentKey = 'a',
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
                current: slot(currentKey),
                previous: previous,
                next: next,
                switching: switching,
                progress: progress,
                onNext: onNext,
                onPrevious: onPrevious,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('P-016: свайп вправо при отсутствии предыдущего трека молчит',
        (tester) async {
      final key = GlobalKey<ArtworkPagerState>();
      final progress = ValueNotifier<double>(0);
      var next = 0;
      var previous = 0;

      await tester.pumpWidget(pagerHost(
        key: key,
        progress: progress,
        onNext: () {
          next++;
          return true;
        },
        onPrevious: () {
          previous++;
          return true;
        },
        next: slot('b', 'https://example.com/n.png'),
      ));

      await tester.drag(find.byType(ArtworkPager), const Offset(280, 0));
      await tester.pumpAndSettle();

      expect(previous, 0);
      expect(next, 0);
      expect(progress.value, 0);
      progress.dispose();
    });

    testWidgets('P-017: пейджер не остаётся сдвинутым, если трек не сменился',
        (tester) async {
      final key = GlobalKey<ArtworkPagerState>();
      final progress = ValueNotifier<double>(0);
      var next = 0;

      Widget host({required bool switching}) => pagerHost(
            key: key,
            progress: progress,
            switching: switching,
            onNext: () {
              next++;
              return true;
            },
            onPrevious: () => true,
            next: slot('b', 'https://example.com/n.png'),
          );

      await tester.pumpWidget(host(switching: false));

      expect(key.currentState!.animateTo(1), isTrue);
      await tester.pumpAndSettle();

      expect(next, 1);

      await tester.pumpWidget(host(switching: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(switching: false));
      await tester.pumpAndSettle();

      expect(
        progress.value,
        0,
        reason: 'трек не сменился, а обложка так и уехала за экран: '
            'смещение ${progress.value}',
      );

      progress.dispose();
    });

    testWidgets('P-018: десять быстрых Next не копят вызовы очереди',
        (tester) async {
      final key = GlobalKey<ArtworkPagerState>();
      final progress = ValueNotifier<double>(0);
      var next = 0;

      await tester.pumpWidget(pagerHost(
        key: key,
        progress: progress,
        onNext: () {
          next++;
          return true;
        },
        onPrevious: () => true,
        next: slot('b', 'https://example.com/n.png'),
      ));

      for (var i = 0; i < 10; i++) {
        key.currentState!.animateTo(1);
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.pumpAndSettle();

      expect(next, lessThanOrEqualTo(1),
          reason: 'один жест — один переход, накопилось $next');
      progress.dispose();
    });
  });

  group('жизненный цикл', () {
    testWidgets('P-019: закрытие экрана трека посреди анимации цвета',
        (tester) async {
      await _sized(tester, const Size(390, 844));

      final pb = _StubPlayback(
        track: {
          'uri': 'spotify:track:x',
          'title': 'Track',
          'artist': 'Artist',
        },
      );

      await tester.pumpWidget(_host(pb, const NowPlayingScreen()));
      await tester.pump(const Duration(milliseconds: 60));

      await tester.pumpWidget(_host(pb, const Scaffold(body: SizedBox())));
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      pb.dispose();
    });

    testWidgets('P-020: трек исчез посреди кадра — мини-плеер не падает',
        (tester) async {
      await _sized(tester, const Size(390, 844));

      final pb = _StubPlayback(
        track: {
          'uri': 'spotify:track:x',
          'title': 'Track',
          'artist': 'Artist',
        },
      );

      await tester.pumpWidget(_host(pb, const Scaffold(body: MiniPlayer())));
      await tester.pump();

      pb.setTrack(null);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pb.dispose();
    });
  });
}
