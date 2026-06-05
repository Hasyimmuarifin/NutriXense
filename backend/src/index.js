const { startMqttWorker } = require('./mqttWorker');

console.log('Starting NutriXense backend workers...');

startMqttWorker();

process.on('SIGINT', () => {
  console.log('NutriXense backend stopped.');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('NutriXense backend stopped.');
  process.exit(0);
});
