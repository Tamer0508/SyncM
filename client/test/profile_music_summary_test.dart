import 'package:flutter_test/flutter_test.dart';

import 'package:syncm/screens/profile/music_summary.dart';

Map<String, dynamic> history(String title, String artist, {String? uri, String? image}) => {
      'spotifyUri': uri ?? 'spotify:track:$title',
      'trackName': title,
      'artistName': artist,
      if (image != null) 'imageUrl': image,
    };

/// Любимые приходят с теми же полями, но кое-где в приложении трек лежит
/// под именами name/artist/uri — сводка обязана понимать оба вида.
Map<String, dynamic> liked(String title, String artist, {String? uri}) => {
      'uri': uri ?? 'spotify:track:$title',
      'name': title,
      'artist': artist,
    };

void main() {
  group('MusicSummary', () {
    test('собирает исполнителей из истории и из любимых', () {
      final summary = MusicSummary.of(
        history: [
          history('t1', 'Кино'),
          history('t2', 'Кино'),
          history('t3', 'Аквариум'),
        ],
        liked: [liked('t4', 'Аквариум')],
      );

      expect(summary.topArtists.length, 2);
      expect(
        {for (final a in summary.topArtists) a.name: a.trackCount},
        {'Кино': 2, 'Аквариум': 2},
      );
    });

    test('один и тот же трек в истории и в любимых считается один раз', () {
      final summary = MusicSummary.of(
        history: [history('t1', 'Кино', uri: 'spotify:track:x')],
        liked: [liked('t1', 'Кино', uri: 'spotify:track:x')],
      );

      expect(summary.topArtists.single.trackCount, 1);
    });

    test('исполнители идут по убыванию числа треков', () {
      final summary = MusicSummary.of(
        history: [
          history('t1', 'Один'),
          history('t2', 'Двое'),
          history('t3', 'Двое'),
          history('t4', 'Трое'),
          history('t5', 'Трое'),
          history('t6', 'Трое'),
        ],
        liked: const [],
      );

      expect(
        summary.topArtists.map((a) => a.name).toList(),
        ['Трое', 'Двое', 'Один'],
      );
      expect(summary.topArtists.first.trackCount, 3);
    });

    test('при равном числе треков порядок алфавитный, а не случайный', () {
      List<String> namesOf(List<Map<String, dynamic>> tracks) =>
          MusicSummary.of(history: tracks, liked: const [])
              .topArtists
              .map((a) => a.name)
              .toList();

      // Один и тот же набор, поданный в разном порядке, обязан дать один и
      // тот же список: иначе обложки прыгают между перерисовками.
      expect(
        namesOf([history('t1', 'Бета'), history('t2', 'Альфа')]),
        namesOf([history('t2', 'Альфа'), history('t1', 'Бета')]),
      );
      expect(namesOf([history('t1', 'Бета'), history('t2', 'Альфа')]),
          ['Альфа', 'Бета']);
    });

    test('запятая внутри имени исполнителя не делит его надвое', () {
      final summary = MusicSummary.of(
        history: [
          history('t1', 'Tyler, The Creator'),
          history('t2', 'Tyler, The Creator'),
        ],
        liked: const [],
      );

      expect(summary.topArtists.length, 1);
      expect(summary.topArtists.single.name, 'Tyler, The Creator');
      expect(summary.topArtists.single.trackCount, 2);
    });

    test('берёт первую попавшуюся обложку исполнителя', () {
      final summary = MusicSummary.of(
        history: [
          history('t1', 'Кино'),
          history('t2', 'Кино', image: 'https://example.test/a.jpg'),
        ],
        liked: const [],
      );

      expect(summary.topArtists.single.imageUrl, 'https://example.test/a.jpg');
    });

    test('пустая сводка так и говорит о себе', () {
      expect(MusicSummary.of(history: const [], liked: const []).isEmpty, isTrue);
    });

    test('трек без исполнителя не создаёт безымянного исполнителя', () {
      final summary = MusicSummary.of(
        history: [history('t1', ''), history('t2', 'Кино')],
        liked: const [],
      );

      expect(summary.topArtists.single.name, 'Кино');
    });
  });

  group('SharedMusic', () {
    test('находит общих исполнителей и точные совпадения треков', () {
      final shared = SharedMusic.between(
        mine: [liked('t1', 'Кино', uri: 'a'), liked('t9', 'Аквариум', uri: 'z')],
        theirs: [
          history('t1', 'Кино', uri: 'a'),
          history('t2', 'Аквариум', uri: 'b'),
          history('t3', 'Другие', uri: 'c'),
        ],
      );

      expect(shared.tracks.map((t) => t['spotifyUri']), ['a']);
      expect(shared.artists, ['Кино', 'Аквариум']);
      expect(shared.isEmpty, isFalse);
    });

    test('исполнитель совпадает независимо от регистра', () {
      final shared = SharedMusic.between(
        mine: [liked('t1', 'КИНО', uri: 'a')],
        theirs: [history('t2', 'кино', uri: 'b')],
      );

      // Показываем ту запись, что у хозяина профиля: это его музыка.
      expect(shared.artists, ['кино']);
    });

    test('исполнитель не повторяется, сколько бы треков ни совпало', () {
      final shared = SharedMusic.between(
        mine: [liked('t1', 'Кино', uri: 'a')],
        theirs: [
          history('t2', 'Кино', uri: 'b'),
          history('t3', 'Кино', uri: 'c'),
        ],
      );

      expect(shared.artists, ['Кино']);
    });

    test('без общего — пусто, а не выдумано', () {
      final shared = SharedMusic.between(
        mine: [liked('t1', 'Кино', uri: 'a')],
        theirs: [history('t2', 'Другие', uri: 'b')],
      );

      expect(shared.isEmpty, isTrue);
    });

    test('пустой список у любой стороны даёт пустое пересечение', () {
      expect(
        SharedMusic.between(mine: const [], theirs: [history('t', 'Кино')])
            .isEmpty,
        isTrue,
      );
      expect(
        SharedMusic.between(mine: [liked('t', 'Кино')], theirs: const []).isEmpty,
        isTrue,
      );
    });
  });
}
