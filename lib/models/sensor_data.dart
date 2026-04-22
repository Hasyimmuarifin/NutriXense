// lib/models/sensor_data.dart
// Data models for all sensor readings in NutriXense

/// Represents a single nutrient/sensor reading
class SensorReading {
  final String label;
  final String unit;
  final double value;
  final double minNormal;
  final double maxNormal;
  final String icon; // emoji icon
  final int colorHex;

  const SensorReading({
    required this.label,
    required this.unit,
    required this.value,
    required this.minNormal,
    required this.maxNormal,
    required this.icon,
    required this.colorHex,
  });

  /// Returns status: 'Low', 'Normal', or 'High'
  String get status {
    if (value < minNormal) return 'Low';
    if (value > maxNormal) return 'High';
    return 'Normal';
  }

  /// Returns 0.0–1.0 progress for gauge display
  double get normalizedValue {
    final range = maxNormal * 1.4;
    return (value / range).clamp(0.0, 1.0);
  }
}

/// Time-series data point for history charts
class SensorDataPoint {
  final DateTime time;
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double ph;
  final double moisture;
  final double temperature;

  const SensorDataPoint({
    required this.time,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.ph,
    required this.moisture,
    required this.temperature,
  });
}

/// AI Insight recommendation model
class InsightCard {
  final String title;
  final String description;
  final String icon;
  final InsightSeverity severity;
  final String action;

  const InsightCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.severity,
    required this.action,
  });
}

enum InsightSeverity { critical, warning, good }

/// Pump controller model
class PumpController {
  final String id;
  final String name;
  final String nutrient;
  final String icon;
  bool isOn;
  bool isLoading;

  PumpController({
    required this.id,
    required this.name,
    required this.nutrient,
    required this.icon,
    this.isOn = false,
    this.isLoading = false,
  });
}