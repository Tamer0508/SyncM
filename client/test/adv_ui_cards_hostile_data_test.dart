// Adversarial-тесты карточек на враждебных данных и узких экранах.
//
// Раздел 17 (responsive) и раздел 18 (edge cases) ТЗ: длинные названия,
// emoji, RTL, отсутствующая обложка, нулевая длительность.
//
// Атакуемый код: client/lib/widgets/track_card.dart
//                client/lib/widgets/playlist_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/playlist_card.dart';
import 'package:syncm/widgets/track_card.dart';

/// Ширины окна от самого узкого телефона до десктопа.
const List<double> _widths = [280, 320, 360, 480, 768, 1280, 1920];

/// Данные, которые реальный каталог отдаёт регулярно.
const Map<String, String> _hostileTitles = {
  'длинное название':
      'Symphony No. 9 in D minor, Op. 125 «Choral» — IV. Presto — Allegro assai '
          '(Remastered 2024 Deluxe Anniversary Edition, Live at the Royal Albert Hall)',
  'без пробелов':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'emoji': '🎵🎶🎸🥁🎹🎤🎧🎼🎺🎻🪕🪗🎷📀💿🔊🔥✨💫⭐🌟💥🎊🎉🥳',
  'RTL': 'أغنية عربية طويلة جدا مع نص إضافي هنا',
  'пусто': '',
};

/// Карточка трека читает у провайдера только текущий трек — сеть не нужна.
class _StubPlayback extends PlaybackProvider {
  @override
  Map<String, dynamic>? get currentTrack => null;

  @override
  bool get isPlaying => false;
}

Widget _host({required Widget child, required double width}) {
  return ChangeNotifierProvider<PlaybackProvider>(
    create: (_) => _StubPlayback(),
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Возвращает исключение отрисовки, если оно было.
Future<Object?> _renderError(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 350));
  return tester.takeException();
}

void main() {
  group('TrackCard на враждебных данных', () {
    for (final entry in _hostileTitles.entries) {
      for (final width in _widths) {
        testWidgets('${entry.key} @ ${width.toInt()}px', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final error = await _renderError(
            tester,
            _host(
              width: width,
              child: TrackCard(
                id: 'track-1',
                title: entry.value,
                artist: entry.value,
                artworkUrl: null, // обложки нет — обычное дело для локальных треков
                durationMs: null, // длительность неизвестна
                showMore: true,
              ),
            ),
          );

          expect(
            error,
            isNull,
            reason: 'карточка трека («${entry.key}») сломалась на ширине ${width.toInt()}px',
          );
        });
      }
    }
  });

  group('PlaylistCard на враждебных данных', () {
    for (final entry in _hostileTitles.entries) {
      for (final width in _widths) {
        testWidgets('${entry.key} @ ${width.toInt()}px', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final error = await _renderError(
            tester,
            _host(
              width: width,
              child: PlaylistCard(
                name: entry.value,
                description: entry.value,
                imageUrl: null,
                width: width,
              ),
            ),
          );

          expect(
            error,
            isNull,
            reason: 'карточка плейлиста («${entry.key}») сломалась на ширине ${width.toInt()}px',
          );
        });
      }
    }
  });

  testWidgets('TrackCard с нулевой длительностью не считает прогресс через ноль',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final error = await _renderError(
      tester,
      _host(
        width: 360,
        child: const TrackCard(
          id: 'track-zero',
          title: 'Трек нулевой длины',
          artist: 'Исполнитель',
          durationMs: 0,
          isActive: true,
        ),
      ),
    );

    expect(error, isNull, reason: 'durationMs: 0 роняет отрисовку карточки');
  });
}
