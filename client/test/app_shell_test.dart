import 'package:syncm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/providers/playback_provider.dart';
import 'package:syncm/widgets/app_shell.dart';

class TestPlaybackProvider extends PlaybackProvider {
  TestPlaybackProvider(this._track);

  final Map<String, dynamic>? _track;

  @override
  Map<String, dynamic>? get currentTrack => _track;

  @override
  bool get isPlaying => true;
}

void main() {
  testWidgets('AppShell shows mini player when playback has a current track', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<PlaybackProvider>.value(
        value: TestPlaybackProvider({
          'title': 'Test track',
          'artist': 'Test artist',
        }),
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: AppShell(
            child: Scaffold(
              body: Center(child: Text('content')),
            ),
          ),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(find.text('Test track'), findsOneWidget);
  });
}
