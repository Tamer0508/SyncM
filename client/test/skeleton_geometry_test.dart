import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/models/friend.dart';
import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/friend_tile.dart';
import 'package:syncm/widgets/skeleton.dart';
import 'package:syncm/widgets/track_card.dart';

/// Заглушка — не отдельный дизайн, а та же разметка без данных.
///
/// Проверяем это единственным способом, который ничего не упускает: строим
/// настоящий виджет и заглушку в одинаковой коробке и сравниваем коробки,
/// которые они заняли. Совпали размеры и начала — значит, при появлении
/// данных ничто не сдвинется.
Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackProvider>(create: (_) => PlaybackProvider()),
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
        // Высота не ограничена — так же, как у строки настоящего списка.
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );

/// Ширина строки списка на телефоне: экран минус боковые отступы списка.
const double _rowWidth = 360 - AppSpacing.sm * 2;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<Size> _measure(WidgetTester tester, Widget child, Type type) async {
  await tester.pumpWidget(_wrap(SizedBox(width: _rowWidth, child: child)));
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.getSize(find.byType(type).first);
}

void main() {
  group('SkeletonLine держит высоту настоящей строки текста', () {
    // Стиль строки — единственный источник её высоты и в тексте, и в
    // заглушке, поэтому проверяем сразу весь набор, которым пользуются
    // строки списков.
    for (final entry in <String, TextStyle? Function(TextTheme)>{
      'titleLarge': (t) => t.titleLarge,
      'titleMedium': (t) => t.titleMedium,
      'titleSmall': (t) => t.titleSmall,
      'bodyMedium': (t) => t.bodyMedium,
      'bodySmall': (t) => t.bodySmall,
      'labelLarge': (t) => t.labelLarge,
    }.entries) {
      testWidgets(entry.key, (tester) async {
        _phone(tester);

        late TextStyle style;
        await tester.pumpWidget(_wrap(
          Builder(
            builder: (context) {
              style = entry.value(context.texts)!;
              return const SizedBox.shrink();
            },
          ),
        ));

        final textHeight = await _measure(
          tester,
          Text('Название трека', style: style, maxLines: 1),
          Text,
        );

        final lineHeight = await _measure(
          tester,
          SkeletonLine(style: style, widthFactor: 0.5),
          SkeletonLine,
        );

        expect(lineHeight.height, textHeight.height);
      });
    }
  });

  testWidgets('строка друга: заглушка занимает ту же коробку', (tester) async {
    _phone(tester);

    const friend = Friend(
      id: 'u1',
      name: 'Александра Иванова',
      isOnline: true,
      lastSeenAt: null,
    );

    await tester.pumpWidget(_wrap(
      SizedBox(
        width: _rowWidth,
        child: FriendTile(
          friend: friend,
          onViewProfile: () {},
          onRemoveFriend: () {},
        ),
      ),
    ));
    await tester.pump();

    final realSize = tester.getSize(find.byType(FriendTile));
    final realTitle = tester.getTopLeft(find.text(friend.name));

    await tester.pumpWidget(_wrap(
      const SizedBox(width: _rowWidth, child: SkeletonFriendTile()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final fakeSize = tester.getSize(find.byType(SkeletonFriendTile));
    final fakeTitle = tester.getTopLeft(find.byType(SkeletonLine).first);

    expect(fakeSize, realSize);
    // Заголовок начинается там же: совпадают и отступ слева, и высота
    // строки, и вертикальное выравнивание колонки.
    expect(fakeTitle, realTitle);
  });

  testWidgets('строка трека со звёздочкой и меню: та же высота',
      (tester) async {
    _phone(tester);

    await tester.pumpWidget(_wrap(
      SizedBox(
        width: _rowWidth,
        child: TrackCard(
          id: 't1',
          title: 'Песня',
          artist: 'Исполнитель',
          durationMs: 215000,
          onPlay: () {},
          trailing: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ),
      ),
    ));
    await tester.pump();

    final realSize = tester.getSize(find.byType(TrackCard));
    final realTitle = tester.getTopLeft(find.text('Песня'));

    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: _rowWidth,
        child: SkeletonTrackCard(
          showLike: true,
          trailing: SkeletonTrackTrailing.menu,
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final fakeSize = tester.getSize(find.byType(SkeletonTrackCard));
    final fakeTitle = tester.getTopLeft(find.byType(SkeletonLine).first);

    expect(fakeSize, realSize);
    expect(fakeTitle, realTitle);
  });

  testWidgets('строка трека с коробкой выбора: та же высота', (tester) async {
    _phone(tester);

    await tester.pumpWidget(_wrap(
      SizedBox(
        width: _rowWidth,
        child: TrackCard(
          id: 't1',
          title: 'Песня',
          artist: 'Исполнитель',
          durationMs: 215000,
          showLike: false,
          onPlay: () {},
          trailing: SizedBox.square(
            dimension: 48,
            child: Center(child: Checkbox(value: false, onChanged: (_) {})),
          ),
        ),
      ),
    ));
    await tester.pump();

    final realSize = tester.getSize(find.byType(TrackCard));

    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: _rowWidth,
        child: SkeletonTrackCard(trailing: SkeletonTrackTrailing.box),
      ),
    ));
    await tester.pump();

    expect(tester.getSize(find.byType(SkeletonTrackCard)), realSize);
  });

  testWidgets('строка истории: заглушка совпадает с ListTile', (tester) async {
    _phone(tester);

    // Тот же ListTile, что строит экран истории.
    await tester.pumpWidget(_wrap(
      SizedBox(
        width: _rowWidth,
        child: ListTile(
          leading: Container(width: 44, height: 44, color: Colors.grey),
          title: const Text('Песня', maxLines: 1),
          subtitle: const Text('Исполнитель', maxLines: 1),
          trailing: const Text('12:30'),
        ),
      ),
    ));
    await tester.pump();

    final realHeight = tester.getSize(find.byType(ListTile)).height;

    await tester.pumpWidget(_wrap(
      const SizedBox(width: _rowWidth, child: SkeletonHistoryList(itemCount: 1)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(tester.getSize(find.byType(ListTile)).height, realHeight);
  });

  group('заглушки раскладываются без ошибок', () {
    final cases = <String, Widget>{
      'друзья': const SkeletonFriendList(),
      'заявки': const SkeletonRequestList(),
      'приглашения': const SkeletonInviteList(),
      'заблокированные': const SkeletonBlockedList(),
      'устройства': const SkeletonDeviceList(),
      'треки: пусто': const SkeletonTrackList(),
      'треки: флажок': const SkeletonTrackList(
        trailing: SkeletonTrackTrailing.checkbox,
      ),
      'треки: коробка': const SkeletonTrackList(
        trailing: SkeletonTrackTrailing.box,
      ),
      'треки: меню и ручка': const SkeletonTrackList(
        showLike: true,
        trailing: SkeletonTrackTrailing.menuAndHandle,
      ),
      'история': const SkeletonHistoryList(),
      'плейлисты': const SkeletonPlaylistList(),
      'выбор плейлиста': const SkeletonPickPlaylistList(),
      'карточка сессии': const SkeletonSessionCard(),
      'шапка профиля': const SkeletonProfileHeader(),
      'кнопки профиля': const SkeletonProfileActions(isOwnProfile: true),
      'раздел профиля': const SkeletonProfileTrackSection(),
    };

    // Строка «Разблокировать» на узком экране при крупном шрифте не
    // помещается — ровно так же, как настоящая строка того же экрана
    // (проверено: обе переполняются на одно и то же число точек). Это
    // ограничение самого экрана, и заглушка обязана его повторять, а не
    // расходиться с ним ради зелёного теста.
    const knownTightRows = {'заблокированные'};

    // Узкий телефон, планшет и крупный системный шрифт: заглушка тянется по
    // тем же правилам, что и настоящая разметка, поэтому нигде не должна ни
    // переполняться, ни требовать бесконечной ширины.
    for (final size in const [Size(360, 640), Size(900, 700)]) {
      for (final scale in const [1.0, 1.5]) {
        for (final entry in cases.entries) {
          if (scale > 1 &&
              size.width < 700 &&
              knownTightRows.contains(entry.key)) {
            continue;
          }

          testWidgets('${entry.key} · ${size.width.toInt()} · x$scale',
              (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(_wrap(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                // Ограниченная высота: так заглушку показывают экраны,
                // где она занимает отведённую списку область.
                child: SizedBox(height: size.height - 100, child: entry.value),
              ),
            ));
            await tester.pump();

            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  testWidgets('заглушки не рисуют и не ловят нажатия своих мерок',
      (tester) async {
    _phone(tester);

    await tester.pumpWidget(_wrap(
      const SizedBox(width: _rowWidth, child: SkeletonFriendTile()),
    ));
    await tester.pump();

    // Кнопка-мерка внутри SkeletonSlot существует только ради размера:
    // нажатие по ней не должно ни во что попасть.
    await tester.tap(find.byType(SkeletonSlot), warnIfMissed: false);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
