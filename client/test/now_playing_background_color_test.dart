import 'dart:async';
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

const orange = Color(0xFFE8730C);
const gray = Color(0xFF8A8A8A);
const blue = Color(0xFF1E5AE8);

PaletteGenerator _palette(Color color) =>
    PaletteGenerator.fromColors(<PaletteColor>[PaletteColor(color, 100)]);

Map<String, dynamic> _track(String id) => {
      'uri': 'spotify:track:$id',
      'title': 'Track $id',
      'artist': 'Artist',
      'imageUrl': 'https://example.com/$id.png',
      'durationMs': 200000,
    };

Color backgroundColor(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) continue;

    final gradient = decoration.gradient;
    if (gradient is LinearGradient && gradient.colors.length == 3) {
      return gradient.colors.first;
    }
  }
  fail('градиент фона Now Playing не найден');
}

Future<List<Color>> sampleBackground(
  WidgetTester tester, {
  int frames = 60,
}) async {
  final samples = <Color>[backgroundColor(tester)];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    samples.add(backgroundColor(tester));
  }
  return samples;
}

double? _progressAlong(Color from, Color to, Color sample) {
  double? found;

  for (final channel in <List<double>>[
    [from.r, to.r, sample.r],
    [from.g, to.g, sample.g],
    [from.b, to.b, sample.b],
  ]) {
    final span = channel[1] - channel[0];
    if (span.abs() < 0.02) {
      if ((channel[2] - channel[0]).abs() > 0.04) return null;
      continue;
    }

    final t = (channel[2] - channel[0]) / span;
    if (t < -0.02 || t > 1.02) return null;
    if (found != null && (found - t).abs() > 0.04) return null;
    found ??= t;
  }

  return found ?? 0;
}

void expectSmoothTransition(
  List<Color> samples, {
  required Color from,
  required Color to,
}) {
  var previous = 0.0;

  for (var i = 0; i < samples.length; i++) {
    final t = _progressAlong(from, to, samples[i]);

    expect(
      t,
      isNotNull,
      reason: 'кадр $i: фон ${samples[i]} не лежит на переходе $from -> $to',
    );

    expect(
      t!,
      greaterThanOrEqualTo(previous - 0.02),
      reason: 'кадр $i: фон откатился назад по переходу '
          '($previous -> $t) — это и есть вспышка',
    );
    previous = t > previous ? t : previous;
  }

  expect(previous, greaterThan(0.95), reason: 'переход не дошёл до конца');
}

void expectNeverReturnsTo(List<Color> samples, Color color) {
  var left = false;

  for (var i = 0; i < samples.length; i++) {
    if (!left) {
      if (samples[i] != color) left = true;
      continue;
    }
    expect(samples[i], isNot(color),
        reason: 'кадр $i: прежний цвет фона появился второй раз');
  }
}

class _ColorPlayback extends PlaybackProvider {
  _ColorPlayback(this._current);

  Map<String, dynamic>? _current;

  final Map<String, PaletteGenerator> _palettes = {};

  final Map<String, Completer<PaletteGenerator?>> pending = {};

  @override
  Map<String, dynamic>? get currentTrack => _current;

  String? next;

  void queueNext(String id) {
    next = id;
    notifyListeners();
  }

  bool _switching = false;

  @override
  Map<String, dynamic>? get nextQueueTrack =>
      next == null ? null : _track(next!);

  @override
  Map<String, dynamic>? get previousQueueTrack => null;

  @override
  bool get isSwitchingTrack => _switching;

  @override
  Future<void> goToNext() async {
    _switching = true;
    notifyListeners();
  }

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
  Map<String, PaletteGenerator> get paletteCache => _palettes;

  @override
  Color? dominantColorForUrl(String? url) =>
      _palettes[url]?.dominantColor?.color;

  @override
  Future<PaletteGenerator?> paletteFor({
    String? imageUrl,
    Uint8List? imageBytes,
    String? fallbackKey,
  }) {
    final key = imageUrl ?? fallbackKey;
    if (key == null) return Future<PaletteGenerator?>.value(null);

    final ready = _palettes[key];
    if (ready != null) return Future<PaletteGenerator?>.value(ready);

    return pending
        .putIfAbsent(key, Completer<PaletteGenerator?>.new)
        .future;
  }

  void knowColor(String id, Color color) {
    _palettes['https://example.com/$id.png'] = _palette(color);
  }

  void resolveColor(String id, Color color) {
    final key = 'https://example.com/$id.png';
    final palette = _palette(color);
    _palettes[key] = palette;
    pending.remove(key)?.complete(palette);
  }

  void switchTo(String id) {
    _current = _track(id);
    _switching = false;
    notifyListeners();
  }
}

Future<void> swipeArtwork(WidgetTester tester) async {
  final gesture =
      await tester.startGesture(tester.getCenter(find.byType(ArtworkPager)));

  for (var step = 0; step < 10; step++) {
    await gesture.moveBy(const Offset(-28, 0));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pump();
}

Widget _host(PlaybackProvider playback) {
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

Future<_ColorPlayback> _openOn(WidgetTester tester, String id, Color color) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final pb = _ColorPlayback(_track(id))..knowColor(id, color);
  addTearDown(pb.dispose);

  await tester.pumpWidget(_host(pb));
  await tester.pumpAndSettle();

  return pb;
}

void main() {
  group('фон не мигает прежним цветом', () {
    testWidgets('C-001: ORANGE -> GRAY идёт одним переходом', (tester) async {
      final pb = await _openOn(tester, 'a', orange);
      pb.knowColor('b', gray);

      final from = backgroundColor(tester);

      pb.switchTo('b');
      final samples = await sampleBackground(tester);

      expectSmoothTransition(samples, from: from, to: samples.last);
      expect(samples.last, isNot(from));
    });

    testWidgets('C-002: медленный расчёт не подставляет заглушку',
        (tester) async {
      final pb = await _openOn(tester, 'a', orange);

      final from = backgroundColor(tester);

      pb.switchTo('b');
      final waiting = await sampleBackground(tester, frames: 30);

      for (var i = 0; i < waiting.length; i++) {
        expect(waiting[i], from, reason: 'кадр $i: фон дёрнулся до расчёта');
      }

      pb.resolveColor('b', gray);
      await tester.pump();
      final moving = await sampleBackground(tester);

      expectSmoothTransition(moving, from: from, to: moving.last);
      expect(moving.last, isNot(from));
    });

    testWidgets('C-003: опоздавший расчёт не возвращает цвет чужого трека',
        (tester) async {
      final pb = await _openOn(tester, 'a', orange);

      final from = backgroundColor(tester);

      pb.switchTo('b');
      await tester.pump(const Duration(milliseconds: 32));

      pb.knowColor('c', blue);
      pb.switchTo('c');
      await tester.pumpAndSettle();

      final settled = backgroundColor(tester);
      expect(settled, isNot(from));

      pb.resolveColor('b', gray);
      final samples = await sampleBackground(tester);

      for (var i = 0; i < samples.length; i++) {
        expect(samples[i], settled,
            reason: 'кадр $i: фон перекрасился под уже неактуальный трек');
      }
    });

    testWidgets('C-004: одинаковый цвет не запускает анимацию', (tester) async {
      final pb = await _openOn(tester, 'a', gray);
      pb.knowColor('b', gray);

      final before = backgroundColor(tester);

      pb.switchTo('b');
      final samples = await sampleBackground(tester, frames: 40);

      for (var i = 0; i < samples.length; i++) {
        expect(samples[i], before,
            reason: 'кадр $i: фон дёрнулся при одинаковом цвете');
      }
    });

    testWidgets('C-005: быстрые смены A -> B -> C -> D', (tester) async {
      final pb = await _openOn(tester, 'a', orange);
      pb
        ..knowColor('b', gray)
        ..knowColor('c', blue)
        ..knowColor('d', const Color(0xFFC81E1E));

      final start = backgroundColor(tester);
      final samples = <Color>[start];

      for (final id in const ['b', 'c', 'd']) {
        pb.switchTo(id);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(backgroundColor(tester));
        }
      }

      await tester.pumpAndSettle();
      samples.add(backgroundColor(tester));

      expectNeverReturnsTo(samples, start);
      expect(samples.last, isNot(start));
    });

    testWidgets('C-006: цвет из кэша ставится без промежуточных кадров',
        (tester) async {
      final pb = await _openOn(tester, 'a', orange);
      pb.knowColor('b', gray);

      final from = backgroundColor(tester);

      pb.switchTo('b');

      await tester.pump();
      expect(_progressAlong(from, gray, backgroundColor(tester)), isNotNull,
          reason: 'первый кадр после смены трека вне перехода');

      await tester.pumpAndSettle();
      expect(backgroundColor(tester), isNot(from));
    });

    testWidgets('C-007: свайп на трек с несчитанным цветом не мигает',
        (tester) async {
      final pb = await _openOn(tester, 'a', orange);
      pb.queueNext('b');
      await tester.pumpAndSettle();

      final from = backgroundColor(tester);

      await swipeArtwork(tester);
      await tester.pumpAndSettle();

      final duringSwipe = await sampleBackground(tester, frames: 20);

      pb.switchTo('b');
      final afterCommit = await sampleBackground(tester, frames: 20);

      for (final sample in [...duringSwipe, ...afterCommit]) {
        expect(sample, from, reason: 'фон дёрнулся до расчёта цвета соседа');
      }

      pb.resolveColor('b', gray);
      await tester.pump();
      final moving = await sampleBackground(tester);

      expectSmoothTransition(moving, from: from, to: moving.last);
      expect(moving.last, isNot(from));
    });

    testWidgets('C-008: свайп с известным цветом соседа сохраняет переход',
        (tester) async {
      final pb = await _openOn(tester, 'a', orange);
      pb
        ..knowColor('b', blue)
        ..queueNext('b');
      await tester.pumpAndSettle();

      final from = backgroundColor(tester);

      await swipeArtwork(tester);
      await tester.pumpAndSettle();

      final committed = backgroundColor(tester);
      expect(committed, isNot(from));

      pb.switchTo('b');
      final samples = await sampleBackground(tester, frames: 30);

      for (var i = 0; i < samples.length; i++) {
        expect(samples[i], committed,
            reason: 'кадр $i: подтверждение трека перекрасило фон заново');
      }
      expectNeverReturnsTo([from, ...samples], from);
    });
  });
}
