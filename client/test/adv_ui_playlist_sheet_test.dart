import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/playlists_provider.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/add_to_playlist_sheet.dart';

class _SlowPlaylists extends PlaylistsProvider {
  _SlowPlaylists(this._items);

  final List<Map<String, dynamic>> _items;

  final List<Completer<({int added, int skipped})>> pending = [];

  int addCalls = 0;

  @override
  List<Map<String, dynamic>> get custom => _items;

  @override
  bool get loadingCustom => false;

  @override
  Future<void> loadCustom({bool refresh = false}) async {}

  @override
  Future<({int added, int skipped})> addTracks(
    String playlistId,
    List<Map<String, dynamic>> tracks,
  ) {
    addCalls++;
    final completer = Completer<({int added, int skipped})>();
    pending.add(completer);
    return completer.future;
  }
}

const _track = {
  'uri': 'spotify:track:1',
  'name': 'Трек',
  'artist': 'Исполнитель',
  'durationMs': 200000,
};

const _underlyingMarker = 'ЭКРАН-ПОД-СТВОРКОЙ';

Future<_SlowPlaylists> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = _SlowPlaylists([
    {'id': 'p1', 'name': 'Мой плейлист', 'isCustom': true, 'trackCount': 3},
  ]);

  await tester.pumpWidget(
    ChangeNotifierProvider<PlaylistsProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        theme: AppTheme.build(
          brightness: Brightness.light,
          accent: AccentColor.values.first,
          compact: false,
          reduceMotion: true,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Builder(
                        builder: (inner) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(_underlyingMarker),
                              FilledButton(
                                onPressed: () =>
                                    showAddToPlaylistSheet(inner, _track),
                                child: const Text('СТВОРКА'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('ДАЛЬШЕ'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('ДАЛЬШЕ'));
  await tester.pumpAndSettle();
  expect(find.text(_underlyingMarker), findsOneWidget);

  await tester.tap(find.text('СТВОРКА'));
  await tester.pumpAndSettle();
  expect(find.text('Мой плейлист'), findsOneWidget);

  return provider;
}

void main() {
  testWidgets(
      'створка закрыта до ответа сети — ответ уносит с собой экран под ней',
      (tester) async {
    final provider = await _openSheet(tester);

    await tester.tap(find.text('Мой плейлист'));
    await tester.pump();
    expect(provider.addCalls, 1);

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(find.text('Мой плейлист'), findsNothing,
        reason: 'створка должна была закрыться от касания мимо');
    expect(find.text(_underlyingMarker), findsOneWidget);

    provider.pending.first.complete((added: 1, skipped: 0));
    await tester.pumpAndSettle();

    expect(find.text(_underlyingMarker), findsOneWidget,
        reason: 'ответ сети закрыл экран, который человек не закрывал');
  });

  testWidgets('двойное касание строки плейлиста не должно рушить стек экранов',
      (tester) async {
    final provider = await _openSheet(tester);

    await tester.tap(find.text('Мой плейлист'));
    await tester.pump(const Duration(milliseconds: 16));
    if (find.text('Мой плейлист').evaluate().isNotEmpty) {
      await tester.tap(find.text('Мой плейлист'));
      await tester.pump(const Duration(milliseconds: 16));
    }

    for (final completer in provider.pending) {
      completer.complete((added: 1, skipped: 0));
    }
    await tester.pumpAndSettle();

    expect(find.text(_underlyingMarker), findsOneWidget,
        reason: 'лишний pop снял экран под створкой');
    expect(provider.addCalls, 1,
        reason: 'второе касание отправило второй запрос на добавление');
  });
}
