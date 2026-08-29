import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/app_globals.dart';

class SessionForegroundService {
  static const MethodChannel _channel = MethodChannel('syncm/system');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _initialized = false;
  static bool _running = false;

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
      _running = false;
    }
  }

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

  static Future<bool> openAutostartSettings() async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openAutostart');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAppSettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {}
  }
}