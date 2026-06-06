const { startMqttWorker } = require('./mqttWorker');
const { startDssWorker } = require('./dssWorker');
const { startScheduleWorker } = require('./scheduleWorker');
const {
  startThresholdNotificationWorker,
} = require('./thresholdNotificationWorker');

console.log('Starting NutriXense backend workers...');

const mqttClient = startMqttWorker();
const dssWorker = startDssWorker(mqttClient);
const scheduleWorker = startScheduleWorker(mqttClient);
const thresholdNotificationWorker = startThresholdNotificationWorker();

process.on('SIGINT', () => {
  dssWorker.stop();
  scheduleWorker.stop();
  thresholdNotificationWorker.stop();
  console.log('NutriXense backend stopped.');
  process.exit(0);
});

process.on('SIGTERM', () => {
  dssWorker.stop();
  scheduleWorker.stop();
  thresholdNotificationWorker.stop();
  console.log('NutriXense backend stopped.');
  process.exit(0);
});
