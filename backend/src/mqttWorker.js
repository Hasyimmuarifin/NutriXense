const mqtt = require('mqtt');
const { admin, db } = require('./firebase');
const { config } = require('./config');
const { normalizeSensorPayload } = require('./sensorNormalizer');

let lastSavedTime = 0;

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
  });

  client.on('message', (topic, rawPayload) => {
    Promise.resolve()
      .then(() => parsePayload(rawPayload))
      .then((payload) => saveSensorReading(topic, payload))
      .catch((error) => {
        console.error('Failed to process MQTT sensor message:', error);
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
