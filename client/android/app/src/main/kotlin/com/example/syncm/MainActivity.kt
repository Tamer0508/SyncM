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

    private var mediaSessionChannel: MediaSessionChannel? = null

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

    private fun handleOpenIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(MediaSessionController.EXTRA_OPEN_NOW_PLAYING, false) != true) {
            return
        }
        intent.removeExtra(MediaSessionController.EXTRA_OPEN_NOW_PLAYING)
        mediaSessionChannel?.requestOpenNowPlaying()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaSessionChannel?.dispose()
        mediaSessionChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun openAutostartSettings(): Boolean {
        val components = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
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
        const val LARGE_SCREEN_DP = 600
    }
}