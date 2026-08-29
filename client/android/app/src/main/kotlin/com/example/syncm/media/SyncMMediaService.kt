package com.example.syncm.media

import android.app.Service
import android.content.Intent
import android.os.IBinder

class SyncMMediaService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaSessionController.onServiceStarted(this)
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
