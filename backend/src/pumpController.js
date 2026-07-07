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

async function runPumpPulseByRelay(client, durationMsByRelay, reason, metadata = {}) {
  const entries = Object.entries(durationMsByRelay || {})
    .map(([relay, durationMs]) => [Number(relay), Number(durationMs)])
    .filter(([relay, durationMs]) =>
      Number.isInteger(relay) &&
      relay >= 1 &&
      relay <= 4 &&
      Number.isFinite(durationMs) &&
      durationMs > 0,
    )
    .sort(([relayA], [relayB]) => relayA - relayB);

  if (entries.length === 0) return;

  const selectedRelays = entries.map(([relay]) => relay);
  const durationByRelay = Object.fromEntries(entries);
  const maxDurationMs = Math.max(...entries.map(([, durationMs]) => durationMs));

  for (const relay of selectedRelays) {
    publishRelay(client, relay, true);
  }

  const startedAt = new Date();
  const remainingRelays = new Set(selectedRelays);
  const startedAtMs = Date.now();

  try {
    while (remainingRelays.size > 0) {
      const elapsedMs = Date.now() - startedAtMs;

      for (const relay of [...remainingRelays]) {
        if (elapsedMs >= durationByRelay[relay]) {
          publishRelay(client, relay, false);
          remainingRelays.delete(relay);
        }
      }

      if (remainingRelays.size > 0) {
        await delay(250);
      }
    }
  } finally {
    for (const relay of remainingRelays) {
      publishRelay(client, relay, false);
    }

    await db.collection(config.firestore.pumpLogsCollection).add({
      relays: selectedRelays,
      pumpLabels: selectedRelays.map((relay) => RELAY_LABELS[relay]),
      durationMs: maxDurationMs,
      durationMsByRelay: durationByRelay,
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
  runPumpPulseByRelay,
  validRelays,
};
