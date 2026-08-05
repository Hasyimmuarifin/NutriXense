# 📘 Panduan Teknis (Technical Guidance) NutriXense
**Sistem Monitoring & Kontrol Nutrisi Tanaman Hydroponik/Pertanian Berbasis IoT, Cloud, dan AI (Gemini)**

---

## 📋 Daftar Isi
1. [Gambaran Umum & Arsitektur Sistem](#1-gambaran-umum--arsitektur-sistem)
2. [Skema Wiring & Rangkaian Perangkat IoT (ESP32 & Baterai 2S)](#2-skema-wiring--rangkaian-perangkat-iot-esp32--baterai-2s)
3. [Panduan Setup Cloud Services & API Key](#3-panduan-setup-cloud-services--api-key)
   - [3.1 Setup Firebase Console & Service Account](#31-setup-firebase-console--service-account)
   - [3.2 Setup HiveMQ Cloud MQTT Broker](#32-setup-hivemq-cloud-mqtt-broker)
   - [3.3 Setup Google AI Studio (Gemini API)](#33-setup-google-ai-studio-gemini-api)
4. [Deployment Backend Worker (Node.js & PM2)](#4-deployment-backend-worker-nodejs--pm2)
5. [Panduan Penggunaan Aplikasi Android NutriXense](#5-panduan-penggunaan-aplikasi-android-nutrixense)
6. [Panduan Penyusunan Buku Manual / Book PDF](#6-panduan-penyusunan-buku-manual--book-pdf)

---

## 1. Gambaran Umum & Arsitektur Sistem

NutriXense adalah sistem cerdas terintegrasi untuk memantau 7 parameter kualitas tanah/nutrisi tanaman (Nitrogen, Phosphorus, Potassium, pH, Kelembapan Tanah, Suhu Tanah, dan EC) secara real-time, mengontrol 4 pompa pemupukan/penyiraman secara otomatis dan manual, serta memberikan rekomendasi diagnosa kecerdasan buatan (Gemini AI).

Sistem hardware ditenagai oleh **2x Baterai Li-ion 18650 Seri (7.4V - 8.4V)** yang dilengkapi modul voltmeter pemantau kapasitas daya, saklar utama (*Rocker Switch*), regulator penstabil tegangan DC-DC (*Step-Down/Step-Up*), papan distribusi daya (*Prototype Board*), tampilan lokal **LCD 16x2 I2C**, **RTC DS3231** untuk pewaktuan presisi lokal, serta **Passive Buzzer** sebagai alarm frekuensi suara.

```mermaid
flowchart TD
    subgraph Power_System["Sistem Daya & Regulator"]
        Bat["2x Baterai 18650 Seri (7.4V - 8.4V)"]
        Switch["Saklar Utama (Rocker Switch)"]
        Voltmeter["Modul Indikator Baterai / Voltmeter"]
        DCDC["Modul DC-DC Converter (Step-Down 5V)"]
        Board["Papan Distribusi Daya (Proto-Board)"]

        Bat --> Switch
        Switch --> Voltmeter & DCDC
        DCDC --> Board
    end

    subgraph IoT_Hardware["Perangkat IoT Hardware"]
        ESP32["ESP32 DevKit v1"]
        RS485["Sensor 7-in-1 NPK/pH/EC/Moisture/Temp"]
        MAX485["Modul MAX485 TTL to RS485"]
        RTC["Modul Real-Time Clock (RTC DS3231 I2C)"]
        LCD["Display LCD 16x2 + Backpack I2C"]
        Relay["4x Modul Single Relay (Pompa A, B, C, D)"]
        Pumps["4x Submersible DC Water Pumps"]
        Buzzer["Passive Buzzer (Alert Suara PWM/Tone)"]
        
        Board --> ESP32 & MAX485 & LCD & RTC & Relay & Buzzer
        RS485 -->|Modbus RTU RS485| MAX485
        MAX485 -->|Serial UART2 (GPIO16/17/4)| ESP32
        ESP32 -->|I2C Bus (GPIO21 SDA / GPIO22 SCL)| LCD & RTC
        ESP32 -->|GPIO Control (GPIO25/26/27/14)| Relay
        Relay -->|Daya 7.4V Direct| Pumps
        ESP32 -->|GPIO 12 PWM Signal| Buzzer
    end

    subgraph Cloud_Broker["Cloud Infrastructure"]
        HiveMQ["HiveMQ Cloud MQTT Broker (Port 8883 TLS)"]
        Firestore[("Firebase Firestore Database")]
        FCM["Firebase Cloud Messaging (Push Notification)"]
        GeminiAPI["Google AI Studio (Gemini 1.5/2.0/3.6 Flash)"]
    end

    subgraph Server_Backend["Backend Service (VPS)"]
        NodeWorker["Node.js Backend Worker (PM2)"]
        NodeWorker -->|Subscribe Telemetry & History| HiveMQ
        NodeWorker -->|Read/Write Config & Logs| Firestore
        NodeWorker -->|Trigger Push Alert| FCM
    end

    subgraph Mobile_App["Aplikasi Mobile (Flutter Android)"]
        App["App NutriXense Android"]
        App -->|MQTT Realtime Stream| HiveMQ
        App -->|Firestore History & Config| Firestore
        App -->|Direct API Call / Insights| GeminiAPI
    end

    ESP32 -->|Publish Telemetry nutrixense/sensor| HiveMQ
    HiveMQ -->|Publish Control nutrixense/control| ESP32
```

---

## 2. Skema Wiring & Rangkaian Perangkat IoT (ESP32 & Baterai 2S)

### 2.1 Daftar Komponen Hardware Berdasarkan Rangkaian Cirkit Designer

| No | Komponen | Fungsi | Tegangan Operasional | Keterangan / Signal |
|---|---|---|---|---|
| 1 | **2x Baterai Li-ion 18650 Seri** | Sumber daya utama portabel (*2S Battery Pack*) | 7.4V Nominal (8.4V Max) | Dihubungkan secara Seri |
| 2 | **Saklar Rocker Switch** | Saklar On/Off utama seluruh sistem | 12V / 250V AC Max | Pemutus jalur positif baterai |
| 3 | **Modul Voltmeter / Battery Level** | Menampilkan sisa tegangan/kapasitas baterai | 5V - 12V DC Input | Tampilan LED Bar / Digital |
| 4 | **Modul DC-DC Converter (Step-Down)** | Regulator penstabil tegangan ke 5V DC | Input 7.4V -> Output 5V DC | Menyuplai rail 5V komponen logic |
| 5 | **Perforated Proto-Board (Expansion)** | Papan bus distribusi VCC (5V) & GND | 5V DC Rail | Jalur distribusi daya rapi |
| 6 | **ESP32 DevKit v1** | Microcontroller utama (Wi-Fi + Bluetooth) | 5V DC (VIN) | Logika Utama (GPIO 3.3V) |
| 7 | **Sensor 7-in-1 NPK Soil** | Mengukur N, P, K, pH, Kelembapan, Temp, EC | 7.4V - 12V DC | RS485 Modbus RTU |
| 8 | **Modul MAX485 (TTL to RS485)** | Converter Signal Serial UART ke RS485 | 5V DC | UART (RX2/TX2 + Control DE/RE) |
| 9 | **Display LCD 16x2 + Backpack I2C** | Tampilan data sensor & status lokal di alat | 5V DC | I2C Bus (SDA/SCL) |
| 10 | **Modul RTC DS3231 I2C** | Real-Time Clock presisi jam offline lokal | 3.3V - 5V DC | I2C Bus (SDA/SCL) + Battery RTC |
| 11 | **Passive Buzzer 5V** | Alarm suara sinyal frekuensi lokal saat sensor abnormal | 5V DC (Drive via PWM) | Sinyal PWM / `tone()` / `ledcWriteTone()` |
| 12 | **4x Single Relay Module (1-Ch)** | Saklar independen untuk 4 Pompa DC | 5V DC (Coil Input) | High/Low Trigger GPIO |
| 13 | **4x Submersible DC Water Pump** | Pompa Nutrisi A, Nutrisi B, pH, & Utama | 7.4V - 12V DC | Daya diputus oleh Relay (NO/COM) |

---

### 2.2 Tabel Pemetaan Pinout Wiring ESP32 Lengkap

```text
+---------------------------------------------------------------------------------------+
|                                PINOUT MAPPING ESP32                                   |
+------------------------+----------------------+---------------------------------------+
| Komponen Hardware      | Pin Perangkat        | Terhubung ke Pin ESP32 / Power Rail   |
+------------------------+----------------------+---------------------------------------+
| Sistem Daya (Power)    | Baterai 2S (+)       | Saklar Rocker Switch (Terminal 1)     |
|                        | Saklar Output (T2)   | DC-DC Converter (IN+) & Voltmeter (+) |
|                        |                      | & Terminal COM 4x Relay (7.4V Line)   |
|                        | Baterai 2S (-)       | Common GND Rail (Semua komponen)      |
|                        | DC-DC Output (OUT+)  | VCC 5V Rail (Proto-Board Expansion)   |
|                        | DC-DC Output (OUT-)  | Common GND Rail                       |
+------------------------+----------------------+---------------------------------------+
| ESP32 DevKit v1        | VIN / 5V             | VCC 5V Rail (Output DC-DC Converter)  |
|                        | GND                  | Common GND Rail                       |
+------------------------+----------------------+---------------------------------------+
| MAX485 Converter       | VCC / GND            | VCC 5V Rail / Common GND Rail         |
|                        | RO (Receiver Out)    | GPIO 16 (RX2 ESP32)                   |
|                        | DI (Data In)         | GPIO 17 (TX2 ESP32)                   |
|                        | DE & RE (Short/Jumper| GPIO 4 (Direction Control ESP32)      |
|                        | A (RS485 Data +)     | Pin A (Kabel Kuning/Cokelat Sensor)   |
|                        | B (RS485 Data -)     | Pin B (Kabel Biru/Hijau Sensor)       |
+------------------------+----------------------+---------------------------------------+
| Sensor 7-in-1 NPK Soil | VCC                  | Positif Baterai 7.4V (Output Switch)  |
|                        | GND                  | Common GND Rail                       |
|                        | Pin A / Pin B        | Pin A / Pin B MAX485                  |
+------------------------+----------------------+---------------------------------------+
| Display LCD 16x2 I2C   | VCC / GND            | VCC 5V Rail / Common GND Rail         |
|                        | SDA                  | GPIO 21 (Shared I2C Bus ESP32)        |
|                        | SCL                  | GPIO 22 (Shared I2C Bus ESP32)        |
+------------------------+----------------------+---------------------------------------+
| Modul RTC DS3231       | VCC / GND            | VCC 5V Rail / Common GND Rail         |
|                        | SDA                  | GPIO 21 (Shared I2C Bus ESP32)        |
|                        | SCL                  | GPIO 22 (Shared I2C Bus ESP32)        |
+------------------------+----------------------+---------------------------------------+
| Passive Buzzer 5V      | VCC / Signal (+)     | GPIO 12 (PWM / tone Pin ESP32)        |
|                        | GND (-)              | Common GND Rail                       |
+------------------------+----------------------+---------------------------------------+
| 4x Modul Single Relay  | VCC / GND (Semua)    | VCC 5V Rail / Common GND Rail         |
|                        | IN Relay 1 (Pompa A) | GPIO 25 (ESP32)                       |
|                        | IN Relay 2 (Pompa B) | GPIO 26 (ESP32)                       |
|                        | IN Relay 3 (Pompa pH)| GPIO 27 (ESP32)                       |
|                        | IN Relay 4 (Utama)   | GPIO 14 (ESP32)                       |
|                        | COM 1, 2, 3, 4       | Positif Baterai 7.4V Line             |
|                        | NO 1, 2, 3, 4        | Positif Kabel 4x DC Pumps             |
+------------------------+----------------------+---------------------------------------+
| 4x DC Water Pumps      | Positif (+)          | Pin NO (Normally Open) Masing Relay   |
|                        | Negatif (-)          | Common GND Rail                       |
+------------------------+----------------------+---------------------------------------+
```

> [!NOTE]
> **Catatan Pemrograman Passive Buzzer**: Berbeda dengan Active Buzzer yang hanya membutuhkan sinyal `digitalWrite(HIGH)`, Passive Buzzer membutuhkan sinyal gelombang AC/PWM untuk menghasilkan suara. Pada ESP32, gunakan fungsi `ledcWriteTone(channel, frequency)` atau `tone(pin, frequency)` (misalnya frekuensi 2000Hz untuk suara bip peringatan).

> [!IMPORTANT]
> **Aturan Grounding Bersama (Common GND)**: Seluruh kabel ground (GND Baterai 2S, GND DC-DC Converter, GND ESP32, GND MAX485, GND LCD I2C, GND RTC DS3231, GND Voltmeter, GND 4 Relay, GND Buzzer, dan GND 4 Pompa DC) **WAJIB dihubungkan bersama pada Proto-Board Expansion** untuk mencegah timbulnya *floating voltage* dan kegagalan sinyal I2C / RS485.

---

## 3. Panduan Setup Cloud Services & API Key

### 3.1 Setup Firebase Console & Service Account

1. **Buat Project Firebase**:
   - Buka [Firebase Console](https://console.firebase.google.com/).
   - Buat project baru bernama `nutrixense-app`.
2. **Registrasi Aplikasi Android**:
   - Tambahkan Android App dengan Package Name: `com.example.nutrixense`.
   - Unduh file `google-services.json` dan letakkan di `android/app/google-services.json`.
3. **Konfigurasi Firestore Database**:
   - Koleksi data yang digunakan:
     - `sensor_data`: Log riwayat sensor real-time & batch sync offline.
     - `automation_config/dss`: Ambang batas (N, P, K, pH, Moisture, Temp, EC), durasi pulsa, dan status `buzzerMuted`.
     - `watering_schedules`: Jadwal penyiraman otomatis bulanan/harian.
     - `pump_activity_logs`: Catatan aktivitas eksekusi saklar pompa.
     - `threshold_alert_logs`: Catatan peringatan sensor out-of-bounds.
4. **Generate Service Account Private Key**:
   - Buka **Project Settings -> Service Accounts** -> Klik **Generate new private key**.
   - Simpan file ke `backend/serviceAccountKey.json`.

---

### 3.2 Setup HiveMQ Cloud MQTT Broker

1. **Buat Cluster HiveMQ Cloud**:
   - Cluster Hostname: `a8805b4f45744c3f9ac83882e423e0c0.s1.eu.hivemq.cloud`.
   - Port SSL/TLS: `8883`.
2. **Kredensial Akses**:
   - Username: `hasyim`
   - Password: `hasyimHiveMQTT@22`
3. **Skema Topic MQTT**:

| Topic MQTT | Direction | Fungsi & Deskripsi Payload | Contoh Format Payload JSON |
|---|---|---|---|
| `nutrixense/sensor` | ESP32 -> App & Backend | Mengirim data telemetry sensor real-time | `{"N":45, "P":120, "K":300, "pH":6.2, "Moisture":65, "Temp":27.5, "EC":1.8}` |
| `nutrixense/control` | App/Backend -> ESP32 | Perintah kontrol relay pompa (manual/auto) | `{"source":"manual_control", "manual_override":1, "relay1":1, "relay2":0, "relay3":0, "relay4":0}` |
| `nutrixense/status` | ESP32 -> App & Backend | LWT status online/offline hardware | `"online"` atau `"offline"` |
| `nutrixense/history` | ESP32 -> Backend | Batch sync data offline dari LittleFS | `{"N":45, ..., "timestamp":1722850000000}` |
| `nutrixense/config` | Backend -> ESP32 | Sync batas threshold & buzzer muted (Retained) | `{"min_nitrogen":80, "max_nitrogen":180, ..., "buzzer_muted":{"nitrogen":true}}` |

---

### 3.3 Setup Google AI Studio (Gemini API)

1. Dapatkan API Key dari [Google AI Studio](https://aistudio.google.com/).
2. Masukkan ke file `assets/config/gemini_config.json`:
   ```json
   {
     "apiKey": "AIzaSy_YOUR_ACTUAL_GEMINI_API_KEY",
     "modelName": "gemini-1.5-flash"
   }
   ```
3. Atau jalankan aplikasi dengan flag build `dart-define`:
   ```bash
   flutter run --dart-define=GEMINI_API_KEY="AIzaSy_YOUR_ACTUAL_GEMINI_API_KEY"
   ```

---

## 4. Deployment Backend Worker (Node.js & PM2)

### 4.1 Langkah Instalasi & Variabel Environment

1. Buka folder backend dan install dependensi:
   ```bash
   cd backend
   npm install
   cp .env.example .env
   ```
2. Isi file `.env`:
   ```env
   MQTT_HOST=a8805b4f45744c3f9ac83882e423e0c0.s1.eu.hivemq.cloud
   MQTT_PORT=8883
   MQTT_USER=hasyim
   MQTT_PASS=hasyimHiveMQTT@22
   MQTT_TOPIC=nutrixense/sensor
   MQTT_HISTORY_TOPIC=nutrixense/history
   MQTT_CONFIG_TOPIC=nutrixense/config
   SAVE_INTERVAL_MS=60000
   SAVE_REALTIME_SENSOR_TO_FIRESTORE=false
   FIRESTORE_COLLECTION=sensor_data
   ```

### 4.2 Menjalankan Backend 24 Jam di VPS dengan PM2

```bash
npm install -g pm2
pm2 start src/index.js --name nutrixense-backend
pm2 save
pm2 startup
```

---

## 5. Panduan Penggunaan Aplikasi Android NutriXense

Aplikasi NutriXense terdiri dari 5 menu navigasi utama:

1. **Dashboard Home**:
   - **Kartu Sensor Real-Time**: Tampilan 6+1 sensor (Nitrogen, Phosphorus, Potassium, pH, Kelembapan Tanah, Suhu Tanah, EC) dengan indikator warna status (**Normal (Hijau)**, **Low (Merah)**, **High (Oranye)**).
   - **Status Koneksi & Hardware**: Indikator status MQTT HiveMQ Cloud & sinyal online/offline ESP32.
   - **Grafik Tren Real-Time**: Kurva visualisasi pergerakan NPK secara langsung.
2. **Riwayat & Grafik (History)**:
   - Filter jangka waktu: **Hari Ini**, **7 Hari**, dan **30 Hari**.
   - Selector tab parameter untuk grafik tren individual.
   - Ringkasan statistik (Min, Max, Rata-rata) dan ekspor log data.
3. **NutriAI Insights (Rekomendasi Cerdas)**:
   - Diagnosa otomatis kondisi nutrisi tanah berbasis korelasi multi-sensor dan Gemini AI.
   - Rekomendasi dosis pupuk NPK & penyesuaian pH adjuster.
   - Modal Pengaturan Ambang Batas (Threshold Config) untuk penyesuaian batas aman sensor.
4. **Kontrol Pompa (Control Screen)**:
   - Saklar manual independen untuk 4 Pompa (Pompa Nutrisi A, Pompa Nutrisi B, Pompa pH Adjuster, Pompa Penyiraman Utama).
   - Saklar toggle mode Manual vs Mode Otomatis (DSS Rule-Based).
   - Pengaturan & tampilan Jadwal Penyiraman Otomatis (*Auto-Schedule*) lengkap dengan timer hitung mundur.
5. **Logs & Alerts (Pusat Peringatan)**:
   - Log riwayat notifikasi saat nilai sensor melebihi ambang aman.
   - Fitur **Buzzer Mute** per sensor (`buzzerMuted`) untuk mematikan alarm suara hardware pada parameter tertentu tanpa menghentikan pemantauan.
   - Log riwayat aktivitas saklar pompa.

---

## 6. Panduan Penyusunan Buku Manual / Book PDF

Gunakan susunan bab di bawah ini untuk pembuatan dokumen **Buku Panduan Teknis (Technical Manual / Buku TA)** resmi:

### 6.1 Struktur Bab & Isi Buku PDF

```text
KAVER BUKU (Judul, Logo, Nama Pengembang, Universitas/Institusi)
KATA PENGANTAR & DAFTAR ISI

BAB I: PENDAHULUAN & ARSITEKTUR SISTEM
  1.1 Latar Belakang & Tujuan NutriXense
  1.2 Arsitektur Sistem End-to-End (Catu Daya 2S - IoT - Cloud - AI - Mobile)
  1.3 Spesifikasi Parameter Sensor Nutrisi

BAB II: PERANGKAT HARDWARE IOT & SKEMA WIRING
  2.1 Spesifikasi Sistem Daya (2x 18650 Battery Pack 7.4V, Switch, & DC-DC Step-Down)
  2.2 Pemetaan Pinout Wiring ESP32, Proto-Board, LCD 16x2 I2C, & RTC DS3231
  2.3 Rangkaian Schematics Cirkit Designer & Aturan Common GND
  2.4 Tata Cara Pemrograman Passive Buzzer (Sinyal PWM / Tone Generation ESP32)
  2.5 Assembly & Testing Modul Relay 4-Channel & Pompa DC

BAB III: KONFIGURASI CLOUD SERVICES & API KEYS
  3.1 Setup Firebase Console, Firestore Database, & Service Account Key
  3.2 Setup HiveMQ Cloud Broker MQTT (SSL/TLS Port 8883) & Topik Komunikasi
  3.3 Setup Google AI Studio & Pengintegrasian Gemini API

BAB IV: DEPLOYMENT BACKEND WORKER (VPS NODE.JS)
  4.1 Persiapan Environment & Variabel Rahasia (.env)
  4.2 Manajemen Service 24 Jam Menggunakan PM2
  4.3 Sistem Pengiriman Notifikasi FCM & Synchronizer Retained Config

BAB V: PANDUAN PENGGUNAAN APLIKASI MOBILE ANDROID
  5.1 Instalasi & Persyaratan Perangkat Android
  5.2 Panduan Penggunaan Dashboard Real-Time & Status Hardware
  5.3 Panduan Analisis Riwayat & Ekspor Data (History)
  5.4 Panduan NutriAI Insights & Pengaturan Ambang Batas (Threshold Config)
  5.5 Panduan Pengoperasian Saklar Pompa Manual & Penjadwalan Otomatis

BAB VI: PEMELIHARAAN SISTEM & TROUBLESHOOTING
  6.1 Prosedur Pengisian Daya & Pemantauan Voltmeter Baterai 18650
  6.2 Kalibrasi Sensor 7-in-1 Soil NPK / pH / EC
  6.3 Solusi Troubleshooting Koneksi MQTT, Wi-Fi ESP32, & Gemini API

DAFTAR PUSTAKA & LAMPIRAN
  Lampiran 1: Data Sheet Komponen Hardware
  Lampiran 2: Potongan Kode Firmware ESP32 & Payload JSON Reference
```

### 6.2 Format Layout & Tipografi Buku PDF

1. **Spesifikasi Halaman**:
   - Ukuran Kertas: **A4 (210 x 297 mm)**.
   - Margin: Left = 3 cm, Right = 2 cm, Top = 2.5 cm, Bottom = 2.5 cm.
2. **Tipografi**:
   - Font Utama: **Inter** / **Roboto** / **Segoe UI** (Ukuran Body: 11pt, Line Height: 1.3).
   - Judul Bab (Heading 1): 18pt Bold (Warna Hijau NutriXense `#2E7D52`).
   - Sub Bab (Heading 2): 14pt Semi-Bold.
3. **Dokumentasi Visual**:
   - Berikan caption dan nomor pada setiap gambar (contoh: *Gambar 2.1: Skema Rangkaian Wiring Cirkit Designer NutriXense*).
   - Kotak Catatan / Callout (*Warning Box*): Berikan latar belakang warna lembut untuk menekankan aturan penting seperti *Common Grounding* dan *Regulasi Daya Baterai 2S*.

---
*NutriXense Technical Guidance · Dokumen Resmi Sistem Monitoring Nutrisi Tanaman IoT & AI*
