package com.example.syncm

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import com.example.syncm.media.MediaSessionChannel
import com.example.syncm.media.MediaSessionController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "syncm/system"

    // Мост к системной media-карточке. Живёт ровно столько же, сколько
    // Flutter-движок: команды карточки исполняет Dart, и без движка её
    // показывать нельзя.
    private var mediaSessionChannel: MediaSessionChannel? = null

    // Портретная блокировка объявлена в AndroidManifest и действует с самого
    // старта процесса. Планшетам и раскладным экранам она не нужна: у SyncM
    // для широкого окна есть своя раскладка (боковой рельс, панель Now
    // Playing), и запирать их в portrait — значит выбросить её.
    //
    // Android 16 (targetSdk 36) сам игнорирует screenOrientation на больших
    // экранах; здесь то же самое делается явно и для более старых версий,
    // чтобы поведение не зависело от версии системы.
    //
    // smallestScreenWidthDp — характеристика устройства, а не текущей
    // ориентации, поэтому одной проверки при старте достаточно: ни
    // слушателей, ни таймеров, ни повторных вызовов.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (resources.configuration.smallestScreenWidthDp >= LARGE_SCREEN_DP) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAutostart" -> result.success(openAutostartSettings())
                    "openAppSettings" -> {
                        openAppDetailsSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        mediaSessionChannel =
            MediaSessionChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        handleOpenIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleOpenIntent(intent)
    }

    // Нажатие на media-карточку должно открывать Now Playing в SyncM, а не
    // Spotify. Экран открывает существующая навигация приложения — здесь
    // только доставляется сам факт нажатия.
    private fun handleOpenIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(MediaSessionController.EXTRA_OPEN_NOW_PLAYING, false) != true) {
            return
        }
        // Флаг одноразовый: иначе Now Playing открывался бы снова при каждом
        // возврате в приложение по тому же intent-у.
        intent.removeExtra(MediaSessionController.EXTRA_OPEN_NOW_PLAYING)
        mediaSessionChannel?.requestOpenNowPlaying()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaSessionChannel?.dispose()
        mediaSessionChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Пытается открыть вендор-специфичный экран автозапуска (MIUI, Huawei,
    // Oppo, Vivo и т.п.). Возвращает true, если удалось открыть хоть один.
    // Если ни один не подошёл — открывает обычные настройки приложения.
    private fun openAutostartSettings(): Boolean {
        val components = listOf(
            // Xiaomi / MIUI
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // Huawei
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ),
            // Oppo
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            // Vivo
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            // Letv
            ComponentName(
                "com.letv.android.letvsafe",
                "com.letv.android.letvsafe.AutobootManageActivity"
            )
        )

        for (component in components) {
            try {
                val intent = Intent().apply {
                    setComponent(component)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Компонент не существует на этом устройстве — пробуем следующий.
            }
        }

        openAppDetailsSettings()
        return false
    }

    private fun openAppDetailsSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private companion object {
        // Тот же порог, что и у AppLayout.railMinSpace в theme.dart: начиная с
        // этой ширины интерфейс переключается на широкую раскладку.
        const val LARGE_SCREEN_DP = 600
    }
}