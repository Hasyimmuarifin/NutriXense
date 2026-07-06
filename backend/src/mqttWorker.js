const mqtt = require('mqtt');
const { admin, db } = require('./firebase');
const { config } = require('./config');
const { normalizeSensorPayload } = require('./sensorNormalizer');
const { RELAY_LABELS } = require('./pumpController');

let lastSavedTime = 0;
const manualPumpSessions = new Map();
const pendingManualPumpCommands = new Map();
const MANUAL_COMMAND_CONFIRM_TIMEOUT_MS = 15 * 1000;

function parsePayload(rawPayload) {
  const message = rawPayload.toString('utf8');
  return JSON.parse(message);
}

async function saveSensorReading(topic, payload) {
  const now = Date.now();
  if (now - lastSavedTime < config.firestore.saveIntervalMs) {
    console.log('Sensor reading ignored because it is still inside the save interval.');
    return;
  }

  const normalized = normalizeSensorPayload(payload);
  const fieldCount = Object.keys(normalized).length;

  if (fieldCount === 0) {
    console.warn('Sensor payload ignored because no supported fields were found.', {
      topic,
      payload,
    });
    return;
  }

  await db.collection(config.firestore.sensorCollection).add({
    ...normalized,
    source: 'hivemq',
    mqttTopic: topic,
    rawPayload: payload,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    receivedAt: new Date().toISOString(),
  });

  lastSavedTime = now;
  console.log(`Saved sensor reading with ${fieldCount} field(s).`);
}

function isManualControlPayload(payload) {
  return payload.source === 'manual' ||
    payload.source === 'manual_control' ||
    payload.manual_override === 1 ||
    payload.manual_override === true;
}

function relayCommandsFromPayload(payload) {
  const commands = [];

  for (let relay = 1; relay <= 4; relay++) {
    const rawValue = payload[`relay${relay}`];
    if (rawValue === undefined || rawValue === null) continue;

    const parsedValue = typeof rawValue === 'number'
      ? rawValue
      : Number(rawValue);
    if (!Number.isFinite(parsedValue)) continue;

    commands.push({
      relay,
      isOn: parsedValue === 1,
    });
  }

  return commands;
}

async function saveManualPumpControlLog(payload) {
  if (!isManualControlPayload(payload)) return;

  const commands = relayCommandsFromPayload(payload);
  if (commands.length === 0) return;

  for (const command of commands) {
    pendingManualPumpCommands.set(command.relay, {
      isOn: command.isOn,
      sentAt: Date.now(),
    });
    console.log(
      `Manual pump relay ${command.relay} command pending confirmation: ${command.isOn ? 'ON' : 'OFF'}.`,
    );
  }
}

async function saveManualPumpCommand(relay, isOn) {
  const session = manualPumpSessions.get(relay);

  if (isOn) {
    if (session) {
      console.log(`Manual pump relay ${relay} already has an active log session.`);
      return;
    }

    const startedAt = new Date();
    const docRef = await db.collection(config.firestore.pumpLogsCollection).add({
      relays: [relay],
      pumpLabels: [RELAY_LABELS[relay] || `Relay ${relay}`],
      durationMs: 0,
      reason: 'Kontrol manual pompa',
      action: 'running',
      metadata: {
        source: 'manual_control',
        relay,
        state: 'on',
      },
      startedAt,
      startedAtLocal: startedAt.toISOString(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    manualPumpSessions.set(relay, { docRef, startedAt });
    console.log(`Manual pump relay ${relay} started and logged.`);
    return;
  }

  const finishedAt = new Date();
  if (!session) {
    console.log(`Manual pump relay ${relay} OFF confirmation ignored because no ON session exists.`);
    return;
  }

  const durationMs = finishedAt.getTime() - session.startedAt.getTime();
  const payload = {
    relays: [relay],
    pumpLabels: [RELAY_LABELS[relay] || `Relay ${relay}`],
    durationMs,
    reason: 'Kontrol manual pompa',
    action: 'completed',
    metadata: {
      source: 'manual_control',
      relay,
      state: 'off',
    },
    finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    finishedAtLocal: finishedAt.toISOString(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await session.docRef.set(payload, { merge: true });
  manualPumpSessions.delete(relay);

  console.log(`Manual pump relay ${relay} stopped and logged (${durationMs}ms).`);
}

function readRelayState(payload, relay) {
  const keys = [
    `relay${relay}`,
    `Relay${relay}`,
    `RELAY${relay}`,
    `r${relay}`,
    `R${relay}`,
  ];

  for (const key of keys) {
    const rawValue = payload[key];
    if (rawValue === undefined || rawValue === null) continue;

    if (typeof rawValue === 'boolean') return rawValue;

    const parsedValue = typeof rawValue === 'number'
      ? rawValue
      : Number(rawValue);
    if (!Number.isFinite(parsedValue)) continue;

    return parsedValue === 1;
  }

  return undefined;
}

async function confirmManualPumpCommandsFromSensor(payload) {
  const now = Date.now();

  for (const [relay, command] of [...pendingManualPumpCommands.entries()]) {
    if (now - command.sentAt > MANUAL_COMMAND_CONFIRM_TIMEOUT_MS) {
      pendingManualPumpCommands.delete(relay);
      console.warn(
        `Manual pump relay ${relay} command expired without device confirmation.`,
      );
      continue;
    }

    const actualState = readRelayState(payload, relay);
    if (actualState === undefined || actualState !== command.isOn) continue;

    pendingManualPumpCommands.delete(relay);
    await saveManualPumpCommand(relay, command.isOn);
  }
}

function startMqttWorker() {
  const url = `mqtts://${config.mqtt.host}:${config.mqtt.port}`;
  const client = mqtt.connect(url, {
    clientId: `${config.mqtt.clientId}-${Date.now().toString(36)}`,
    clean: true,
    username: config.mqtt.username,
    password: config.mqtt.password,
    reconnectPeriod: 5000,
    keepalive: 30,
  });

  client.on('connect', () => {
    console.log(`Connected to MQTT broker: ${config.mqtt.host}`);
    client.subscribe(config.mqtt.sensorTopic, { qos: 1 }, (error) => {
      if (error) {
        console.error('Failed to subscribe MQTT sensor topic:', error);
        return;
      }

      console.log(`Subscribed to sensor topic: ${config.mqtt.sensorTopic}`);
    });

    client.subscribe(config.mqtt.controlTopic, { qos: 1 }, (error) => {
      if (error) {
        console.error('Failed to subscribe MQTT control topic:', error);
        return;
      }

      console.log(`Subscribed to control topic: ${config.mqtt.controlTopic}`);
    });
  });

  client.on('message', (topic, rawPayload) => {
    Promise.resolve()
      .then(() => parsePayload(rawPayload))
      .then((payload) => {
        if (topic === config.mqtt.sensorTopic) {
          return Promise.resolve()
            .then(() => confirmManualPumpCommandsFromSensor(payload))
            .then(() => saveSensorReading(topic, payload));
        }

        if (topic === config.mqtt.controlTopic) {
          return saveManualPumpControlLog(payload);
        }

        return undefined;
      })
      .catch((error) => {
        console.error('Failed to process MQTT message:', error);
      });
  });

  client.on('reconnect', () => {
    console.log('Reconnecting to MQTT broker...');
  });

  client.on('error', (error) => {
    console.error('MQTT client error:', error.message);
  });

  client.on('close', () => {
    console.warn('MQTT connection closed.');
  });

  return client;
}

module.exports = { startMqttWorker };
