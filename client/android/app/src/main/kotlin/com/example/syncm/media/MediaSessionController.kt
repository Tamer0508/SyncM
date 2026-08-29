package com.example.syncm.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.example.syncm.MainActivity
import com.example.syncm.R

interface MediaCommandSink {
    fun onCommand(action: String, value: Long?)
}

object MediaSessionController {

    private const val TAG = "SyncMMediaSession"

    const val CHANNEL_ID = "syncm_media"

    private const val ABANDONED_CHANNEL_ID = "syncm_media_playback"
    const val NOTIFICATION_ID = 0x5C41

    const val EXTRA_OPEN_NOW_PLAYING = "com.example.syncm.OPEN_NOW_PLAYING"

    private const val PREFIX = "com.example.syncm.media.action."
    const val ACTION_PLAY = PREFIX + "PLAY"
    const val ACTION_PAUSE = PREFIX + "PAUSE"
    const val ACTION_NEXT = PREFIX + "NEXT"
    const val ACTION_PREVIOUS = PREFIX + "PREVIOUS"
    const val ACTION_STOP = PREFIX + "STOP"

    const val CMD_PLAY = "play"
    const val CMD_PAUSE = "pause"
    const val CMD_NEXT = "next"
    const val CMD_PREVIOUS = "previous"
    const val CMD_SEEK = "seek"
    const val CMD_STOP = "stop"
    const val CMD_SHUFFLE = "shuffle"
    const val CMD_REPEAT = "repeat"

    private const val ARTWORK_MAX_PX = 512

    private var appContext: Context? = null
    private var session: MediaSessionCompat? = null
    private var sink: MediaCommandSink? = null
    private var service: Service? = null
    private var foregroundStarted = false
    private var channelReady = false
    private var notifiedSignature: String? = null

    private var channelName = "Playback"
    private var channelDescription = ""

    private var active = false
    private var trackId: String? = null
    private var title = ""
    private var artist = ""
    private var album = ""
    private var durationMs = 0L
    private var positionMs = 0L
    private var positionUpdatedAt = 0L
    private var isPlaying = false

    private var isBuffering = false
    private var shuffle = false
    private var repeatMode = PlaybackStateCompat.REPEAT_MODE_NONE
    private var artwork: Bitmap? = null

    private val callback = object : MediaSessionCompat.Callback() {
        override fun onPlay() = dispatch(CMD_PLAY, null)
        override fun onPause() = dispatch(CMD_PAUSE, null)
        override fun onSkipToNext() = dispatch(CMD_NEXT, null)
        override fun onSkipToPrevious() = dispatch(CMD_PREVIOUS, null)
        override fun onStop() = dispatch(CMD_STOP, null)
        override fun onSeekTo(pos: Long) = dispatch(CMD_SEEK, pos)

        override fun onSetShuffleMode(shuffleMode: Int) = dispatch(
            CMD_SHUFFLE,
            if (shuffleMode == PlaybackStateCompat.SHUFFLE_MODE_NONE) 0L else 1L
        )

        override fun onSetRepeatMode(repeat: Int) = dispatch(CMD_REPEAT, repeat.toLong())
    }

    @Synchronized
    fun attach(
        context: Context,
        commandSink: MediaCommandSink,
        notificationChannelName: String?,
        notificationChannelDescription: String?,
    ) {
        appContext = context.applicationContext
        sink = commandSink
        notificationChannelName?.takeIf { it.isNotBlank() }?.let {
            if (it != channelName) {
                channelName = it
                channelReady = false
            }
        }
        notificationChannelDescription?.takeIf { it.isNotBlank() }?.let {
            if (it != channelDescription) {
                channelDescription = it
                channelReady = false
            }
        }
    }

    @Synchronized
    fun detach(commandSink: MediaCommandSink) {
        if (sink !== commandSink) return
        sink = null
        release()
    }

    @Synchronized
    fun updateTrack(
        id: String?,
        newTitle: String,
        newArtist: String,
        newAlbum: String,
        newDurationMs: Long,
    ) {
        val changed = id != trackId
        trackId = id
        title = newTitle
        artist = newArtist
        album = newAlbum
        durationMs = newDurationMs
        if (changed) artwork = null
        active = true
        ensureSession() ?: return
        publish()
    }

    @Synchronized
    fun updateArtwork(id: String?, bytes: ByteArray?) {
        if (id != trackId) return
        artwork = bytes?.let { decodeArtwork(it) }
        if (session == null) return
        publish()
    }

    @Synchronized
    fun updatePlayback(
        playing: Boolean,
        buffering: Boolean,
        newPositionMs: Long,
        newDurationMs: Long,
        shuffling: Boolean,
        repeat: String,
    ) {
        isPlaying = playing
        isBuffering = buffering
        positionMs = if (newPositionMs < 0) 0 else newPositionMs
        positionUpdatedAt = SystemClock.elapsedRealtime()
        if (newDurationMs > 0) durationMs = newDurationMs
        shuffle = shuffling
        repeatMode = when (repeat) {
            "track" -> PlaybackStateCompat.REPEAT_MODE_ONE
            "context" -> PlaybackStateCompat.REPEAT_MODE_ALL
            else -> PlaybackStateCompat.REPEAT_MODE_NONE
        }
        if (!active) return
        ensureSession() ?: return
        publish()
    }

    @Synchronized
    fun release() {
        active = false
        isPlaying = false
        isBuffering = false
        trackId = null
        artwork = null
        title = ""
        artist = ""
        album = ""
        durationMs = 0
        positionMs = 0
        stopService()
        session?.let {
            it.isActive = false
            it.setCallback(null)
            it.release()
        }
        session = null
    }

    private fun ensureSession(): MediaSessionCompat? {
        session?.let { return it }
        val context = appContext ?: return null
        return try {
            MediaSessionCompat(context, TAG).also {
                it.setCallback(callback)
                it.setSessionActivity(sessionActivityIntent(context))
                it.isActive = true
                session = it
            }
        } catch (e: Exception) {
            Log.w(TAG, "Не удалось создать MediaSession: $e")
            null
        }
    }

    private fun publish() {
        val current = session ?: return
        try {
            current.setMetadata(buildMetadata())
            current.setPlaybackState(buildState())
            current.setShuffleMode(
                if (shuffle) PlaybackStateCompat.SHUFFLE_MODE_ALL
                else PlaybackStateCompat.SHUFFLE_MODE_NONE
            )
            current.setRepeatMode(repeatMode)
        } catch (e: Exception) {
            Log.w(TAG, "Не удалось обновить состояние сессии: $e")
        }
        updateNotification()
    }

    private fun buildMetadata(): MediaMetadataCompat {
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, trackId ?: "")
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(
                MediaMetadataCompat.METADATA_KEY_DURATION,
                if (durationMs > 0) durationMs else -1L
            )
        artwork?.let {
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, it)
        }
        return builder.build()
    }

    private fun buildState(): PlaybackStateCompat {
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_STOP or
            PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE or
            PlaybackStateCompat.ACTION_SET_REPEAT_MODE

        val state = when {
            isBuffering -> PlaybackStateCompat.STATE_BUFFERING
            isPlaying -> PlaybackStateCompat.STATE_PLAYING
            else -> PlaybackStateCompat.STATE_PAUSED
        }

        return PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(
                state,
                positionMs,
                if (state == PlaybackStateCompat.STATE_PLAYING) 1f else 0f,
                if (positionUpdatedAt > 0) positionUpdatedAt else SystemClock.elapsedRealtime()
            )
            .build()
    }

    private fun sessionActivityIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_NOW_PLAYING, true)
        }
        return PendingIntent.getActivity(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun dispatch(action: String, value: Long?) {
        val target = sink
        if (target == null) {
            release()
            return
        }
        target.onCommand(action, value)
    }

    @Synchronized
    fun handleAction(action: String?) {
        when (action) {
            ACTION_PLAY -> dispatch(CMD_PLAY, null)
            ACTION_PAUSE -> dispatch(CMD_PAUSE, null)
            ACTION_NEXT -> dispatch(CMD_NEXT, null)
            ACTION_PREVIOUS -> dispatch(CMD_PREVIOUS, null)
            ACTION_STOP -> dispatch(CMD_STOP, null)
        }
    }

    @Synchronized
    fun onServiceStarted(startedService: Service) {
        service = startedService
        if (!active) {
            stopService()
            return
        }
        notifiedSignature = notificationSignature()
        pushNotification(startedService)
    }

    @Synchronized
    fun onServiceDestroyed(destroyedService: Service) {
        if (service === destroyedService) {
            service = null
            foregroundStarted = false
        }
    }

    @Synchronized
    fun onTaskRemoved() = release()

    private fun updateNotification() {
        val context = appContext ?: return
        if (!active) {
            stopService()
            return
        }
        val signature = notificationSignature()

        val running = service
        if (running == null) {
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, SyncMMediaService::class.java)
                )
            } catch (e: Exception) {
                Log.w(TAG, "Foreground-сервис не стартовал: $e")
                notifiedSignature = signature
                buildNotification(context)?.let { notifyCompat(context, it) }
            }
            return
        }
        if (signature == notifiedSignature) return
        notifiedSignature = signature
        pushNotification(running)
    }

    private fun notificationSignature(): String =
        "$title $artist $isPlaying $isBuffering " +
            "${artwork?.hashCode() ?: 0} $foregroundStarted"

    private fun pushNotification(target: Service) {
        val notification = buildNotification(target) ?: return
        if (isPlaying) {
            if (foregroundStarted) {
                notifyCompat(target, notification)
            } else {
                startForegroundCompat(target, notification)
            }
        } else {
            if (foregroundStarted) {
                try {
                    ServiceCompat.stopForeground(target, ServiceCompat.STOP_FOREGROUND_DETACH)
                } catch (_: Exception) {
                }
                foregroundStarted = false
            }
            notifyCompat(target, notification)
        }
    }

    private fun startForegroundCompat(target: Service, notification: Notification) {
        try {
            ServiceCompat.startForeground(
                target,
                NOTIFICATION_ID,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                else 0
            )
            foregroundStarted = true
        } catch (e: Exception) {
            Log.w(TAG, "startForeground отклонён: $e")
            foregroundStarted = false
            notifyCompat(target, notification)
            try {
                target.stopSelf()
            } catch (_: Exception) {
            }
        }
    }

    private fun notifyCompat(context: Context, notification: Notification) {
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Уведомление не показано: $e")
        }
    }

    private fun stopService() {
        val running = service
        if (running != null) {
            try {
                ServiceCompat.stopForeground(running, ServiceCompat.STOP_FOREGROUND_REMOVE)
            } catch (_: Exception) {
            }
            try {
                running.stopSelf()
            } catch (_: Exception) {
            }
        }
        foregroundStarted = false
        notifiedSignature = null
        appContext?.let {
            try {
                NotificationManagerCompat.from(it).cancel(NOTIFICATION_ID)
            } catch (_: Exception) {
            }
        }
    }

    private fun buildNotification(context: Context): Notification? {
        val current = session ?: return null
        ensureChannel(context)

        val playPause = if (isPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                actionIntent(context, ACTION_PAUSE)
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Play",
                actionIntent(context, ACTION_PLAY)
            )
        }

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_media_notification)
            .setContentTitle(title)
            .setContentText(artist)
            .setLargeIcon(artwork)
            .setContentIntent(current.controller.sessionActivity)
            .setDeleteIntent(actionIntent(context, ACTION_STOP))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(isPlaying)
            .addAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                actionIntent(context, ACTION_PREVIOUS)
            )
            .addAction(playPause)
            .addAction(
                android.R.drawable.ic_media_next,
                "Next",
                actionIntent(context, ACTION_NEXT)
            )
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(current.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
                    .setShowCancelButton(true)
                    .setCancelButtonIntent(actionIntent(context, ACTION_STOP))
            )
            .build()
    }

    private fun actionIntent(context: Context, action: String): PendingIntent {
        val intent = Intent(action).setComponent(
            ComponentName(context, MediaActionReceiver::class.java)
        )
        return PendingIntent.getBroadcast(
            context,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureChannel(context: Context) {
        if (channelReady) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            try {
                manager.deleteNotificationChannel(ABANDONED_CHANNEL_ID)
            } catch (_: Exception) {
            }
            val channel = NotificationChannel(
                CHANNEL_ID,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = channelDescription
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(false)
                enableLights(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
        channelReady = true
    }

    private fun decodeArtwork(bytes: ByteArray): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)

        var sample = 1
        val largest = maxOf(bounds.outWidth, bounds.outHeight)
        while (largest / sample > ARTWORK_MAX_PX) sample *= 2

        BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample }
        )
    } catch (e: Exception) {
        Log.w(TAG, "Обложку не удалось декодировать: $e")
        null
    }
}
