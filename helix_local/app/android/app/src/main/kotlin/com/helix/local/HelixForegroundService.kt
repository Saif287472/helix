// android/app/src/main/kotlin/com/helix/local/HelixForegroundService.kt
package com.helix.local

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Persistent foreground service that keeps the Helix session alive when
 * the app is backgrounded on Android.
 *
 * Foreground service type: connectedDevice (Android 14+ requirement for
 * services that maintain local-network connections).
 *
 * The service is NOT auto-restarted after it is killed (START_NOT_STICKY).
 * When the task is removed from the recents screen the service stops itself
 * and notifies the Flutter layer via the method channel so the session can
 * be cleanly torn down.
 */
class HelixForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "helix_session_channel"
        const val CHANNEL_NAME = "Helix Session"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.helix.local.ACTION_STOP"
        const val EXTRA_NOTIFICATION_TEXT = "notification_text"
        const val EXTRA_IN_CALL = "in_call"
    }

    // ── Service lifecycle ──────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                MainActivity.notifyTaskRemoved()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        createNotificationChannel()

        val notificationText = intent?.getStringExtra(EXTRA_NOTIFICATION_TEXT)
            ?: "Secure local messaging session running"
        val inCall = intent?.getBooleanExtra(EXTRA_IN_CALL, false) ?: false

        val notification = buildNotification(notificationText)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            var type = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            if (inCall) {
                val hasMicPermission = androidx.core.content.ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.RECORD_AUDIO
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                if (hasMicPermission) {
                    type = type or android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Called when the user swipes the app away from the recents screen.
     * Stops the service so the notification disappears and notifies Flutter
     * that the session should be terminated.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)

        // Notify Flutter layer — MainActivity's method channel handler will
        // trigger session cleanup in Dart.
        MainActivity.notifyTaskRemoved()

        stopSelf()
    }

    // ── Private helpers ────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW // low = no sound/vibration
            ).apply {
                description = "Keeps the Helix session active in the background"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(contentText: String): android.app.Notification {
        // Tap the notification → re-opens the app
        val openIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) }

        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "Stop Helix" action in the notification drawer
        val stopIntent = Intent(this, HelixForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Helix is active")
            .setContentText(contentText)
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop Helix",
                stopPendingIntent
            )
            .build()
    }
}
