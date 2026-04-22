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
          minNormal: 40.0,
          maxNormal: 80.0,
          icon: '🌿',
          colorHex: 0xFF2E7D52,
        ),
        const SensorReading(
          label: 'Phosphorus',
          unit: 'mg/kg',
          value: 55.2,
          minNormal: 30.0,
          maxNormal: 70.0,
          icon: '🔵',
          colorHex: 0xFF1565C0,
        ),
        const SensorReading(
          label: 'Potassium',
          unit: 'mg/kg',
          value: 92.8,
          minNormal: 60.0,
          maxNormal: 90.0,
          icon: '🟡',
          colorHex: 0xFFFF8F00,
        ),
        const SensorReading(
          label: 'pH Level',
          unit: 'pH',
          value: 5.8,
          minNormal: 6.0,
          maxNormal: 7.5,
          icon: '⚗️',
          colorHex: 0xFF7B1FA2,
        ),
        const SensorReading(
          label: 'Soil Moisture',
          unit: '%',
          value: 64.0,
          minNormal: 40.0,
          maxNormal: 70.0,
          icon: '💧',
          colorHex: 0xFF0288D1,
        ),
        const SensorReading(
          label: 'Temperature',
          unit: '°C',
          value: 28.4,
          minNormal: 20.0,
          maxNormal: 30.0,
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
        nitrogen:  38.5 + 15 * _wave(t, 0.0),
        phosphorus: 55.2 + 10 * _wave(t, 1.2),
        potassium:  92.8 + 12 * _wave(t, 2.4),
        ph:          5.8 + 0.8 * _wave(t, 0.8),
        moisture:   64.0 + 12 * _wave(t, 1.6),
        temperature: 28.4 + 3.0 * _wave(t, 3.0),
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
              'Nitrogen levels are below optimal range (38.5 mg/kg vs 40–80 mg/kg). Plants may show yellowing of older leaves.',
          icon: '⚠️',
          severity: InsightSeverity.critical,
          action: 'Apply nitrogen-rich fertilizer (NPK 20-10-10). Activate Pump A for 5 minutes.',
        ),
        const InsightCard(
          title: 'pH Too Acidic',
          description:
              'Soil pH of 5.8 is below the ideal range of 6.0–7.5. Acidic soil limits nutrient absorption.',
          icon: '🔴',
          severity: InsightSeverity.warning,
          action: 'Apply agricultural lime or dolomite to raise pH gradually.',
        ),
        const InsightCard(
          title: 'High Potassium Levels',
          description:
              'Potassium at 92.8 mg/kg exceeds optimal range (60–90 mg/kg). Excess K may block calcium uptake.',
          icon: '🟡',
          severity: InsightSeverity.warning,
          action: 'Pause Pump C until K levels normalize. Flush soil with clean water.',
        ),
        const InsightCard(
          title: 'Phosphorus is Optimal',
          description:
              'Phosphorus at 55.2 mg/kg is within the ideal range. Root development and flowering should be healthy.',
          icon: '✅',
          severity: InsightSeverity.good,
          action: 'Maintain current Pump B schedule.',
        ),
        const InsightCard(
          title: 'Moisture Levels Good',
          description:
              'Soil moisture at 64% is within the healthy range. Plants have adequate water availability.',
          icon: '💧',
          severity: InsightSeverity.good,
          action: 'Continue current irrigation schedule.',
        ),
        const InsightCard(
          title: 'Temperature Normal',
          description:
              'Soil temperature at 28.4°C is within optimal range. Microbial activity and nutrient cycling are active.',
          icon: '🌡️',
          severity: InsightSeverity.good,
          action: 'No action required. Monitor during peak afternoon heat.',
        ),
      ];

  // ─── Pumps ────────────────────────────────────────────────────────────────────
  static List<PumpController> getPumps() => [
        PumpController(
          id: 'pump_a',
          name: 'Pump A',
          nutrient: 'Nitrogen (N)',
          icon: '🌿',
          isOn: false,
        ),
        PumpController(
          id: 'pump_b',
          name: 'Pump B',
          nutrient: 'Phosphorus (P)',
          icon: '🔵',
          isOn: true,
        ),
        PumpController(
          id: 'pump_c',
          name: 'Pump C',
          nutrient: 'Potassium (K)',
          icon: '🟡',
          isOn: false,
        ),
      ];

  // ─── Mini chart data for Home screen ─────────────────────────────────────────
  static List<double> getMiniChartData(String sensor) {
    final Map<String, List<double>> charts = {
      'Nitrogen':    [42, 40, 37, 35, 38, 36, 38.5],
      'Phosphorus':  [50, 53, 56, 54, 58, 55, 55.2],
      'Potassium':   [85, 88, 90, 93, 91, 95, 92.8],
      'pH Level':    [6.2, 6.0, 5.9, 5.8, 6.0, 5.7, 5.8],
      'Soil Moisture':[60, 65, 68, 62, 64, 66, 64.0],
      'Temperature': [27, 28, 29, 28, 27, 29, 28.4],
    };
    return charts[sensor] ?? [0, 0, 0, 0, 0, 0, 0];
  }
}