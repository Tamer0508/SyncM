package com.example.syncm.media

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MediaSessionChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, MediaCommandSink {

    companion object {
        const val CHANNEL = "syncm/media_session"
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    private var ready = false
    private var pendingOpenNowPlaying = false
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    fun requestOpenNowPlaying() {
        pendingOpenNowPlaying = true
        flushOpenRequest()
    }

    private fun flushOpenRequest() {
        if (disposed || !ready || !pendingOpenNowPlaying) return
        pendingOpenNowPlaying = false
        main.post {
            if (!disposed) channel.invokeMethod("openNowPlaying", null)
        }
    }

    fun dispose() {
        disposed = true
        ready = false
        channel.setMethodCallHandler(null)
        MediaSessionController.detach(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                MediaSessionController.attach(
                    appContext,
                    this,
                    call.argument("channelName"),
                    call.argument("channelDescription"),
                )
                ready = true
                flushOpenRequest()
                result.success(true)
            }

            "setTrack" -> {
                MediaSessionController.updateTrack(
                    call.argument<String>("trackId"),
                    call.argument<String>("title") ?: "",
                    call.argument<String>("artist") ?: "",
                    call.argument<String>("album") ?: "",
                    longArg(call, "durationMs"),
                )
                result.success(null)
            }

            "setArtwork" -> {
                MediaSessionController.updateArtwork(
                    call.argument<String>("trackId"),
                    call.argument<ByteArray>("bytes"),
                )
                result.success(null)
            }

            "setPlaybackState" -> {
                MediaSessionController.updatePlayback(
                    call.argument<Boolean>("isPlaying") ?: false,
                    call.argument<Boolean>("buffering") ?: false,
                    longArg(call, "positionMs"),
                    longArg(call, "durationMs"),
                    call.argument<Boolean>("shuffle") ?: false,
                    call.argument<String>("repeat") ?: "off",
                )
                result.success(null)
            }

            "release" -> {
                MediaSessionController.release()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun longArg(call: MethodCall, name: String): Long =
        (call.argument<Number>(name))?.toLong() ?: 0L

    override fun onCommand(action: String, value: Long?) {
        if (disposed) return
        main.post {
            if (disposed) return@post
            channel.invokeMethod(
                "command",
                mapOf("action" to action, "value" to value),
            )
        }
    }
}
