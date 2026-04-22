# 🌱 NutriXense

**IoT-Based Plant Nutrient Monitoring & Control App**

NutriXense is a production-grade Flutter application for monitoring and controlling plant nutrients via IoT sensors and smart pumps.

---

## 📱 Features

| # | Screen | Description |
|---|--------|-------------|
| 1 | **Home** | Live dashboard — 6 sensor cards (N, P, K, pH, Moisture, Temp) + real-time NPK trend chart |
| 2 | **History** | Time-series charts with Today / 7 Days / 30 Days filter, sensor selector, stats summary, data table |
| 3 | **Scan** | AI plant scan simulation — camera viewfinder, scan animation, detailed health report |
| 4 | **Insights** | AI recommendation cards with severity filters, NutriAI summary, expandable action cards |
| 5 | **Control** | Pump A/B/C toggle with loading state, IoT gateway status, auto-schedule display |

---

## 🗂️ Project Structure

```
lib/
├── main.dart                    # App entry + Bottom Nav
├── theme/
│   └── app_theme.dart           # Material 3 color + typography
├── models/
│   ├── sensor_data.dart         # Data models
│   └── dummy_data.dart          # Static dummy data provider
├── screens/
│   ├── home_screen.dart         # Monitoring dashboard
│   ├── history_screen.dart      # Time-series history
│   ├── scan_screen.dart         # AI plant scan
│   ├── insights_screen.dart     # AI recommendations
│   └── control_screen.dart      # Pump controller
└── widgets/
    ├── sensor_card.dart          # Individual sensor card
    ├── insight_card_widget.dart  # Insight/recommendation card
    ├── mini_line_chart.dart      # Compact sparkline chart
    ├── pump_card.dart            # Pump toggle card
    └── section_header.dart      # Reusable section title
```

---

## 🚀 Getting Started

```bash
# Install dependencies
flutter pub get

# Run on Android device/emulator
flutter run

# Build APK
flutter build apk --release
```

---

## 📦 Dependencies

- `fl_chart` — Beautiful, production-grade Flutter charts
- `animate_do` — Smooth entrance animations  
- `intl` — Date/time formatting

---

## 🎨 Design System

| Token | Value |
|-------|-------|
| Primary Green | `#2E7D52` |
| Primary Blue | `#1565C0` |
| Status Low | `#E53935` (red) |
| Status Normal | `#43A047` (green) |
| Status High | `#FF8F00` (amber) |
| Border Radius | 16–20px cards, 12px chips |
| Design System | Material 3 |

---

## 🔌 IoT Integration (Future)

The app is designed for seamless MQTT/WebSocket integration:
- Replace `DummyData` methods with stream subscriptions
- Use `mqtt_client` package for real-time sensor data
- Add Firebase Realtime Database for cloud history

---

*Built with Flutter · Designed for agriculture + technology*