const { admin, db } = require('./firebase');
const { config } = require('./config');
const { sensorReadingFromFirestore } = require('./readingUtils');
const { abnormalReadings, buildThresholds } = require('./thresholdRules');

function formatValue(value) {
  return Number(value).toFixed(1);
}

function formatAlertLine(alert) {
  return `${alert.label}: ${formatValue(alert.value)} ${alert.unit} is ${alert.direction} ${formatValue(alert.threshold)} ${alert.unit}`;
}

function alertKey(alert) {
  return `${alert.key}:${alert.status}`;
}

function readMutedSensors(...configs) {
  return configs.reduce((mutedSensors, item) => {
    const rawMuted = item?.buzzerMuted || item?.buzzer_muted || {};
    for (const [key, value] of Object.entries(rawMuted)) {
      mutedSensors[key] = value === true || value === 1;
    }
    return mutedSensors;
  }, {});
}

async function writeRuntimeStatus(status) {
  try {
    await db
      .collection(config.firestore.automationConfigCollection)
      .doc('threshold_notifications_runtime')
      .set(
        {
          ...status,
          checkedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  } catch (error) {
    console.error('Failed to write threshold notification runtime:', error.message);
  }
}

async function loadNotificationConfig() {
  const dssSnapshot = await db
    .collection(config.firestore.automationConfigCollection)
    .doc(config.firestore.dssConfigDocument)
    .get();
  const fallbackSnapshot = await db
    .collection(config.firestore.wateringSchedulesCollection)
    .doc('_dss_config')
    .get();
  const notificationSnapshot = await db
    .collection(config.firestore.automationConfigCollection)
    .doc('threshold_notifications')
    .get();

  const dssData = dssSnapshot.exists ? dssSnapshot.data() : {};
  const fallbackData = fallbackSnapshot.exists ? fallbackSnapshot.data() : {};
  const notificationData = notificationSnapshot.exists
    ? notificationSnapshot.data()
    : {};
  const data = {
    ...dssData,
    ...fallbackData,
    ...notificationData,
    thresholds: {
      ...(dssData.thresholds || {}),
      ...(fallbackData.thresholds || {}),
      ...(notificationData.thresholds || {}),
    },
  };

  return {
    enabled:
      notificationData.enabled !== undefined
        ? notificationData.enabled === true
        : config.automation.thresholdNotificationEnabled,
    thresholds: buildThresholds(data),
    mutedSensors: readMutedSensors(dssData, fallbackData, notificationData),
    repeatMs:
      Number(notificationData.repeatMs) ||
      config.automation.thresholdNotificationRepeatMs,
  };
}

async function loadLatestReading() {
  const snapshot = await db
    .collection(config.firestore.sensorCollection)
    .orderBy('timestamp', 'desc')
    .limit(1)
    .get();

  if (snapshot.empty) return undefined;
  return {
    id: snapshot.docs[0].id,
    ...sensorReadingFromFirestore(snapshot.docs[0].data()),
  };
}

async function sendThresholdNotification(alerts, reading) {
  const body = alerts.map(formatAlertLine).join('\n');
  const title = 'Nutrient threshold alert';

  const response = await admin.messaging().send({
    topic: config.automation.fcmTopic,
    notification: {
      title,
      body,
    },
    data: {
      title,
      body,
      message: body,
      type: 'threshold_alert',
      sensorReadingId: reading.id,
      alertCount: String(alerts.length),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: config.automation.fcmChannelId,
        sound: 'default',
      },
    },
  });

  await db.collection(config.firestore.thresholdAlertLogsCollection).add({
    topic: config.automation.fcmTopic,
    title,
    body,
    alerts,
    sensorReadingId: reading.id,
    fcmMessageId: response,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return response;
}

function startThresholdNotificationWorker() {
  const lastSentByAlert = new Map();
  let isChecking = false;

  async function check() {
    if (isChecking) return;
    isChecking = true;

    try {
      const notificationConfig = await loadNotificationConfig();
      if (!notificationConfig.enabled) {
        await writeRuntimeStatus({
          state: 'disabled',
          message: 'Threshold notification worker is disabled.',
        });
        return;
      }

      const reading = await loadLatestReading();
      if (!reading) {
        await writeRuntimeStatus({
          state: 'no_reading',
          message: 'No sensor reading found in Firestore.',
        });
        return;
      }

      if (
        reading.timestampMillis &&
        Date.now() - reading.timestampMillis >
          config.automation.thresholdNotificationMaxSensorAgeMs
      ) {
        await writeRuntimeStatus({
          state: 'sensor_stale',
          message:
            'Latest sensor reading is older than THRESHOLD_NOTIFICATION_MAX_SENSOR_AGE_MS.',
          sensorReadingId: reading.id,
          sensorAgeMs: Date.now() - reading.timestampMillis,
        });
        return;
      }

      const alerts = abnormalReadings(reading, notificationConfig.thresholds)
        .filter((alert) => notificationConfig.mutedSensors[alert.key] !== true);
      if (alerts.length === 0) {
        lastSentByAlert.clear();
        await writeRuntimeStatus({
          state: 'normal',
          message:
            'All unmuted readings are inside configured thresholds.',
          sensorReadingId: reading.id,
          mutedSensors: notificationConfig.mutedSensors,
        });
        return;
      }

      const dueAlerts = alerts.filter((alert) => {
        const key = alertKey(alert);
        const lastSentAt = lastSentByAlert.get(key);
        return (
          !lastSentAt ||
          Date.now() - lastSentAt >= notificationConfig.repeatMs
        );
      });

      if (dueAlerts.length === 0) {
        await writeRuntimeStatus({
          state: 'repeat_wait',
          message: 'Abnormal readings found, but repeat interval has not passed.',
          sensorReadingId: reading.id,
          alerts,
          mutedSensors: notificationConfig.mutedSensors,
          repeatMs: notificationConfig.repeatMs,
        });
        return;
      }

      const fcmMessageId = await sendThresholdNotification(dueAlerts, reading);
      const now = Date.now();
      for (const alert of dueAlerts) {
        lastSentByAlert.set(alertKey(alert), now);
      }

      await writeRuntimeStatus({
        state: 'sent',
        message: 'Threshold push notification sent.',
        sensorReadingId: reading.id,
        alerts: dueAlerts,
        mutedSensors: notificationConfig.mutedSensors,
        fcmMessageId,
        repeatMs: notificationConfig.repeatMs,
      });
    } catch (error) {
      console.error('Threshold notification worker check failed:', error);
      await writeRuntimeStatus({
        state: 'error',
        message: error.message,
      });
    } finally {
      isChecking = false;
    }
  }

  check();
  const timer = setInterval(
    check,
    config.automation.thresholdNotificationIntervalMs,
  );
  return { stop: () => clearInterval(timer) };
}

module.exports = { startThresholdNotificationWorker };
