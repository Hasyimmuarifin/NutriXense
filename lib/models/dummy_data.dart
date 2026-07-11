// lib/models/dummy_data.dart
// Static dummy data used throughout the NutriXense app

import 'sensor_data.dart';

class DummyData {
  // ─── Current Sensor Readings ─────────────────────────────────────────────────
  static List<SensorReading> getCurrentReadings() => [
        const SensorReading(
          label: 'Nitrogen',
          unit: 'mg/kg',
          value: 38.5,
          minValue: 0,
          maxValue: 250,
          minNormal: 100.0,
          maxNormal: 200.0,
          icon: '🌿',
          colorHex: 0xFF2E7D52,
        ),
        const SensorReading(
          label: 'Fosfor',
          unit: 'mg/kg',
          value: 55.2,
          minValue: 0,
          maxValue: 100,
          minNormal: 20.0,
          maxNormal: 50.0,
          icon: '🔵',
          colorHex: 0xFF1565C0,
        ),
        const SensorReading(
          label: 'Kalium',
          unit: 'mg/kg',
          value: 92.8,
          minValue: 0,
          maxValue: 250,
          minNormal: 100.0,
          maxNormal: 200.0,
          icon: '🟡',
          colorHex: 0xFFFF8F00,
        ),
        const SensorReading(
          label: 'pH Level',
          unit: 'pH',
          value: 5.0,
          minValue: 0,
          maxValue: 14,
          minNormal: 4.5,
          maxNormal: 5.5,
          icon: '⚗️',
          colorHex: 0xFF7B1FA2,
        ),
        const SensorReading(
          label: 'Soil Moisture',
          unit: '%',
          value: 64.0,
          minValue: 0,
          maxValue: 100,
          minNormal: 40.0,
          maxNormal: 70.0,
          icon: '💧',
          colorHex: 0xFF0288D1,
        ),
        const SensorReading(
          label: 'Temperature',
          unit: '°C',
          value: 22.4,
          minValue: 0,
          maxValue: 50,
          minNormal: 18.0,
          maxNormal: 25.0,
          icon: '🌡️',
          colorHex: 0xFFE53935,
        ),
      ];

  // ─── 7-Day Time Series History ────────────────────────────────────────────────
  static List<SensorDataPoint> getHistoryData({int days = 7}) {
    final now = DateTime.now();
    final List<SensorDataPoint> data = [];

    // Generate hourly data for 'days' days
    final totalPoints = days * 6; // one point per 4 hours
    for (int i = totalPoints; i >= 0; i--) {
      final time = now.subtract(Duration(hours: i * 4));
      // Add slight variation for realistic dummy data
      final t = i / totalPoints;
      data.add(SensorDataPoint(
        time: time,
        nitrogen: 38.5 + 15 * _wave(t, 0.0),
        phosphorus: 55.2 + 10 * _wave(t, 1.2),
        potassium: 92.8 + 12 * _wave(t, 2.4),
        ph: 5.0 + 0.4 * _wave(t, 0.8),
        moisture: 64.0 + 12 * _wave(t, 1.6),
        temperature: 22.4 + 2.0 * _wave(t, 3.0),
        ec: 1.3 + 0.3 * _wave(t, 2.0),
      ));
    }
    return data;
  }

  // Simple wave function for realistic-looking dummy sensor data
  static double _wave(double t, double offset) {
    return (0.5 * (1 + (t * 6.28 + offset).abs() % 6.28 / 3.14 - 1));
  }

  // ─── AI Insights ─────────────────────────────────────────────────────────────
  static List<InsightCard> getInsights() => [
        const InsightCard(
          title: 'Low Nitrogen Detected',
          description:
              'Nitrogen levels are below the tea crop normal range (38.5 mg/kg vs 100–200 mg/kg). Plants may show yellowing of older leaves.',
          icon: '⚠️',
          severity: InsightSeverity.kritis,
          action:
              'Apply nitrogen-rich fertilizer (NPK 20-10-10). Activate Pump A for 5 minutes.',
        ),
        const InsightCard(
          title: 'pH Normal untuk Teh',
          description:
              'Soil pH of 5.0 is within the tea crop normal range of 4.5–5.5.',
          icon: '✅',
          severity: InsightSeverity.baik,
          action:
              'Maintain the current media acidity and avoid excessive liming.',
        ),
        const InsightCard(
          title: 'Kadar Kalium Rendah',
          description:
              'Kalium 92.8 mg/kg sedikit di bawah rentang normal teh (100–200 mg/kg). Kekurangan K dapat menurunkan ketahanan tanaman.',
          icon: '🟡',
          severity: InsightSeverity.awas,
          action:
              'Tambahkan kalium bertahap dan ukur ulang setelah larutan merata.',
        ),
        const InsightCard(
          title: 'Fosfor Optimal',
          description:
              'Fosfor 55.2 mg/kg sedikit di atas rentang normal teh (20–50 mg/kg). Pantau agar tidak terus meningkat.',
          icon: '✅',
          severity: InsightSeverity.awas,
          action:
              'Tunda penambahan fosfor sementara dan pantau pembacaan berikutnya.',
        ),
        const InsightCard(
          title: 'Moisture Levels Good',
          description:
              'Soil moisture at 64% is within the healthy range. Plants have adequate water availability.',
          icon: '💧',
          severity: InsightSeverity.baik,
          action: 'Continue current irrigation schedule.',
        ),
        const InsightCard(
          title: 'Temperature Normal',
          description:
              'Soil temperature at 22.4°C is within the tea crop normal range of 18–25°C.',
          icon: '🌡️',
          severity: InsightSeverity.baik,
          action: 'No action required. Monitor during peak afternoon heat.',
        ),
      ];

  // ─── Pumps ────────────────────────────────────────────────────────────────────
  static List<PumpController> getPumps() => [
        PumpController(
          id: 'pump_a',
          name: 'Pompa A',
          nutrient: 'Nitrogen (N)',
          iconPath: 'assets/icons/leaf.png',
          isOn: false,
        ),
        PumpController(
          id: 'pump_b',
          name: 'Pompa B',
          nutrient: 'Fosfor (P)',
          iconPath: 'assets/icons/root.png',
          isOn: false,
        ),
        PumpController(
          id: 'pump_c',
          name: 'Pompa C',
          nutrient: 'Kalium (K)',
          iconPath: 'assets/icons/crop.png',
          isOn: false,
        ),
        PumpController(
          id: 'pump_d',
          name: 'Pompa D',
          nutrient: 'Air (H2O)',
          iconPath: 'assets/icons/water.png',
          isOn: false,
        ),
      ];

  // ─── Mini chart data for Home screen ─────────────────────────────────────────
  static List<double> getMiniChartData(String sensor) {
    final Map<String, List<double>> charts = {
      'Nitrogen': [42, 40, 37, 35, 38, 36, 38.5],
      'Fosfor': [50, 53, 56, 54, 58, 55, 55.2],
      'Kalium': [85, 88, 90, 93, 91, 95, 92.8],
      'pH Level': [5.1, 5.0, 4.9, 5.0, 5.2, 4.8, 5.0],
      'Soil Moisture': [60, 65, 68, 62, 64, 66, 64.0],
      'Temperature': [21, 22, 23, 22, 21, 23, 22.4],
    };
    return charts[sensor] ?? [0, 0, 0, 0, 0, 0, 0];
  }
}
