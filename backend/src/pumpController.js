const { admin, db } = require('./firebase');
const { config } = require('./config');

const RELAY_LABELS = {
  1: 'Pompa A (N)',
  2: 'Pompa B (P)',
  3: 'Pompa C (K)',
  4: 'Pompa D (Air)',
};

function validRelays(relays) {
  return [...new Set(relays.map(Number))]
    .filter((relay) => Number.isInteger(relay) && relay >= 1 && relay <= 4)
    .sort((a, b) => a - b);
}

function publishRelay(client, relay, isOn) {
  const payload = JSON.stringify({ [`relay${relay}`]: isOn ? 1 : 0 });
  client.publish(config.mqtt.controlTopic, payload, { qos: 1 }, (error) => {
    if (error) {
      console.error(`Failed to publish relay ${relay} command:`, error);
      return;
    }

    console.log(`Published ${payload} to ${config.mqtt.controlTopic}`);
  });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runPumpPulse(client, relays, durationMs, reason, metadata = {}) {
  const selectedRelays = validRelays(relays);
  if (selectedRelays.length === 0) return;

  for (const relay of selectedRelays) {
    publishRelay(client, relay, true);
  }

  const startedAt = new Date();

  try {
    await delay(durationMs);
  } finally {
    for (const relay of selectedRelays) {
      publishRelay(client, relay, false);
    }

    await db.collection(config.firestore.pumpLogsCollection).add({
      relays: selectedRelays,
      pumpLabels: selectedRelays.map((relay) => RELAY_LABELS[relay]),
      durationMs,
      reason,
      metadata,
      startedAt,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

module.exports = {
  RELAY_LABELS,
  runPumpPulse,
  validRelays,
};
