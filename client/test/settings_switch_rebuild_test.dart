import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:syncm/l10n/app_localizations.dart';
import 'package:syncm/providers/appearance_provider.dart';
import 'package:syncm/theme.dart';
import 'package:syncm/utils/local_store.dart';
import 'package:syncm/widgets/settings_widgets.dart';

/// Один тап по переключателю обязан перестроить одну строку.
///
/// Раньше он будил `AppearanceProvider`, а на него подписан весь
/// `MaterialApp` — тема, плотность, масштаб текста. Вдобавок раздел
/// настроек читал флаги через `context.watch` и пересобирался целиком.
/// Оба перестроения приходились ровно на тот кадр, с которого начинается
/// анимация тумблера, — отсюда и рывок.
Widget _wrap(Widget child) => ChangeNotifierProvider<AppearanceProvider>(
      create: (_) => AppearanceProvider(),
      child: MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('ru'),
        theme: AppTheme.build(
          brightness: Brightness.light,
          accent: AccentColor.values.first,
          compact: false,
          reduceMotion: false,
        ),
        home: Scaffold(body: child),
      ),
    );

/// Считает, сколько раз перестроилось поддерево.
class _Counter extends StatelessWidget {
  const _Counter({required this.onBuild, required this.child});

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
}

void main() {
  testWidgets('переключение флага не будит подписчиков AppearanceProvider',
      (tester) async {
    var rootBuilds = 0;

    await tester.pumpWidget(_wrap(
      // Так устроен корень приложения: Consumer поверх всего, потому что от
      // оформления зависят тема и масштаб текста.
      Consumer<AppearanceProvider>(
        builder: (context, _, _) {
          rootBuilds += 1;
          return const SettingsFlagSwitch(
            flagKey: StoreKeys.confirmEndSession,
            title: 'Спрашивать перед завершением',
            defaultValue: true,
          );
        },
      ),
    ));

    final before = rootBuilds;
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(rootBuilds, before, reason: 'корень приложения перестраиваться не должен');
  });

  testWidgets('перестраивается только своя строка', (tester) async {
    final builds = <String, int>{
      StoreKeys.autoOpenPlayer: 0,
      StoreKeys.keepScreenOn: 0,
      StoreKeys.confirmEndSession: 0,
    };

    Widget row(String key, String title) => _Counter(
          onBuild: () => builds[key] = builds[key]! + 1,
          child: SettingsFlagSwitch(
            flagKey: key,
            title: title,
            defaultValue: true,
          ),
        );

    var sectionBuilds = 0;

    await tester.pumpWidget(_wrap(
      // Так устроен раздел настроек: он подписан на провайдер ради других
      // своих данных и собирает строки списком.
      Consumer<AppearanceProvider>(
        builder: (context, _, _) {
          sectionBuilds += 1;
          return Column(
            children: [
              row(StoreKeys.autoOpenPlayer, 'Открывать плеер'),
              row(StoreKeys.keepScreenOn, 'Не гасить экран'),
              row(StoreKeys.confirmEndSession, 'Спрашивать'),
            ],
          );
        },
      ),
    ));

    final before = Map<String, int>.from(builds);
    final sectionBefore = sectionBuilds;

    await tester.tap(find.text('Не гасить экран'));
    await tester.pumpAndSettle();

    // Раздел целиком не пересобирается...
    expect(sectionBuilds, sectionBefore);
    // ...а соседние строки к чужому флагу отношения не имеют.
    expect(builds[StoreKeys.autoOpenPlayer], before[StoreKeys.autoOpenPlayer]);
    expect(builds[StoreKeys.confirmEndSession],
        before[StoreKeys.confirmEndSession]);

    // И у них не сбилось значение.
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isFalse);
    expect(switches[2].value, isTrue);
  });

  testWidgets('разметка строки не шевелится во время анимации',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      const SettingsGroup(
        children: [
          SettingsFlagSwitch(
            flagKey: StoreKeys.keepScreenOn,
            title: 'Не гасить экран',
            subtitle: 'Пока идёт сессия',
            icon: Icons.screen_lock_portrait_outlined,
            defaultValue: true,
          ),
          SettingsFlagSwitch(
            flagKey: StoreKeys.confirmEndSession,
            title: 'Спрашивать перед завершением',
            subtitle: 'Чтобы не оборвать случайно',
            icon: Icons.help_outline_rounded,
            defaultValue: true,
          ),
        ],
      ),
    ));

    Rect rectOf(String text) => tester.getRect(find.text(text));

    final row = tester.getRect(find.byType(SwitchListTile).first);
    final title = rectOf('Не гасить экран');
    final neighbour = rectOf('Спрашивать перед завершением');
    final group = tester.getSize(find.byType(SettingsGroup));

    await tester.tap(find.byType(Switch).first);

    // Кадры анимации тумблера: ни строка, ни текст, ни соседи, ни группа
    // не должны сдвинуться ни на точку.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 25));

      expect(tester.getRect(find.byType(SwitchListTile).first), row);
      expect(rectOf('Не гасить экран'), title);
      expect(rectOf('Спрашивать перед завершением'), neighbour);
      expect(tester.getSize(find.byType(SettingsGroup)), group);
    }

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(SwitchListTile).first), row);
    expect(tester.getSize(find.byType(SettingsGroup)), group);
  });

  testWidgets('быстрые повторные переключения не ломают состояние',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const SettingsFlagSwitch(
        flagKey: StoreKeys.autoOpenPlayer,
        title: 'Открывать плеер',
        defaultValue: true,
      ),
    ));

    // Тап, не дожидаясь конца анимации, — и так пять раз подряд.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Нечётное число переключений от «включено» — значит выключено.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('строка переключателя изолирована по перерисовке',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const SettingsFlagSwitch(
        flagKey: StoreKeys.keepScreenOn,
        title: 'Не гасить экран',
        defaultValue: true,
      ),
    ));

    // Анимация тумблера идёт два десятка кадров; без своей области
    // перерисовки каждый кадр пачкал бы скруглённую группу целиком.
    expect(
      find.descendant(
        of: find.byType(SettingsSwitch),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });

  group('AppearanceProvider.flagListenable', () {
    test('слушатель срабатывает только на свой ключ', () {
      final appearance = AppearanceProvider();
      addTearDown(appearance.dispose);

      var mine = 0;
      var other = 0;
      appearance
          .flagListenable(StoreKeys.keepScreenOn)
          .addListener(() => mine += 1);
      appearance
          .flagListenable(StoreKeys.autoOpenPlayer)
          .addListener(() => other += 1);

      appearance.setFlag(StoreKeys.keepScreenOn, true);

      expect(mine, 1);
      expect(other, 0);
    });

    test('повторная запись того же значения никого не будит', () {
      final appearance = AppearanceProvider();
      addTearDown(appearance.dispose);

      appearance.setFlag(StoreKeys.keepScreenOn, true);

      var calls = 0;
      appearance
          .flagListenable(StoreKeys.keepScreenOn)
          .addListener(() => calls += 1);

      appearance.setFlag(StoreKeys.keepScreenOn, true);

      expect(calls, 0);
      expect(appearance.flag(StoreKeys.keepScreenOn), isTrue);
    });

    test('значение по умолчанию берётся при первом обращении', () {
      final appearance = AppearanceProvider();
      addTearDown(appearance.dispose);

      expect(
        appearance.flag(StoreKeys.confirmEndSession, defaultValue: true),
        isTrue,
      );
      expect(appearance.flag(StoreKeys.prefetchOnStart), isFalse);
    });
  });
}
