package com.motovoice.moto_assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import androidx.core.content.ContextCompat

class WakeWordService : Service() {
    companion object {
        private const val TAG = "WakeWordService"
        private const val CHANNEL_ID = "wakeword"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "com.motovoice.moto_assistant.STOP_RIDING_MODE"

        var isRunning = false
            private set

        // Throws ForegroundServiceStartNotAllowedException if called while the app is in the background.
        fun start(context: Context) =
            ContextCompat.startForegroundService(context, Intent(context, WakeWordService::class.java))

        fun stop(context: Context) = context.stopService(Intent(context, WakeWordService::class.java))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } catch (e: Exception) {
            // Android 14+ refuses a mic service without RECORD_AUDIO or when not started from the foreground.
            Log.e(TAG, "startForeground failed: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        isRunning = true
        MotoEngine.detector?.start()
        MotoEngine.notifyRidingMode(true)
        // ponytail: not sticky — if Android kills the process, riding mode ends until the app is reopened.
        // Restarting headless would need Dart to boot without an activity (permission prompts would fail).
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        MotoEngine.detector?.pause()
        MotoEngine.notifyRidingMode(false)
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Hey Jarvis listening", NotificationManager.IMPORTANCE_LOW)
        )
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, WakeWordService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("MotoVoice riding mode")
            .setContentText("Listening for \"Hey Jarvis\"")
            .setOngoing(true)
            .setContentIntent(openApp)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }
}
