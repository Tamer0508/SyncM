package com.example.syncm.media

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MediaActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        MediaSessionController.handleAction(intent.action)
    }
}
