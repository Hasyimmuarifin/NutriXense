package com.example.nutrixense

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class NutrixenseFirebaseMessagingService : FirebaseMessagingService() {
    companion object {
        private const val ALERT_CHANNEL_ID = "nutrixense_threshold_alerts"
        private const val FCM_CHANNEL_ID = "nutrixense_fcm_alerts"
        private const val ALERT_GROUP_KEY = "com.example.nutrixense.ALERT_NOTIFICATIONS"
        private const val ALERT_GROUP_SUMMARY_ID = 4199
        private const val ALERT_NOTIFICATION_BASE_ID = 4200
        private const val ALERT_CHILD_LIMIT = 15
        private const val ALERT_WINDOW_MILLIS = 60 * 60 * 1000L
        private const val NOTIFICATION_STATE_PREFS_NAME = "nutrixense_notification_state"
        private const val PREF_ALERT_TIMESTAMPS = "alert_timestamps"
        private const val PREF_NEXT_ALERT_SLOT = "next_alert_slot"
        private const val PREF_DISPLAYED_ALERT_KEYS = "displayed_alert_keys"
    }

    private val notificationColor = Color.rgb(46, 125, 50)

    override fun onMessageReceived(message: RemoteMessage) {
        val type = message.data["type"]
        if (type != "threshold_alert") return

        createNotificationChannels()

        val title = message.data["title"] ?: "Peringatan Nutrisi Tanaman"
        val summaryBody = message.data["body"]
            ?: message.data["message"]
            ?: "Pembacaan sensor berada di luar ambang batas normal."
        val detailBody = message.data["detailBody"]
            ?.takeIf { it.isNotBlank() }
            ?: summaryBody
        val recentAlertCount = message.data["recentAlertCount"]?.toIntOrNull()
        val notificationKey = message.data["notificationKey"] ?: message.data["logId"]

        showThresholdAlert(
            title = title,
            message = detailBody,
            providedRecentAlertCount = recentAlertCount,
            notificationKey = notificationKey,
        )
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "Peringatan Nutrisi Tanaman",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Memberi peringatan saat pembacaan nutrisi tanaman keluar dari ambang batas normal yang dikonfigurasi."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                FCM_CHANNEL_ID,
                "Notifikasi Push NutriXense",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi push yang dikirim melalui Firebase Cloud Messaging."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            }
        )
    }

    private fun showThresholdAlert(
        title: String,
        message: String,
        providedRecentAlertCount: Int?,
        notificationKey: String?,
    ) {
        if (shouldSkipDuplicateNotification(notificationKey)) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val currentAlertCount = countAlertLines(message)
        val recentAlertCount = providedRecentAlertCount ?: recordRecentAlerts(currentAlertCount)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
        }

        val notification = withBadgeIcon(withGroupAlertBehavior(builder))
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setColor(notificationColor)
            .setNumber(currentAlertCount)
            .setContentTitle(title)
            .setContentText(firstAlertLine(message))
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setGroup(ALERT_GROUP_KEY)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 350, 150, 350))
            .build()

        manager.notify(nextAlertChildNotificationId(), notification)
        showAlertGroupSummary(manager, pendingIntent, recentAlertCount)
    }

    private fun showAlertGroupSummary(
        manager: NotificationManager,
        pendingIntent: PendingIntent,
        recentAlertCount: Int,
    ) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setPriority(Notification.PRIORITY_HIGH)
        }

        val summaryText = alertSummaryText(recentAlertCount)
        val notification = withBadgeIcon(withGroupAlertBehavior(builder))
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setColor(notificationColor)
            .setNumber(recentAlertCount)
            .setContentTitle("Peringatan NutriXense")
            .setContentText(summaryText)
            .setStyle(
                Notification.InboxStyle()
                    .setSummaryText("Peringatan NutriXense")
                    .addLine(summaryText)
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setGroup(ALERT_GROUP_KEY)
            .setGroupSummary(true)
            .build()

        manager.notify(ALERT_GROUP_SUMMARY_ID, notification)
    }

    private fun withGroupAlertBehavior(builder: Notification.Builder): Notification.Builder {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
        }
        return builder
    }

    private fun withBadgeIcon(builder: Notification.Builder): Notification.Builder {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setBadgeIconType(Notification.BADGE_ICON_SMALL)
        }
        return builder
    }

    private fun firstAlertLine(message: String): String {
        return message.lines().firstOrNull { it.isNotBlank() } ?: message
    }

    private fun countAlertLines(message: String): Int {
        return message.lines().count { it.isNotBlank() }.coerceAtLeast(1)
    }

    private fun alertSummaryText(recentAlertCount: Int): String {
        return "$recentAlertCount peringatan nutrisi terdeteksi dalam 1 jam terakhir. Buka halaman Logs untuk melihat detail."
    }

    private fun nextAlertChildNotificationId(): Int {
        val prefs = getSharedPreferences(NOTIFICATION_STATE_PREFS_NAME, Context.MODE_PRIVATE)
        val slot = prefs.getInt(PREF_NEXT_ALERT_SLOT, 0).coerceIn(0, ALERT_CHILD_LIMIT - 1)
        prefs.edit()
            .putInt(PREF_NEXT_ALERT_SLOT, (slot + 1) % ALERT_CHILD_LIMIT)
            .apply()
        return ALERT_NOTIFICATION_BASE_ID + slot
    }

    private fun recordRecentAlerts(alertCount: Int): Int {
        val now = System.currentTimeMillis()
        val prefs = getSharedPreferences(NOTIFICATION_STATE_PREFS_NAME, Context.MODE_PRIVATE)
        val retained = prefs.getString(PREF_ALERT_TIMESTAMPS, "")
            .orEmpty()
            .split(',')
            .mapNotNull { it.toLongOrNull() }
            .filter { now - it <= ALERT_WINDOW_MILLIS }
            .toMutableList()

        repeat(alertCount.coerceAtLeast(1)) {
            retained.add(now)
        }

        val capped = retained.takeLast(300)
        prefs.edit()
            .putString(PREF_ALERT_TIMESTAMPS, capped.joinToString(","))
            .apply()

        return capped.size
    }

    private fun shouldSkipDuplicateNotification(notificationKey: String?): Boolean {
        val key = notificationKey?.takeIf { it.isNotBlank() } ?: return false
        val prefs = getSharedPreferences(NOTIFICATION_STATE_PREFS_NAME, Context.MODE_PRIVATE)
        val displayedKeys = prefs.getString(PREF_DISPLAYED_ALERT_KEYS, "")
            .orEmpty()
            .split(',')
            .filter { it.isNotBlank() }

        if (displayedKeys.contains(key)) return true

        val capped = (displayedKeys + key).takeLast(100)
        prefs.edit()
            .putString(PREF_DISPLAYED_ALERT_KEYS, capped.joinToString(","))
            .apply()

        return false
    }
}
