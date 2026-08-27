package com.example.syncm.media

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Foreground-сервис, который держит media-уведомление SyncM.
 *
 * Он ничего не воспроизводит: звук остаётся за Spotify. Нужен ровно для двух
 * вещей — карточка в шторке/на локскрине и приоритет процесса, чтобы при
 * погашенном экране SyncM продолжал получать PlayerState от Spotify и
 * обновлять карточку.
 *
 * Вся логика уведомления живёт в [MediaSessionController]: сервис — лишь
 * контейнер, который сообщает контроллеру о своём появлении и уходе.
 */
class SyncMMediaService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaSessionController.onServiceStarted(this)
        // Перезапускать сервис без живого Flutter-движка бессмысленно: команды
        // карточки было бы некому исполнять.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        MediaSessionController.onTaskRemoved()
        super.onTaskRemoved(rootIntent)
        stopSelf()
    }

    override fun onDestroy() {
        MediaSessionController.onServiceDestroyed(this)
        super.onDestroy()
    }
}
