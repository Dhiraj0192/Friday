package com.privateagent.private_agent

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * Keeps Friday's process, and with it her cached Flutter engine, alive after
 * Sir swipes the app away or the phone restarts, so the agent keeps running.
 */
class FridayKeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                standbyNotification(),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not go foreground: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        // After a reboot, or when Android killed the process, no engine exists:
        // start Friday out of sight so her Dart side and channels come back.
        if (FlutterEngineCache.getInstance().get(MainActivity.ENGINE_ID) == null) {
            try {
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        .putExtra(MainActivity.EXTRA_START_HIDDEN, true)
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not start Friday in the background: ${e.message}")
            }
        }
        return START_STICKY
    }

    private fun standbyNotification(): android.app.Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Friday standing by", NotificationManager.IMPORTANCE_MIN)
                    .apply { description = "Keeps Friday running in the background." }
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Friday is standing by")
            .setContentText("Ready on your phone, Sir.")
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val TAG = "FridayKeepAlive"
        private const val CHANNEL_ID = "friday_standby"
        private const val NOTIFICATION_ID = 4107

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, FridayKeepAliveService::class.java)
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not start the keep-alive service: ${e.message}")
            }
        }
    }
}
