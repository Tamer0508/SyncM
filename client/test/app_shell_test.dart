import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/widgets/app_shell.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: AppShell(child: child),
    );

void main() {
  testWidgets('AppShell показывает вложенный экран как есть', (tester) async {
    await tester.pumpWidget(
      _host(const Scaffold(body: Center(child: Text('содержимое')))),
    );

    expect(find.text('содержимое'), findsOneWidget);
  });

  testWidgets('тап мимо поля ввода снимает фокус', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _host(
        Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              const SizedBox(height: 200, child: Center(child: Text('пустое место'))),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue, reason: 'предусловие: поле получило фокус');

    await tester.tap(find.text('пустое место'));
    await tester.pump();

    expect(
      focusNode.hasFocus,
      isFalse,
      reason: 'ради этого AppShell и существует — тап мимо поля закрывает клавиатуру',
    );
  });

  testWidgets('тап проходит к вложенным обработчикам', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      _host(
        Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('кнопка'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('кнопка'));
    await tester.pump();

    expect(taps, 1, reason: 'HitTestBehavior.translucent не должен перехватывать нажатия');
  });
}
