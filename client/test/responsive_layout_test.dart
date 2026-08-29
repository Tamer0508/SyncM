
import 'package:syncm/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/home_nav.dart';
import 'package:syncm/widgets/now_playing_panel.dart';

const List<Size> _windowSizes = [
  Size(1920, 1080),
  Size(1600, 900),
  Size(1440, 900),
  Size(1280, 800),
  Size(1200, 800),
  Size(1024, 768),
  Size(900, 700),
  Size(800, 600),
  Size(700, 600),
  Size(600, 600),
  Size(480, 800),
  Size(360, 640),
  Size(320, 568),
  Size(280, 500),
];

class _StubPlayback extends PlaybackProvider {
  @override
  Map<String, dynamic>? get currentTrack => {
        'uri': 'spotify:track:test',
        'title': 'Очень длинное название трека, которое некуда девать',
        'artist': 'Исполнитель с не менее длинным именем',
      };

  @override
  Uint8List? get currentImageBytes => null;

  @override
  int get durationMs => 210000;

  @override
  Future<PaletteGenerator?> paletteFor({
    String? imageUrl,
    Uint8List? imageBytes,
    String? fallbackKey,
  }) =>
      Future<PaletteGenerator?>.value(null);
}

Future<void> _withWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _asPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('AppLayout', () {
    test('раскладка меняется ступенями, а не одним переключателем', () {
      final wide = AppLayout.of(1440);
      expect(wide.showRail, isTrue);
      expect(wide.railLabels, isTrue);
      expect(wide.showNowPlayingPanel, isTrue);

      final medium = AppLayout.of(900);
      expect(medium.showRail, isTrue);
      expect(medium.railLabels, isTrue);
      expect(medium.showNowPlayingPanel, isFalse);

      final narrow = AppLayout.of(680);
      expect(narrow.showRail, isTrue);
      expect(narrow.railLabels, isFalse);

      final compact = AppLayout.of(560);
      expect(compact.showRail, isFalse);
    });

    test('между соседними размерами меняется не больше одного решения', () {
      var previous = AppLayout.of(400);

      for (var width = 401.0; width <= 1600; width += 1) {
        final current = AppLayout.of(width);
        final changes = [
          current.showRail != previous.showRail,
          current.railLabels != previous.railLabels,
          current.showNowPlayingPanel != previous.showNowPlayingPanel,
        ].where((changed) => changed).length;

        expect(changes, lessThanOrEqualTo(1),
            reason: 'на ширине $width раскладка перестроилась сразу дважды');
        previous = current;
      }
    });

    test('боковые панели не съедают окно', () {
      for (final size in _windowSizes) {
        final layout = AppLayout.of(size.width);
        if (!layout.showRail) continue;

        final railWidth = layout.railLabels ? layout.railMaxWidth : 72.0;
        final panelWidth =
            layout.showNowPlayingPanel ? layout.sidePanelWidth : 0.0;
        final left = size.width - railWidth - panelWidth - layout.gutter * 4;

        expect(left, greaterThan(280),
            reason: 'в окне ${size.width} содержимому осталось $left точек');
      }
    });

    test('в окне минимального размера навигация остаётся боковой', () {
      expect(AppLayout.minWindowSize.width,
          greaterThanOrEqualTo(AppLayout.railMinSpace));
      expect(AppLayout.of(AppLayout.minWindowSize.width).showRail, isTrue);
    });
  });

  group('AppLayoutScope', () {
    testWidgets('раздаёт раскладку вниз по дереву', (tester) async {
      await _withWindow(tester, const Size(1440, 900));

      late AppLayout seen;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: AppLayoutScope(
          child: Builder(builder: (context) {
            seen = context.layout;
            return const SizedBox.shrink();
          }),
        ),
      ));

      expect(seen.width, 1440);
      expect(seen.showNowPlayingPanel, isTrue);
    });

    testWidgets('на телефоне нижней границы окна нет', (tester) async {
      await _asPlatform(TargetPlatform.android, () async {
        await _withWindow(tester, const Size(360, 640));

        late AppLayout seen;
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: AppLayoutScope(
            child: Builder(builder: (context) {
              seen = context.layout;
              return const SizedBox.shrink();
            }),
          ),
        ));

        expect(seen.width, 360);
        expect(seen.showRail, isFalse);
        expect(find.byType(SingleChildScrollView), findsNothing);
      });
    });

    testWidgets('окно меньше минимума держит размер и даёт прокрутку',
        (tester) async {
      await _asPlatform(TargetPlatform.windows, () async {
        await _withWindow(tester, const Size(600, 130));

        late AppLayout seen;
        late Size seenMedia;
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: AppLayoutScope(
            child: Builder(builder: (context) {
              seen = context.layout;
              seenMedia = MediaQuery.sizeOf(context);
              return const SizedBox.shrink();
            }),
          ),
        ));

        expect(seen.width, AppLayout.minWindowSize.width);
        expect(seenMedia, AppLayout.minWindowSize);
        expect(find.byType(SingleChildScrollView), findsNWidgets(2));
        expect(seen.showRail, isTrue);
      });
    });

    testWidgets('в браузере на десктопе нижняя навигация не появляется',
        (tester) async {
      await _asPlatform(TargetPlatform.windows, () async {
        for (final size in const [
          Size(603, 652),
          Size(694, 1018),
          Size(400, 300),
          Size(120, 90),
        ]) {
          await _withWindow(tester, size);

          late AppLayout seen;
          await tester.pumpWidget(MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: AppLayoutScope(
              child: Builder(builder: (context) {
                seen = context.layout;
                return const SizedBox.shrink();
              }),
            ),
          ));

          expect(seen.showRail, isTrue,
              reason: 'окно $size сорвалось в нижнюю навигацию');
        }
      });
    });
  });

  group('Боковая навигация', () {
    Widget rail(AppLayout layout) => MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          theme: AppTheme.build(
            brightness: Brightness.dark,
            accent: AccentColor.values.first,
            compact: false,
            reduceMotion: true,
          ),
          home: Scaffold(
            body: Row(children: [
              HomeNavigationRail(
                currentIndex: 0,
                onSelected: (_) {},
                maxWidth: layout.railMaxWidth,
                showLabels: layout.railLabels,
                unreadFriendRequests: 12,
                onCreateSession: () {},
                onFindFriends: () {},
                onOpenLiked: () {},
                onOpenHistory: () {},
              ),
              const Expanded(child: SizedBox.shrink()),
            ]),
          ),
        );

    testWidgets('строится без переполнения на всех размерах', (tester) async {
      for (final size in _windowSizes) {
        final layout = AppLayout.of(size.width);
        if (!layout.showRail) continue;

        await _withWindow(tester, size);
        await tester.pumpWidget(rail(layout));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'панель сломалась в окне ${size.width}×${size.height}');
      }
    });

    testWidgets('в тесном окне остаются значки, а подписи уходят',
        (tester) async {
      await _withWindow(tester, const Size(700, 600));
      final layout = AppLayout.of(700);
      expect(layout.railLabels, isFalse);

      await tester.pumpWidget(rail(layout));
      await tester.pump();

      expect(find.byIcon(Icons.radio_rounded), findsOneWidget);
      expect(find.text('Музыка'), findsNothing);
      expect(find.byType(Tooltip), findsWidgets);

      final railBox = tester.getSize(
        find.descendant(
          of: find.byType(HomeNavigationRail),
          matching: find.byType(Container),
        ).first,
      );
      expect(railBox.width, 72);
    });

    testWidgets('в низком окне прокручивается, а не вылезает', (tester) async {
      await _withWindow(tester, const Size(1770, 420));
      await tester.pumpWidget(rail(AppLayout.of(1770)));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final scroller = find.descendant(
        of: find.byType(HomeNavigationRail),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroller, findsOneWidget);

      final content = tester.getSize(
        find.descendant(of: scroller, matching: find.byType(Column)).first,
      );
      expect(content.height, greaterThan(420));
    });

    testWidgets('занимает всю высоту, а не высоту своего списка',
        (tester) async {
      await _withWindow(tester, const Size(1440, 900));
      await tester.pumpWidget(rail(AppLayout.of(1440)));
      await tester.pump();

      final panel = tester.getSize(
        find.descendant(
          of: find.byType(HomeNavigationRail),
          matching: find.byType(Container),
        ).first,
      );
      expect(panel.height, 900);
    });

    testWidgets('не шире того, что позволяет окно', (tester) async {
      await _withWindow(tester, const Size(800, 600));
      final layout = AppLayout.of(800);

      await tester.pumpWidget(rail(layout));
      await tester.pump();

      expect(layout.railMaxWidth, lessThanOrEqualTo(800 * 0.28));
    });
  });

  group('Панель «сейчас играет»', () {
    Widget panel(double width, double height) => MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          theme: AppTheme.build(
            brightness: Brightness.dark,
            accent: AccentColor.values.first,
            compact: false,
            reduceMotion: true,
          ),
          home: ChangeNotifierProvider<PlaybackProvider>(
            create: (_) => _StubPlayback(),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: const Column(children: [
                    Expanded(child: NowPlayingPanelCompact()),
                  ]),
                ),
              ),
            ),
          ),
        );

    testWidgets('не переполняется на всей своей ширине', (tester) async {
      for (final size in _windowSizes) {
        final layout = AppLayout.of(size.width);
        if (!layout.showNowPlayingPanel) continue;

        await _withWindow(tester, size);
        await tester.pumpWidget(
          panel(layout.sidePanelWidth, size.height - layout.gutter * 2),
        );
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'панель сломалась в окне ${size.width}×${size.height}');
      }
    });

    testWidgets('обложка тянется вместе с панелью', (tester) async {
      await _withWindow(tester, const Size(1920, 1080));
      await tester.pumpWidget(panel(360, 900));
      await tester.pump();

      final wide = tester
          .getSize(find.byIcon(Icons.music_note_rounded).hitTestable())
          .width;

      await _withWindow(tester, const Size(1100, 800));
      await tester.pumpWidget(panel(280, 700));
      await tester.pump();

      final narrow = tester
          .getSize(find.byIcon(Icons.music_note_rounded).hitTestable())
          .width;

      expect(narrow, lessThan(wide));
    });

    testWidgets('в низком окне прокручивается, а не вылезает', (tester) async {
      await _withWindow(tester, const Size(1200, 300));
      await tester.pumpWidget(panel(300, 240));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(NowPlayingPanelCompact),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });
  });
}
