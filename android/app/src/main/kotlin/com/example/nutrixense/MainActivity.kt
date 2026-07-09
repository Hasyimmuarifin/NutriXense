package com.example.nutrixense

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.nutrixense/alerts"
    private val notificationChannelId = "nutrixense_threshold_alerts"
    private val fcmNotificationChannelId = "nutrixense_fcm_alerts"
    private val notificationPermissionRequestCode = 4102
    private val alertGroupKey = "com.example.nutrixense.ALERT_NOTIFICATIONS"
    private val alertGroupSummaryId = 4199
    private val notificationColor = Color.rgb(46, 125, 50)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()
        createFcmNotificationChannel()
        requestNotificationPermissionIfNeeded()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeAlerts" -> {
                    createNotificationChannel()
                    createFcmNotificationChannel()
                    requestNotificationPermissionIfNeeded()
                    result.success(null)
                }

                "showNutrientAlert" -> {
                    val title = call.argument<String>("title") ?: "Peringatan Nutrisi Tanaman"
                    val message = call.argument<String>("message") ?: "Pembacaan sensor berada di luar ambang batas normal."

                    showThresholdAlert(title, message)
                    result.success(null)
                }

                "startBackgroundMonitor" -> {
                    val thresholdsJson = call.argument<String>("thresholdsJson")
                    startBackgroundMonitor(thresholdsJson)
                    result.success(null)
                }

                "startBackgroundAlertMonitor" -> {
                    val thresholdsJson = call.argument<String>("thresholdsJson")
                    startBackgroundAlertMonitor(thresholdsJson)
                    result.success(null)
                }

                "stopBackgroundAlertMonitor" -> {
                    stopBackgroundAlertMonitor()
                    result.success(null)
                }

                "stopBackgroundMonitor" -> {
                    stopBackgroundMonitor()
                    result.success(null)
                }

                "syncBackgroundThresholds" -> {
                    val thresholdsJson = call.argument<String>("thresholdsJson")
                    syncBackgroundThresholds(thresholdsJson)
                    result.success(null)
                }

                "syncBackgroundSchedules" -> {
                    val schedulesJson = call.argument<String>("schedulesJson")
                    syncBackgroundSchedules(schedulesJson)
                    result.success(null)
                }

                "isBackgroundMonitorRunning" -> {
                    result.success(NutrixenseBackgroundService.isServiceRunning)
                }

                "saveFileToDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")

                    if (fileName.isNullOrBlank() || bytes == null) {
                        result.error("INVALID_ARGUMENT", "fileName and bytes are required.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(saveFileToDownloads(fileName, mimeType, bytes))
                    } catch (error: Exception) {
                        result.error("SAVE_FAILED", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveFileToDownloads(
        fileName: String,
        mimeType: String,
        bytes: ByteArray
    ): String {
        val publicPath = "/storage/emulated/0/Download/$fileName"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create Downloads file.")

            resolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
            } ?: throw IllegalStateException("Unable to open Downloads file.")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            return publicPath
        }

        @Suppress("DEPRECATION")
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        if (!downloadsDir.exists()) {
            downloadsDir.mkdirs()
        }

        val file = File(downloadsDir, fileName)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return

        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            notificationChannelId,
            "Peringatan Nutrisi Tanaman",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Memberi peringatan saat pembacaan nutrisi tanaman keluar dari ambang batas normal yang dikonfigurasi."
            enableVibration(true)
            setShowBadge(true)
            setSound(soundUri, audioAttributes)
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun createFcmNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            fcmNotificationChannelId,
            "Notifikasi Push NutriXense",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifikasi push yang dikirim melalui Firebase Cloud Messaging."
            enableVibration(true)
            setShowBadge(true)
            setSound(soundUri, audioAttributes)
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun startBackgroundMonitor(thresholdsJson: String?) {
        val intent = Intent(this, NutrixenseBackgroundService::class.java).apply {
            action = NutrixenseBackgroundService.ACTION_START
            putExtra(NutrixenseBackgroundService.EXTRA_THRESHOLDS_JSON, thresholdsJson)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun startBackgroundAlertMonitor(thresholdsJson: String?) {
        val intent = Intent(this, NutrixenseBackgroundService::class.java).apply {
            action = NutrixenseBackgroundService.ACTION_START_ALERT_MONITOR
            putExtra(NutrixenseBackgroundService.EXTRA_THRESHOLDS_JSON, thresholdsJson)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopBackgroundAlertMonitor() {
        val intent = Intent(this, NutrixenseBackgroundService::class.java).apply {
            action = NutrixenseBackgroundService.ACTION_STOP_ALERT_MONITOR
        }
        startService(intent)
    }

    private fun stopBackgroundMonitor() {
        val intent = Intent(this, NutrixenseBackgroundService::class.java).apply {
            action = NutrixenseBackgroundService.ACTION_STOP
        }
        startService(intent)
    }

    private fun syncBackgroundThresholds(thresholdsJson: String?) {
        NutrixenseBackgroundService.storeThresholds(this, thresholdsJson)
        if (!NutrixenseBackgroundService.isServiceRunning) return

        val intent = Intent(this, NutrixenseBackgroundService::class.java).apply {
            action = NutrixenseBackgroundService.ACTION_SYNC_THRESHOLDS
            putExtra(NutrixenseBackgroundService.EXTRA_THRESHOLDS_JSON, thresholdsJson)
        }
        startService(intent)
    }

    private fun syncBackgroundSchedules(schedulesJson: String?) {
        NutrixenseBackgroundService.storeSchedules(this, schedulesJson)

        val intent = Intent(this, NutrixenseBackgroundService::class.java).apply {
            action = NutrixenseBackgroundService.ACTION_SYNC_SCHEDULES
            putExtra(NutrixenseBackgroundService.EXTRA_SCHEDULES_JSON, schedulesJson)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            NutrixenseBackgroundService.hasEnabledSchedules(this)
        ) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun showThresholdAlert(title: String, message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermissionIfNeeded()
            return
        }

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

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
                .setPriority(android.app.Notification.PRIORITY_HIGH)
                .setDefaults(android.app.Notification.DEFAULT_SOUND or android.app.Notification.DEFAULT_VIBRATE)
        }

        val notification = withBadgeIcon(withGroupAlertBehavior(builder))
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setLargeIcon(notificationLargeIcon())
            .setColor(notificationColor)
            .setNumber(1)
            .setContentTitle(title)
            .setContentText(message.lines().firstOrNull() ?: message)
            .setStyle(android.app.Notification.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setGroup(alertGroupKey)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 350, 150, 350))
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
        showAlertGroupSummary(manager, pendingIntent)
    }

    private fun showAlertGroupSummary(
        manager: NotificationManager,
        pendingIntent: PendingIntent
    ) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setPriority(Notification.PRIORITY_HIGH)
        }

        val notification = withBadgeIcon(withGroupAlertBehavior(builder))
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setLargeIcon(notificationLargeIcon())
            .setColor(notificationColor)
            .setNumber(1)
            .setContentTitle("Peringatan NutriXense")
            .setContentText("Buka aplikasi untuk melihat semua peringatan terbaru.")
            .setStyle(
                Notification.InboxStyle()
                    .setSummaryText("Peringatan NutriXense")
                    .addLine("Ada beberapa notifikasi peringatan nutrisi.")
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setGroup(alertGroupKey)
            .setGroupSummary(true)
            .build()

        manager.notify(alertGroupSummaryId, notification)
    }

    private fun withGroupAlertBehavior(builder: Notification.Builder): Notification.Builder {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
        }
        return builder
    }

    private fun withBadgeIcon(builder: Notification.Builder): Notification.Builder {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setBadgeIconType(Notification.BADGE_ICON_LARGE)
        }
        return builder
    }

    private fun notificationLargeIcon(): Bitmap? {
        return BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
    }
}
