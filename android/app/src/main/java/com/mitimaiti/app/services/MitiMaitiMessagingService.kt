package com.mitimaiti.app.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.mitimaiti.app.MainActivity
import com.mitimaiti.app.R

/**
 * Receives FCM pushes from the backend (services/notifications.ts).
 * The backend sends both a notification payload (title/body) and a data
 * payload ({ type, matchId, ... }) — we always render locally from the data
 * so foreground messages show too, and taps deep-link into the right chat.
 */
class MitiMaitiMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        // Fires on install, token rotation, and restore — keep the backend current
        FcmTokenRegistrar.register(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title
            ?: message.data["title"]
            ?: "MitiMaiti"
        val body = message.notification?.body
            ?: message.data["body"]
            ?: "You have a new notification"
        val type = message.data["type"] ?: ""
        val matchId = message.data["matchId"]

        val channelId = if (type in SAFETY_TYPES) CHANNEL_SAFETY else CHANNEL_DEFAULT

        // Tap → open the app; carry the matchId so MainActivity can jump
        // straight into that conversation.
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (matchId != null) putExtra(EXTRA_MATCH_ID, matchId)
            putExtra(EXTRA_NOTIFICATION_TYPE, type)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            (matchId ?: type).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val granted = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(
            this, android.Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) return

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify((matchId ?: type).hashCode(), notification)
    }

    companion object {
        const val CHANNEL_DEFAULT = "default"
        const val CHANNEL_SAFETY = "safety"
        const val EXTRA_MATCH_ID = "matchId"
        const val EXTRA_NOTIFICATION_TYPE = "notificationType"

        private val SAFETY_TYPES = setOf("safety_alert", "account_warning", "report_update")

        /** Create the channels the backend targets (channelId 'default'/'safety'). */
        fun createChannels(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_DEFAULT,
                    "Matches & Messages",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "New matches, messages, and likes" }
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_SAFETY,
                    "Safety",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "Safety alerts and account notices" }
            )
        }
    }
}
