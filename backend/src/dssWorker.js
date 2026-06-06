const { admin, db } = require('./firebase');
const { config } = require('./config');
const { runPumpPulse } = require('./pumpController');
const { sensorReadingFromFirestore } = require('./readingUtils');

const DEFAULT_THRESHOLDS = {
  min_nitrogen: 40,
  max_nitrogen: 80,
  min_phosphorus: 20,
  max_phosphorus: 60,
  min_potassium: 40,
  max_potassium: 100,
  min_ph: 5.8,
  max_ph: 7.2,
  min_moisture: 40,
  max_moisture: 80,
  min_temperature: 18,
  max_temperature: 35,
  min_ec: 1.0,
  max_ec: 3.0,
};

function isLow(value, minimum) {
  return typeof value === 'number' && typeof minimum === 'number' && value < minimum;
}

function isHigh(value, maximum) {
  return typeof value === 'number' && typeof maximum === 'number' && value > maximum;
}

function relaysForReading(reading, thresholds) {
  const relays = new Set();

  if (isLow(reading.nitrogen, thresholds.min_nitrogen)) relays.add(1);
  if (isLow(reading.phosphorus, thresholds.min_phosphorus)) relays.add(2);
  if (isLow(reading.potassium, thresholds.min_potassium)) relays.add(3);
  if (isLow(reading.moisture, thresholds.min_moisture)) relays.add(4);
  if (isHigh(reading.temperature, thresholds.max_temperature)) relays.add(4);
  if (isLow(reading.ec, thresholds.min_ec)) {
    relays.add(1);
    relays.add(2);
    relays.add(3);
  }

  return [...relays];
}

async function loadDssConfig() {
  const primarySnapshot = await db
    .collection(config.firestore.automationConfigCollection)
    .doc(config.firestore.dssConfigDocument)
    .get();
  const fallbackSnapshot = await db
    .collection(config.firestore.wateringSchedulesCollection)
    .doc('_dss_config')
    .get();

  const primaryData = primarySnapshot.exists ? primarySnapshot.data() : {};
  const fallbackData = fallbackSnapshot.exists ? fallbackSnapshot.data() : {};
  const data = {
    ...primaryData,
    ...fallbackData,
    thresholds: {
      ...(primaryData.thresholds || {}),
      ...(fallbackData.thresholds || {}),
    },
  };
  return {
    enabled: data.enabled === true,
    thresholds: {
      ...DEFAULT_THRESHOLDS,
      ...(data.thresholds || {}),
    },
    pulseDurationMs: Number(data.pulseDurationMs) || config.automation.dssPulseDurationMs,
    cooldownMs: Number(data.cooldownMs) || config.automation.dssCooldownMs,
  };
}

async function writeDssRuntimeStatus(status) {
  try {
    await db
      .collection(config.firestore.automationConfigCollection)
      .doc('dss_runtime')
      .set(
        {
          ...status,
          checkedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  } catch (error) {
    console.error('Failed to write DSS runtime status:', error.message);
  }
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

function startDssWorker(mqttClient) {
  const lastActivationByRelay = new Map();
  let isChecking = false;

  async function check() {
    if (isChecking) return;
    isChecking = true;

    try {
      const dssConfig = await loadDssConfig();
      if (!dssConfig.enabled) {
        await writeDssRuntimeStatus({
          state: 'disabled',
          message: 'DSS is disabled in Firestore config.',
        });
        return;
      }

      const reading = await loadLatestReading();
      if (!reading) {
        await writeDssRuntimeStatus({
          state: 'no_reading',
          message: 'No sensor reading found in Firestore.',
        });
        return;
      }

      if (
        reading.timestampMillis &&
        Date.now() - reading.timestampMillis > config.automation.maxSensorAgeMs
      ) {
        console.warn('DSS skipped because latest sensor reading is stale.');
        await writeDssRuntimeStatus({
          state: 'sensor_stale',
          message: 'Latest sensor reading is older than DSS_MAX_SENSOR_AGE_MS.',
          sensorReadingId: reading.id,
          sensorAgeMs: Date.now() - reading.timestampMillis,
          maxSensorAgeMs: config.automation.maxSensorAgeMs,
        });
        return;
      }

      const relays = relaysForReading(reading, dssConfig.thresholds);
      if (relays.length === 0) {
        await writeDssRuntimeStatus({
          state: 'no_rule_matched',
          message: 'Latest sensor reading does not cross any DSS threshold.',
          sensorReadingId: reading.id,
          reading,
          thresholds: dssConfig.thresholds,
        });
        return;
      }

      const allowedRelays = relays.filter((relay) => {
        const lastActivation = lastActivationByRelay.get(relay);
        return !lastActivation || Date.now() - lastActivation >= dssConfig.cooldownMs;
      });

      if (allowedRelays.length === 0) {
        await writeDssRuntimeStatus({
          state: 'cooldown',
          message: 'DSS rule matched, but all matched relays are still in cooldown.',
          sensorReadingId: reading.id,
          matchedRelays: relays,
          cooldownMs: dssConfig.cooldownMs,
        });
        return;
      }

      await runPumpPulse(
        mqttClient,
        allowedRelays,
        dssConfig.pulseDurationMs,
        'Rule-based DSS automatic pump control',
        {
          source: 'dss_worker',
          sensorReadingId: reading.id,
          thresholds: dssConfig.thresholds,
        },
      );

      const now = Date.now();
      for (const relay of allowedRelays) {
        lastActivationByRelay.set(relay, now);
      }

      await writeDssRuntimeStatus({
        state: 'activated',
        message: 'DSS activated pump relay(s).',
        sensorReadingId: reading.id,
        matchedRelays: relays,
        activatedRelays: allowedRelays,
        pulseDurationMs: dssConfig.pulseDurationMs,
        cooldownMs: dssConfig.cooldownMs,
      });
    } catch (error) {
      console.error('DSS worker check failed:', error);
      await writeDssRuntimeStatus({
        state: 'error',
        message: error.message,
      });
    } finally {
      isChecking = false;
    }
  }

  check();
  const timer = setInterval(check, config.automation.dssCheckIntervalMs);
  return { stop: () => clearInterval(timer) };
}

module.exports = { startDssWorker, DEFAULT_THRESHOLDS };
