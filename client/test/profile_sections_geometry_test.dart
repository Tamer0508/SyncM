import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/screens/profile/music_summary.dart';
import 'package:syncm/screens/profile/profile_sections.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/skeleton.dart';

/// Новые разделы профиля и их заглушки обязаны занимать одну и ту же
/// коробку: списки треков идут следом, и любое расхождение сдвигает их
/// в момент, когда данные доедут.
///
/// Сравнивается содержимое разделов, а не их полная высота: под тестовым
/// шрифтом (Onest здесь не загружается) заголовки переносятся не так, как
/// в приложении, и высота шапки к делу не относится — её задаёт один и тот
/// же `ProfileSectionHeader` и там, и там.
Widget _wrap(Widget child, {double scale = 1.0}) => MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('ru'),
      theme: AppTheme.build(
        brightness: Brightness.light,
        accent: AccentColor.values.first,
        compact: false,
        reduceMotion: true,
      ),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          // Высота не ограничена — как у sliver'а в профиле.
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  for (final size in const [Size(360, 800), Size(900, 900)]) {
    final label = size.width.toInt();

    testWidgets('«Чаще всего звучит»: полоса заглушки той же высоты · $label',
        (tester) async {
      _screen(tester, size);

      final artists = [
        for (var i = 0; i < 5; i++)
          ArtistTally(name: 'Исполнитель $i', trackCount: 5 - i),
      ];

      await tester.pumpWidget(_wrap(ProfileArtistsSection(artists: artists)));
      await tester.pump();

      // Карусель — это то, что заглушка обязана повторить: её высоту
      // задаёт содержимое, а не число в коде.
      final realStrip = tester.getSize(find.byType(SingleChildScrollView).last);
      final realAvatar = tester.getSize(find.byType(ClipOval).first);

      await tester.pumpWidget(_wrap(const SkeletonProfileArtists()));
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(tester.getSize(find.byType(SingleChildScrollView).last), realStrip);
      expect(
        tester.getSize(find.byWidgetPredicate(
          (w) => w is SkeletonBox && w.circle,
        ).first),
        realAvatar,
      );
    });
  }

  testWidgets('«Общая музыка» остаётся на месте и без совпадений',
      (tester) async {
    _screen(tester, const Size(360, 800));

    await tester.pumpWidget(_wrap(
      const ProfileSharedMusicSection(shared: SharedMusic.none),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final element = tester.element(find.byType(ProfileSharedMusicSection));
    expect(find.text(L.of(element).profileInCommonEmpty), findsOneWidget);
  });

  testWidgets('«Общая музыка» показывает исполнителей и число общих треков',
      (tester) async {
    _screen(tester, const Size(360, 800));

    await tester.pumpWidget(_wrap(
      ProfileSharedMusicSection(
        shared: SharedMusic(
          artists: const ['Кино', 'Аквариум'],
          tracks: [
            {'spotifyUri': 'a', 'trackName': 'т', 'artistName': 'Кино'},
          ],
        ),
      ),
    ));
    await tester.pump();

    final element = tester.element(find.byType(ProfileSharedMusicSection));
    expect(find.text('Кино'), findsOneWidget);
    expect(find.text('Аквариум'), findsOneWidget);
    expect(find.text(L.of(element).profileInCommonTracks(1)), findsOneWidget);
  });

  group('разделы профиля раскладываются без ошибок', () {
    final cases = <String, Widget>{
      'исполнители': ProfileArtistsSection(
        artists: [
          for (var i = 0; i < 12; i++)
            ArtistTally(name: 'Очень длинное имя исполнителя $i', trackCount: i),
        ],
      ),
      'исполнители: заглушка': const SkeletonProfileArtists(),
      'общая музыка': const ProfileSharedMusicSection(
        shared: SharedMusic(
          artists: ['Кино', 'Аквариум', 'Наутилус Помпилиус', 'ДДТ'],
          tracks: [],
        ),
      ),
      'общая музыка: заглушка': const SkeletonProfileSharedMusic(),
      'плейлисты': ProfilePlaylistsSection(
        playlists: const [
          {'id': '1', 'name': 'Подборка', 'trackCount': 12},
          {'id': '2', 'name': 'Ещё одна', 'trackCount': 3},
        ],
        onOpen: (_) {},
      ),
    };

    for (final size in const [Size(360, 640), Size(900, 700)]) {
      for (final scale in const [1.0, 1.5]) {
        for (final entry in cases.entries) {
          testWidgets('${entry.key} · ${size.width.toInt()} · x$scale',
              (tester) async {
            _screen(tester, size);

            await tester.pumpWidget(_wrap(entry.value, scale: scale));
            await tester.pump();

            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
