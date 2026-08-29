import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/playlist_card.dart';
import 'package:syncm/widgets/skeleton.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      theme: AppTheme.build(
        brightness: Brightness.light,
        accent: AccentColor.values.first,
        compact: false,
        reduceMotion: true,
      ),
      home: Scaffold(
        body: Column(children: [const SizedBox(height: 48), Expanded(child: child)]),
      ),
    );

void main() {
  testWidgets('строка-заглушка плейлиста совпадает по высоте с карточкой',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const SkeletonPlaylistList()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final skeletonHeight =
        tester.getSize(find.byType(SkeletonPlaylistTile).first).height;

    await tester.pumpWidget(_wrap(
      ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xl,
        ),
        children: const [
          PlaylistCard(dense: true, name: 'Плейлист', description: '12 треков'),
        ],
      ),
    ));
    await tester.pump();

    final cardSize = tester.getSize(find.byType(PlaylistCard));

    expect(skeletonHeight, cardSize.height);
    expect(skeletonHeight, lessThan(100));
  });

  testWidgets('заглушка не переполняется на низком экране', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const SkeletonPlaylistList(itemCount: 12)));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
