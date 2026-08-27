package com.example.syncm.media

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Кнопки media-уведомления.
 *
 * Через broadcast, а не через PendingIntent на сервис: старт сервиса из фона
 * на Android 12+ запрещён, а доставка широковещательного intent-а внутри
 * собственного процесса — нет. Системные media controls (шторка, локскрин,
 * Bluetooth) ходят не сюда, а напрямую в MediaSessionCompat.Callback;
 * ресивер обслуживает только классический вид уведомления.
 */
class MediaActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        MediaSessionController.handleAction(intent.action)
    }
}
