import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/appearance_provider.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/widgets/settings_widgets.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    ChangeNotifierProvider<AppearanceProvider>(
      create: (_) => AppearanceProvider(),
      child: MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('ru'),
        theme: AppTheme.build(
          brightness: brightness,
          accent: AccentColor.values.first,
        ),
        home: Scaffold(body: child),
      ),
    );

Future<void> _setWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('строка настройки не мельче удобной цели нажатия',
      (tester) async {
    await _setWindow(tester, const Size(360, 800));

    await tester.pumpWidget(_wrap(
      SettingsGroup(
        children: [
          SettingsAction(
            icon: Icons.badge_outlined,
            title: 'Имя',
            onTap: () {},
          ),
        ],
      ),
    ));

    expect(
      tester.getSize(find.byType(SettingsRow)).height,
      greaterThanOrEqualTo(SettingsMetrics.rowMinHeight),
    );
  });

  testWidgets('на широком окне колонка не растягивается и стоит по центру',
      (tester) async {
    await _setWindow(tester, const Size(1600, 900));

    await tester.pumpWidget(_wrap(
      SettingsScrollView(
        children: [
          SettingsGroup(
            children: [
              SettingsAction(title: 'Имя', onTap: () {}),
            ],
          ),
        ],
      ),
    ));

    final card = tester.getRect(find.byType(SettingsGroup));

    expect(
      card.width,
      lessThanOrEqualTo(SettingsMetrics.contentMaxWidth),
      reason: 'строка настройки не должна тянуться на весь монитор',
    );
    expect(
      card.center.dx,
      moreOrLessEquals(800, epsilon: 1),
      reason: 'колонка стоит по центру окна',
    );
  });

  testWidgets('на узком экране колонка занимает ширину за вычетом полей',
      (tester) async {
    await _setWindow(tester, const Size(320, 640));

    await tester.pumpWidget(_wrap(
      SettingsScrollView(
        children: [
          SettingsGroup(
            children: [
              SettingsAction(title: 'Имя', onTap: () {}),
            ],
          ),
        ],
      ),
    ));

    expect(
      tester.getSize(find.byType(SettingsGroup)).width,
      moreOrLessEquals(320 - SettingsMetrics.pagePadding * 2, epsilon: 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('длинные подписи не выходят за границы строки', (tester) async {
    await _setWindow(tester, const Size(320, 640));

    await tester.pumpWidget(_wrap(
      SettingsScrollView(
        children: [
          SettingsGroup(
            children: [
              SettingsAction(
                icon: Icons.storage_outlined,
                title: 'Сохранённые списки и обложки, которые лежат на диске',
                subtitle:
                    'Друзья: 42 · Сессии: 17 · обновлено несколько минут назад',
                value: '128,4 МБ на диске',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    ));

    expect(tester.takeException(), isNull);
  });

  testWidgets('справочная строка не притворяется кнопкой', (tester) async {
    await tester.pumpWidget(_wrap(
      const SettingsGroup(
        children: [
          SettingsInfo(
            icon: Icons.lock_outline_rounded,
            title: 'Имя и аватар',
            subtitle: 'Видны всем',
          ),
        ],
      ),
    ));

    expect(
      find.descendant(
        of: find.byType(SettingsInfo),
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason: 'нажимать здесь не на что — подсветки быть не должно',
    );
  });

  testWidgets('выключенная строка не срабатывает', (tester) async {
    var taps = 0;

    await tester.pumpWidget(_wrap(
      SettingsGroup(
        children: [
          SettingsAction(
            icon: Icons.download_outlined,
            title: 'Выгрузить данные',
            enabled: false,
            onTap: () => taps += 1,
          ),
        ],
      ),
    ));

    await tester.tap(find.text('Выгрузить данные'));
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('переключатель меняется нажатием в любое место строки',
      (tester) async {
    var value = false;

    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (context, setState) => SettingsGroup(
          children: [
            SettingsSwitch(
              icon: Icons.density_medium_rounded,
              title: 'Плотнее',
              subtitle: 'Больше строк на экране',
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ],
        ),
      ),
    ));

    await tester.tap(find.text('Больше строк на экране'));
    await tester.pumpAndSettle();

    expect(value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('группа рисуется обеими темами', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(_wrap(
        brightness: brightness,
        SettingsScrollView(
          children: [
            SettingsGroup(
              title: 'Оформление',
              footer: 'Меняется сразу, без перезапуска',
              children: [
                SettingsAction(
                  icon: Icons.palette_outlined,
                  title: 'Акцент',
                  value: 'Оливковый',
                  chevron: true,
                  onTap: () {},
                ),
                const SettingsInfo(
                  icon: Icons.info_outline_rounded,
                  title: 'Версия',
                  subtitle: '1.0.0',
                ),
              ],
            ),
          ],
        ),
      ));

      expect(tester.takeException(), isNull, reason: '$brightness');
      expect(find.text('Оформление'), findsOneWidget);
    }
  });
}
