const { startMqttWorker } = require('./mqttWorker');
const { startDssWorker } = require('./dssWorker');
const { startScheduleWorker } = require('./scheduleWorker');
const { startDeviceConfigWorker } = require('./deviceConfigWorker');
const {
  startThresholdNotificationWorker,
} = require('./thresholdNotificationWorker');

console.log('Starting NutriXense backend workers...');

const mqttClient = startMqttWorker();
const dssWorker = startDssWorker(mqttClient);
const scheduleWorker = startScheduleWorker(mqttClient);
const deviceConfigWorker = startDeviceConfigWorker(mqttClient);
const thresholdNotificationWorker = startThresholdNotificationWorker();


process.on('SIGINT', () => {
  dssWorker.stop();
  scheduleWorker.stop();
  deviceConfigWorker.stop();
  thresholdNotificationWorker.stop();
  console.log('NutriXense backend stopped.');
  process.exit(0);
});

process.on('SIGTERM', () => {
  dssWorker.stop();
  scheduleWorker.stop();
  deviceConfigWorker.stop();
  thresholdNotificationWorker.stop();
  console.log('NutriXense backend stopped.');
  process.exit(0);
});

const http = require('node:http');
const port = Number(process.env.PORT || 8080);

http
  .createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(
      JSON.stringify({
        ok: true,
        service: 'nutrixense-backend',
        uptime: process.uptime(),
      }),
    );
  })
  .listen(port, '127.0.0.1', () => {
    console.log(`Health server listening on port ${port}`);
  });