# NutriXense Backend

Backend worker untuk menjalankan proses NutriXense yang harus hidup 24 jam di VPS.

Tahap pertama yang sudah tersedia:

- Subscribe data sensor dari HiveMQ Cloud.
- Normalisasi payload sensor ke field yang dipakai Flutter.
- Simpan data ke Firestore collection `sensor_data`.

## Setup Lokal atau VPS

```bash
cd backend
npm install
cp .env.example .env
```

Isi `.env` dengan credential HiveMQ dan Firebase Admin SDK.

Download Firebase Admin SDK dari Firebase Console:

```text
Project Settings -> Service Accounts -> Generate new private key
```

Simpan file JSON sebagai:

```text
backend/serviceAccountKey.json
```

## Menjalankan Worker

```bash
npm start
```

Jika sudah punya middleware lama `mqtt-firestore`, format `.env` berikut tetap didukung:

```env
MQTT_HOST=your-hivemq-host
MQTT_PORT=8883
MQTT_USER=your-hivemq-username
MQTT_PASS=your-hivemq-password
MQTT_TOPIC=nutrixense/sensor
SAVE_INTERVAL_MS=60000
FIRESTORE_COLLECTION=sensor_data
FIREBASE_SERVICE_ACCOUNT=
```

Untuk VPS, jalankan dengan PM2:

```bash
npm install -g pm2
pm2 start src/index.js --name nutrixense-backend
pm2 save
pm2 startup
```

## Payload MQTT yang Didukung

Worker menerima variasi key dari perangkat, lalu menyimpannya sebagai field standar.

Contoh:

```json
{
  "N": 42,
  "P": 25,
  "K": 51,
  "pH": 6.4,
  "Moisture": 58,
  "Temp": 29.5,
  "EC": 1.8
}
```

Akan disimpan ke Firestore sebagai:

```json
{
  "nitrogen": 42,
  "phosphorus": 25,
  "potassium": 51,
  "ph": 6.4,
  "moisture": 58,
  "temperature": 29.5,
  "ec": 1.8,
  "timestamp": "server timestamp"
}
```

## Catatan Keamanan

Jangan commit file berikut:

- `.env`
- `serviceAccountKey.json`
- file credential Firebase lainnya

File tersebut sudah dimasukkan ke `.gitignore`.
