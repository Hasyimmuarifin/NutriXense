package com.example.nutrixense

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.MqttAsyncClient
import org.eclipse.paho.client.mqttv3.MqttCallbackExtended
import org.eclipse.paho.client.mqttv3.MqttConnectOptions
import org.eclipse.paho.client.mqttv3.MqttMessage
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class NutrixenseBackgroundService : Service() {
    companion object {
        const val ACTION_START = "com.example.nutrixense.background.START"
        const val ACTION_START_ALERT_MONITOR =
            "com.example.nutrixense.background.START_ALERT_MONITOR"
        const val ACTION_STOP_ALERT_MONITOR =
            "com.example.nutrixense.background.STOP_ALERT_MONITOR"
        const val ACTION_STOP = "com.example.nutrixense.background.STOP"
        const val ACTION_SYNC_THRESHOLDS = "com.example.nutrixense.background.SYNC_THRESHOLDS"
        const val ACTION_SYNC_SCHEDULES = "com.example.nutrixense.background.SYNC_SCHEDULES"
        const val EXTRA_THRESHOLDS_JSON = "thresholds_json"
        const val EXTRA_SCHEDULES_JSON = "schedules_json"

        private const val PREFS_NAME = "nutrixense_background_monitor"
        private const val PREF_ENABLED = "enabled"
        private const val PREF_ALERT_MONITOR_ENABLED = "alert_monitor_enabled"
        private const val PREF_THRESHOLDS = "thresholds_json"
        private const val PREF_SCHEDULES = "schedules_json"

        private const val MQTT_SERVER_URI =
            "ssl://a8805b4f45744c3f9ac83882e423e0c0.s1.eu.hivemq.cloud:8883"
        private const val MQTT_USERNAME = "hasyim"
        private const val MQTT_PASSWORD = "hasyimHiveMQTT@22"
        private const val SENSOR_TOPIC = "nutrixense/sensor"
        private const val CONTROL_TOPIC = "nutrixense/control"

        private const val FOREGROUND_NOTIFICATION_ID = 2201
        private const val ALERT_NOTIFICATION_BASE_ID = 4200
        private const val MONITOR_CHANNEL_ID = "nutrixense_background_monitor"
        private const val ALERT_CHANNEL_ID = "nutrixense_threshold_alerts"

        @Volatile
        var isServiceRunning: Boolean = false
            private set

        fun setEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREF_ENABLED, enabled)
                .apply()
        }

        fun isEnabled(context: Context): Boolean {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREF_ENABLED, false)
        }

        fun setAlertMonitorEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREF_ALERT_MONITOR_ENABLED, enabled)
                .apply()
        }

        fun isAlertMonitorEnabled(context: Context): Boolean {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREF_ALERT_MONITOR_ENABLED, false)
        }

        fun shouldKeepMonitoring(context: Context): Boolean {
            return isAlertMonitorEnabled(context) ||
                isEnabled(context) ||
                hasEnabledSchedules(context)
        }

        fun storeThresholds(context: Context, thresholdsJson: String?) {
            if (thresholdsJson.isNullOrBlank()) return

            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_THRESHOLDS, thresholdsJson)
                .apply()
        }

        fun storeSchedules(context: Context, schedulesJson: String?) {
            if (schedulesJson.isNullOrBlank()) return

            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_SCHEDULES, schedulesJson)
                .apply()
        }

        fun hasEnabledSchedules(context: Context): Boolean {
            val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(PREF_SCHEDULES, null)
                ?: return false

            return try {
                val array = JSONArray(raw)
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    if (item.optBoolean("enabled", true)) return true
                }
                false
            } catch (_: Exception) {
                false
            }
        }
    }

    private val executor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    private var ruleFuture: ScheduledFuture<*>? = null
    private var scheduleFuture: ScheduledFuture<*>? = null
    private var mqttClient: MqttAsyncClient? = null
    private var latestReading: SensorReading? = null
    private val schedules = mutableListOf<WateringSchedule>()
    private val thresholds = defaultThresholds().toMutableMap()
    private val mutedSensors = defaultMutedSensors().toMutableMap()
    private val lastAlertTimes = mutableMapOf<String, Long>()
    private val lastRelayActivationTimes = mutableMapOf<Int, Long>()
    private val lastScheduleRunDates = mutableMapOf<Long, String>()
    private val repeatAlertMillis = TimeUnit.MINUTES.toMillis(5)
    private val ruleIntervalMillis = TimeUnit.MINUTES.toMillis(1)

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        createNotificationChannels()
        loadStoredThresholds()
        loadStoredSchedules()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                setEnabled(this, false)
                if (shouldKeepMonitoring(this)) {
                    startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
                    startMonitor()
                } else {
                    stopMonitor()
                    stopSelf()
                }
                return START_NOT_STICKY
            }
            ACTION_START_ALERT_MONITOR -> {
                setAlertMonitorEnabled(this, true)
                updateThresholds(intent.getStringExtra(EXTRA_THRESHOLDS_JSON))
                startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
                startMonitor()
                return START_STICKY
            }
            ACTION_STOP_ALERT_MONITOR -> {
                setAlertMonitorEnabled(this, false)
                if (shouldKeepMonitoring(this)) {
                    startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
                    startMonitor()
                } else {
                    stopMonitor()
                    stopSelf()
                }
                return START_NOT_STICKY
            }
            ACTION_SYNC_THRESHOLDS -> {
                updateThresholds(intent.getStringExtra(EXTRA_THRESHOLDS_JSON))
                return START_STICKY
            }
            ACTION_SYNC_SCHEDULES -> {
                updateSchedules(intent.getStringExtra(EXTRA_SCHEDULES_JSON))
                if (isEnabled(this) || schedules.any { it.enabled }) {
                    startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
                    startMonitor()
                } else {
                    stopMonitor()
                    stopSelf()
                }
                return START_STICKY
            }
            ACTION_START -> {
                setEnabled(this, true)
                updateThresholds(intent?.getStringExtra(EXTRA_THRESHOLDS_JSON))
                startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
                startMonitor()
            }
            else -> {
                updateThresholds(null)
                if (shouldKeepMonitoring(this)) {
                    startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
                    startMonitor()
                } else {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopMonitor()
        isServiceRunning = false
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun startMonitor() {
        executor.execute { connectMqttIfNeeded() }
        if (isEnabled(this) && (ruleFuture == null || ruleFuture?.isCancelled == true)) {
            ruleFuture = executor.scheduleAtFixedRate(
                { runRuleBasedDecisionSupport() },
                1,
                1,
                TimeUnit.MINUTES
            )
        }
        if (scheduleFuture == null || scheduleFuture?.isCancelled == true) {
            scheduleFuture = executor.scheduleAtFixedRate(
                { runDueSchedules() },
                5,
                15,
                TimeUnit.SECONDS
            )
        }
    }

    private fun stopMonitor() {
        ruleFuture?.cancel(true)
        ruleFuture = null
        scheduleFuture?.cancel(true)
        scheduleFuture = null
        try {
            mqttClient?.disconnect()
        } catch (_: Exception) {
        }
        mqttClient = null
    }

    private fun connectMqttIfNeeded() {
        val existingClient = mqttClient
        if (existingClient?.isConnected == true) return

        val clientId = "android_background_${System.currentTimeMillis()}"
        val client = MqttAsyncClient(MQTT_SERVER_URI, clientId, MemoryPersistence())
        mqttClient = client

        client.setCallback(object : MqttCallbackExtended {
            override fun connectComplete(reconnect: Boolean, serverURI: String?) {
                subscribeToSensors()
            }

            override fun connectionLost(cause: Throwable?) {
            }

            override fun messageArrived(topic: String?, message: MqttMessage?) {
                if (topic == SENSOR_TOPIC && message != null) {
                    handleSensorMessage(String(message.payload))
                }
            }

            override fun deliveryComplete(token: IMqttDeliveryToken?) {
            }
        })

        val options = MqttConnectOptions().apply {
            userName = MQTT_USERNAME
            password = MQTT_PASSWORD.toCharArray()
            isAutomaticReconnect = true
            isCleanSession = false
            keepAliveInterval = 20
            connectionTimeout = 10
        }

        try {
            client.connect(options).waitForCompletion(10_000)
            subscribeToSensors()
        } catch (_: Exception) {
        }
    }

    private fun subscribeToSensors() {
        val client = mqttClient ?: return
        if (!client.isConnected) return

        try {
            client.subscribe(SENSOR_TOPIC, 0)
        } catch (_: Exception) {
        }
    }

    private fun handleSensorMessage(payload: String) {
        val reading = SensorReading.fromJson(payload) ?: return
        latestReading = reading
        handleThresholdAlerts(reading)
    }

    private fun handleThresholdAlerts(reading: SensorReading) {
        val alertLines = mutableListOf<String>()

        addAlertLine(alertLines, "nitrogen", "Nitrogen", reading.nitrogen, "mg/kg", "min_nitrogen", "max_nitrogen")
        addAlertLine(alertLines, "phosphorus", "Fosfor", reading.phosphorus, "mg/kg", "min_phosphorus", "max_phosphorus")
        addAlertLine(alertLines, "potassium", "Kalium", reading.potassium, "mg/kg", "min_potassium", "max_potassium")
        addAlertLine(alertLines, "ph", "pH", reading.ph, "pH", "min_ph", "max_ph")
        addAlertLine(alertLines, "moisture", "Kelembapan", reading.moisture, "%", "min_moisture", "max_moisture")
        addAlertLine(alertLines, "temperature", "Suhu", reading.temperature, "°C", "min_temperature", "max_temperature")
        addAlertLine(alertLines, "ec", "EC", reading.ec, "mS/cm", "min_ec", "max_ec")

        if (alertLines.isEmpty()) return

        publishAlertBuzzer()
        showThresholdAlert(
            "Peringatan Nutrisi Tanaman",
            alertLines.joinToString("\n")
        )
    }

    private fun addAlertLine(
        lines: MutableList<String>,
        sensorKey: String,
        label: String,
        value: Double?,
        unit: String,
        minKey: String,
        maxKey: String
    ) {
        if (value == null) return
        if (mutedSensors[sensorKey] == true) {
            lastAlertTimes.keys
                .filter { it.startsWith("$label:") }
                .forEach { lastAlertTimes.remove(it) }
            return
        }
        val min = thresholds[minKey] ?: return
        val max = thresholds[maxKey] ?: return
        val status = when {
            value < min -> "di bawah batas minimal ${formatNumber(min)} $unit"
            value > max -> "di atas batas maksimal ${formatNumber(max)} $unit"
            else -> return
        }

        val now = System.currentTimeMillis()
        val alertKey = "$label:$status"
        val lastAlert = lastAlertTimes[alertKey]
        if (lastAlert != null && now - lastAlert < repeatAlertMillis) return

        lastAlertTimes[alertKey] = now
        lines.add("$label: ${formatNumber(value)} $unit $status")
    }

    private fun runRuleBasedDecisionSupport() {
        if (!isEnabled(this)) return
        val reading = latestReading ?: return
        val relays = relaysForRule(reading)
        if (relays.isEmpty()) return

        val now = System.currentTimeMillis()
        val allowedRelays = relays.filter { relay ->
            val lastActivation = lastRelayActivationTimes[relay]
            lastActivation == null || now - lastActivation >= ruleIntervalMillis
        }.toSet()

        if (allowedRelays.isEmpty()) return

        pulseRelays(allowedRelays)
        allowedRelays.forEach { relay -> lastRelayActivationTimes[relay] = now }
    }

    private fun runDueSchedules() {
        val enabledSchedules = schedules.filter { it.enabled }
        if (enabledSchedules.isEmpty()) return

        val now = Calendar.getInstance()
        val todayKey = "%04d-%02d-%02d".format(
            now.get(Calendar.YEAR),
            now.get(Calendar.MONTH) + 1,
            now.get(Calendar.DAY_OF_MONTH)
        )
        val currentMinute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        var changed = false

        for (schedule in enabledSchedules) {
            val scheduleMinute = schedule.hour * 60 + schedule.minute
            if (currentMinute != scheduleMinute) continue
            if (lastScheduleRunDates[schedule.id] == todayKey) continue

            lastScheduleRunDates[schedule.id] = todayKey
            pulseRelays(schedule.relays, schedule.durationSeconds * 1000L)

            if (!schedule.repeatsDaily) {
                schedule.enabled = false
                changed = true
            }
        }

        if (changed) {
            persistSchedules()
        }
    }

    private fun relaysForRule(reading: SensorReading): Set<Int> {
        val relays = mutableSetOf<Int>()

        if (isLow(reading.nitrogen, "min_nitrogen")) relays.add(1)
        if (isLow(reading.phosphorus, "min_phosphorus")) relays.add(2)
        if (isLow(reading.potassium, "min_potassium")) relays.add(3)
        if (isLow(reading.moisture, "min_moisture")) relays.add(4)
        if (isHigh(reading.temperature, "max_temperature")) relays.add(4)
        if (isLow(reading.ec, "min_ec")) relays.addAll(setOf(1, 2, 3))

        return relays
    }

    private fun isLow(value: Double?, minKey: String): Boolean {
        return value != null && value < (thresholds[minKey] ?: return false)
    }

    private fun isHigh(value: Double?, maxKey: String): Boolean {
        return value != null && value > (thresholds[maxKey] ?: return false)
    }

    private fun pulseRelays(relays: Set<Int>) {
        pulseRelays(relays, 5_000)
    }

    private fun pulseRelays(relays: Set<Int>, durationMillis: Long) {
        if (relays.isEmpty()) return
        relays.forEach { relay -> publishRelay(relay, true) }
        Thread.sleep(durationMillis.coerceAtLeast(1_000))
        relays.forEach { relay -> publishRelay(relay, false) }
    }

    private fun publishRelay(relay: Int, turnOn: Boolean) {
        val payload = JSONObject()
            .put("relay$relay", if (turnOn) 1 else 0)
            .toString()
        publishMqtt(CONTROL_TOPIC, payload)
    }

    private fun publishAlertBuzzer() {
        val payload = JSONObject()
            .put("buzzer", 1)
            .toString()
        publishMqtt(CONTROL_TOPIC, payload)
    }

    private fun publishMqtt(topic: String, payload: String) {
        val client = mqttClient ?: return
        if (!client.isConnected) return

        try {
            client.publish(topic, MqttMessage(payload.toByteArray()).apply {
                qos = 1
            })
        } catch (_: Exception) {
        }
    }

    private fun updateThresholds(thresholdsJson: String?) {
        storeThresholds(this, thresholdsJson)

        val raw = thresholdsJson ?: getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREF_THRESHOLDS, null)
            ?: return

        try {
            val json = JSONObject(raw)
            json.keys().forEach { key ->
                val value = json.opt(key)
                if (value is Number) {
                    thresholds[key] = value.toDouble()
                }
            }
            updateMutedSensors(json.optJSONObject("buzzer_muted") ?: json.optJSONObject("buzzerMuted"))
        } catch (_: Exception) {
        }
    }

    private fun updateMutedSensors(json: JSONObject?) {
        if (json == null) return
        mutedSensors.keys.forEach { key ->
            if (json.has(key)) {
                mutedSensors[key] = json.optBoolean(key, false)
            }
        }
    }

    private fun loadStoredThresholds() {
        updateThresholds(null)
    }

    private fun updateSchedules(schedulesJson: String?) {
        storeSchedules(this, schedulesJson)

        val raw = schedulesJson ?: getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREF_SCHEDULES, null)
            ?: "[]"

        schedules.clear()

        try {
            val array = JSONArray(raw)
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val schedule = WateringSchedule.fromJson(item) ?: continue
                schedules.add(schedule)
            }
        } catch (_: Exception) {
        }
    }

    private fun loadStoredSchedules() {
        updateSchedules(null)
    }

    private fun persistSchedules() {
        val array = JSONArray()
        schedules.forEach { schedule ->
            array.put(schedule.toJson())
        }
        storeSchedules(this, array.toString())
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
                MONITOR_CHANNEL_ID,
                "Monitor Latar Belakang NutriXense",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Menjaga pemantauan MQTT dan DSS tetap aktif."
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "Peringatan Nutrisi Tanaman",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Memberi peringatan saat pembacaan nutrisi tanaman keluar dari ambang yang dikonfigurasi."
                enableVibration(true)
                setSound(soundUri, audioAttributes)
            }
        )
    }

    private fun buildForegroundNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MONITOR_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setPriority(Notification.PRIORITY_LOW)
        }

        return builder
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setContentTitle("NutriXense monitoring active")
            .setContentText("MQTT and Decision Support are running in the background.")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun showThresholdAlert(title: String, message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
        }

        val notification = builder
            .setSmallIcon(R.drawable.ic_nutrixense_notification)
            .setContentTitle(title)
            .setContentText(message.lines().firstOrNull() ?: message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 350, 150, 350))
            .build()

        manager.notify(ALERT_NOTIFICATION_BASE_ID + (System.currentTimeMillis() % 1000).toInt(), notification)
    }

    private fun formatNumber(value: Double): String {
        return String.format("%.1f", value)
    }

    private fun defaultThresholds(): Map<String, Double> = mapOf(
        "min_nitrogen" to 80.0,
        "max_nitrogen" to 180.0,
        "min_phosphorus" to 100.0,
        "max_phosphorus" to 300.0,
        "min_potassium" to 250.0,
        "max_potassium" to 650.0,
        "min_ph" to 4.5,
        "max_ph" to 5.5,
        "min_moisture" to 40.0,
        "max_moisture" to 70.0,
        "min_temperature" to 18.0,
        "max_temperature" to 25.0,
        "min_ec" to 1.2,
        "max_ec" to 2.5
    )

    private fun defaultMutedSensors(): Map<String, Boolean> = mapOf(
        "nitrogen" to false,
        "phosphorus" to false,
        "potassium" to false,
        "ph" to false,
        "moisture" to false,
        "temperature" to false,
        "ec" to false
    )

    data class SensorReading(
        val nitrogen: Double?,
        val phosphorus: Double?,
        val potassium: Double?,
        val ph: Double?,
        val temperature: Double?,
        val moisture: Double?,
        val ec: Double?
    ) {
        companion object {
            fun fromJson(payload: String): SensorReading? {
                return try {
                    val json = JSONObject(payload)
                    SensorReading(
                        nitrogen = readDouble(json, "N", "n", "nitrogen"),
                        phosphorus = readDouble(json, "P", "p", "phosphorus"),
                        potassium = readDouble(json, "K", "k", "potassium"),
                        ph = readDouble(json, "pH", "ph", "PH"),
                        temperature = readDouble(json, "Temp", "temp", "temperature"),
                        moisture = readDouble(json, "Moisture", "moisture"),
                        ec = readDouble(json, "EC", "ec", "electrical_conductivity")
                    )
                } catch (_: Exception) {
                    null
                }
            }

            private fun readDouble(json: JSONObject, vararg keys: String): Double? {
                for (key in keys) {
                    if (!json.has(key) || json.isNull(key)) continue
                    val value = json.opt(key)
                    if (value is Number) return value.toDouble()
                    if (value is String) return value.toDoubleOrNull()
                }
                return null
            }
        }
    }

    data class WateringSchedule(
        val id: Long,
        val hour: Int,
        val minute: Int,
        val relays: Set<Int>,
        val durationSeconds: Int,
        val repeatsDaily: Boolean,
        var enabled: Boolean
    ) {
        fun toJson(): JSONObject {
            return JSONObject()
                .put("id", id)
                .put("hour", hour)
                .put("minute", minute)
                .put("pumpIndexes", JSONArray(relays.map { relay -> relay - 1 }))
                .put("durationSeconds", durationSeconds)
                .put("repeatsDaily", repeatsDaily)
                .put("enabled", enabled)
        }

        companion object {
            fun fromJson(json: JSONObject): WateringSchedule? {
                val id = json.optLong("id", -1)
                val hour = json.optInt("hour", -1)
                val minute = json.optInt("minute", -1)
                val durationSeconds = json.optInt("durationSeconds", 5)
                val repeatsDaily = json.optBoolean("repeatsDaily", true)
                val enabled = json.optBoolean("enabled", true)
                val pumpIndexes = json.optJSONArray("pumpIndexes") ?: return null

                if (id < 0 || hour !in 0..23 || minute !in 0..59) return null

                val relays = mutableSetOf<Int>()
                for (index in 0 until pumpIndexes.length()) {
                    val pumpIndex = pumpIndexes.optInt(index, -1)
                    if (pumpIndex in 0..3) relays.add(pumpIndex + 1)
                }

                if (relays.isEmpty()) return null

                return WateringSchedule(
                    id = id,
                    hour = hour,
                    minute = minute,
                    relays = relays,
                    durationSeconds = durationSeconds,
                    repeatsDaily = repeatsDaily,
                    enabled = enabled
                )
            }
        }
    }
}
