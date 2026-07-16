// android/app/src/main/kotlin/com/helix/local/MainActivity.kt
package com.helix.local

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity for Helix Local.
 *
 * Registers the "com.helix.local/foreground" method channel so that the
 * Dart layer can start/stop/update [HelixForegroundService].
 *
 * Also provides a static hook ([notifyTaskRemoved]) that the service calls
 * when the user removes the task from recents, so Flutter can cleanly end
 * the session.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL         = "com.helix.local/foreground"
        private const val MDNS_CHANNEL    = "com.helix.local/mdns"
        private const val MDNS_EVT_CHANNEL = "com.helix.local/mdns/events"

        // Nullable static — only valid while the activity is alive.
        private var _channel: MethodChannel? = null

        /**
         * Called by [HelixForegroundService.onTaskRemoved] to let the
         * Dart layer know the user has swiped the app away.
         */
        fun notifyTaskRemoved() {
            _channel?.invokeMethod("onTaskRemoved", null)
        }
    }

    private lateinit var mdnsService: HelixMdnsService
    private var multicastLock: android.net.wifi.WifiManager.MulticastLock? = null

    // ── FlutterActivity ────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Foreground service channel ────────────────────────────────────
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        _channel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val inCall = call.argument<Boolean>("inCall") ?: false
                    startForegroundService(inCall, result)
                }
                "stopService" -> {
                    stopForegroundService(result)
                }
                "updateNotificationText" -> {
                    val text = call.argument<String>("text")
                        ?: "Secure local messaging session running"
                    val inCall = call.argument<Boolean>("inCall") ?: false
                    updateNotificationText(text, inCall, result)
                }
                "canUseFullScreenIntent" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(NOTIFICATION_SERVICE)
                                 as android.app.NotificationManager
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        result.success(true)
                    }
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val intent = Intent(
                            android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                        ).apply { data = Uri.parse("package:$packageName") }
                        startActivity(intent)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── mDNS method + event channels ─────────────────────────────────
        mdnsService = HelixMdnsService(applicationContext)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MDNS_EVT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                mdnsService.setEventSink(sink)
            }
            override fun onCancel(args: Any?) {
                mdnsService.setEventSink(null)
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MDNS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            try {
                when (call.method) {
                    "start" -> {
                        mdnsService.start(args)
                        result.success(null)
                    }
                    "stop" -> {
                        mdnsService.stop()
                        result.success(null)
                    }
                    "updateDiscoverability" -> {
                        mdnsService.updateDiscoverability(args)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                Log.w("HelixMdns", "${call.method} failed", t)
                result.error("mdns_failed", t.message, null)
            }
        }

        // ── Multicast lock channel ────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.helix.local/multicast_lock",
        ).setMethodCallHandler { call, result ->
            try {
                val wifi = applicationContext.getSystemService(android.content.Context.WIFI_SERVICE)
                           as android.net.wifi.WifiManager
                when (call.method) {
                    "acquire" -> {
                        if (multicastLock == null) {
                            multicastLock = wifi.createMulticastLock("helix_lobby")
                            multicastLock!!.setReferenceCounted(false)
                        }
                        multicastLock!!.acquire()
                        result.success(null)
                    }
                    "release" -> {
                        multicastLock?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                Log.w("HelixMulticast", "${call.method} failed", t)
                result.error("multicast_lock_failed", t.message, null)
            }
        }
    }

    override fun onDestroy() {
        try {
            if (::mdnsService.isInitialized) {
                mdnsService.stop()
            }
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (t: Throwable) {
            Log.w("HelixMain", "onDestroy cleanup failed", t)
        }
        _channel = null
        super.onDestroy()
    }

    // ── Private helpers ────────────────────────────────────────────────────

    private fun startForegroundService(inCall: Boolean, result: MethodChannel.Result) {
        val intent = Intent(this, HelixForegroundService::class.java).apply {
            putExtra(HelixForegroundService.EXTRA_IN_CALL, inCall)
        }
        startServiceSafely(intent, result, "startService")
    }

    private fun stopForegroundService(result: MethodChannel.Result) {
        val intent = Intent(this, HelixForegroundService::class.java)
        try {
            stopService(intent)
            result.success(null)
        } catch (t: Throwable) {
            Log.w("HelixForeground", "stopService failed", t)
            result.error("foreground_service_stop_failed", t.message, null)
        }
    }

    private fun updateNotificationText(text: String, inCall: Boolean, result: MethodChannel.Result) {
        val intent = Intent(this, HelixForegroundService::class.java).apply {
            putExtra(HelixForegroundService.EXTRA_NOTIFICATION_TEXT, text)
            putExtra(HelixForegroundService.EXTRA_IN_CALL, inCall)
        }
        startServiceSafely(intent, result, "updateNotificationText")
    }

    private fun startServiceSafely(
        intent: Intent,
        result: MethodChannel.Result,
        operation: String,
    ) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(null)
        } catch (t: Throwable) {
            Log.w("HelixForeground", "$operation failed", t)
            result.error("foreground_service_start_failed", t.message, null)
        }
    }
}
