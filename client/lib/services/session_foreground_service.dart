import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/app_globals.dart';

/// Управляет foreground-сервисом и wakelock на время активной сессии.
///
/// Зачем: когда экран гаснет, Android через некоторое время замораживает
/// приложение, и синхронизация встаёт. Foreground-сервис (постоянное
/// уведомление в шторке) говорит системе «не замораживай меня», а wakelock
/// не даёт заснуть процессору — вместе они позволяют держать сокет и
/// синхронизацию при погашенном экране.
///
/// Работает только на Android. На iOS/Windows/Web — no-op (там свои механизмы
/// фоновой работы, и flutter_foreground_task их не покрывает).
class SessionForegroundService {
  static const MethodChannel _channel = MethodChannel('syncm/system');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _initialized = false;
  static bool _running = false;

  /// Одноразовая инициализация параметров сервиса. Безопасно вызывать повторно.
  static void _ensureInitialized() {
    if (_initialized || !_isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'syncm_session',
        channelName: appL10n?.foregroundChannelName ?? 'Активная сессия SyncM',
        channelDescription:
            appL10n?.foregroundChannelDescription ??
                'Показывается, пока идёт совместное прослушивание, чтобы синхронизация не прерывалась.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> start({
    String? title,
    String? text,
    bool keepScreenOn = true,
  }) async {
    if (keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }

    if (!_isAndroid) return;
    _ensureInitialized();

    // Текст видно в системной шторке, поэтому язык — как в приложении.
    final l = appL10n;
    final notificationTitle = title ?? l?.foregroundTitle ?? 'Сессия SyncM активна';
    final notificationText = text ?? l?.foregroundText ?? 'Слушаете вместе с друзьями';

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
        );
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
        );
      }
      _running = true;
    } catch (_) {
      // Если сервис не стартовал (нет разрешения на уведомления и т.п.) —
      // не роняем приложение, просто остаёмся без фонового удержания.
      _running = false;
    }
  }

  /// Останавливает сервис и снимает wakelock. Вызывать при выходе из сессии.
  static Future<void> stop() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}

    if (!_isAndroid) return;
    try {
      if (_running || await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
    _running = false;
  }

  /// Запрашивает разрешения для надёжной фоновой работы: уведомления и игнор
  /// оптимизации батареи. Вызывать перед start() или из настроек.
  static Future<bool> requestPermissions() async {
    if (!_isAndroid) return true;
    _ensureInitialized();
    try {
      final notif = await FlutterForegroundTask.checkNotificationPermission();
      if (notif != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Открывает вендорский экран автозапуска (MIUI/Huawei/Oppo/Vivo и т.п.).
  /// Если у устройства такого экрана нет — откроются настройки приложения.
  /// Возвращает true, если открылся именно вендорский экран автозапуска.
  static Future<bool> openAutostartSettings() async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openAutostart');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Открывает системный экран «О приложении» (там можно вручную выставить
  /// батарею «Без ограничений» и прочее).
  static Future<void> openAppSettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {}
  }
}