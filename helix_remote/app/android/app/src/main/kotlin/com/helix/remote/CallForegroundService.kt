package com.helix.remote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val caller = intent.getStringExtra(EXTRA_CALLER) ?: "Unknown caller"
                val isVideo = intent.getBooleanExtra(EXTRA_IS_VIDEO, false)
                startForeground(NOTIFICATION_ID, buildNotification(caller, isVideo))
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(caller: String, isVideo: Boolean): Notification {
        ensureChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )
        val title = if (isVideo) "Video call in progress" else "Audio call in progress"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(caller)
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Active Calls",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing Helix Remote call controls"
            }
        )
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun pendingIntentImmutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    companion object {
        const val CHANNEL_ID = "helix_active_calls"
        const val NOTIFICATION_ID = 121716
        private const val ACTION_START = "com.helix.remote.calls.START_FOREGROUND"
        private const val ACTION_STOP = "com.helix.remote.calls.STOP_FOREGROUND"
        private const val EXTRA_CALLER = "caller"
        private const val EXTRA_IS_VIDEO = "is_video"

        fun startIntent(context: Context, caller: String, isVideo: Boolean): Intent =
            Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CALLER, caller)
                putExtra(EXTRA_IS_VIDEO, isVideo)
            }

        fun stopIntent(context: Context): Intent =
            Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_STOP
            }
    }
}
