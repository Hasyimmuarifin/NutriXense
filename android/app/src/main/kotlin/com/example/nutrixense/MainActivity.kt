package com.example.nutrixense

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.nutrixense/alerts"
    private val notificationChannelId = "nutrixense_threshold_alerts"
    private val notificationPermissionRequestCode = 4102

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()
        requestNotificationPermissionIfNeeded()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeAlerts" -> {
                    createNotificationChannel()
                    requestNotificationPermissionIfNeeded()
                    result.success(null)
                }

                "showNutrientAlert" -> {
                    val title = call.argument<String>("title") ?: "Nutrient threshold alert"
                    val message = call.argument<String>("message") ?: "A sensor reading is out of range."

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

                else -> result.notImplemented()
            }
        }
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
            "Nutrient Threshold Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts when plant nutrition readings leave the configured thresholds."
            enableVibration(true)
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

        val notification = builder
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setContentTitle(title)
            .setContentText(message.lines().firstOrNull() ?: message)
            .setStyle(android.app.Notification.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 350, 150, 350))
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
    }
}
