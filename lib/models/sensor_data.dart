// lib/models/sensor_data.dart
// Data models for all sensor readings in NutriXense
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single nutrient/sensor reading
class SensorReading {
  final String label;
  final String unit;
  final double value;
  final double minValue;
  final double maxValue;
  final double minNormal;
  final double maxNormal;
  final String icon;
  final int colorHex;

  const SensorReading({
    required this.label,
    required this.unit,
    required this.value,
    required this.minValue,
    required this.maxValue,
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

  double get normalizedValue {
    final range = maxValue - minValue;
    if (range == 0) return 0;
    return ((value - minValue) / range).clamp(0.0, 1.0);
  }
}

/// Time-series data point for history charts
class SensorDataPoint {
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double ph;
  final double moisture;
  final double temperature;
  final DateTime time;

  const SensorDataPoint({
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.ph,
    required this.moisture,
    required this.temperature,
    required this.time,
  });

  factory SensorDataPoint.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return SensorDataPoint(
      nitrogen: _readDouble(data, ['nitrogen', 'N', 'n']),
      phosphorus: _readDouble(data, ['phosphorus', 'P', 'p']),
      potassium: _readDouble(data, ['potassium', 'K', 'k']),
      ph: _readDouble(data, ['ph', 'pH', 'PH']),
      moisture: _readDouble(data, ['moisture', 'Moisture']),
      temperature: _readDouble(data, ['temperature', 'Temp', 'temp']),
      time: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  static double _readDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }

    return 0;
  }
}

/// AI Insight recommendation model
class InsightCard {
  final String title;
  final String description;
  final String icon;
  final InsightSeverity severity;
  final String action;
  final String recommendation;

  const InsightCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.severity,
    required this.action,
    this.recommendation = '',
  });
}

enum InsightSeverity { kritis, awas, baik }

/// Pump controller model
class PumpController {
  final String id;
  final String name;
  final String nutrient;
  final String iconPath;
  bool isOn;
  bool isLoading;

  PumpController({
    required this.id,
    required this.name,
    required this.nutrient,
    required this.iconPath,
    this.isOn = false,
    this.isLoading = false,
  });
}
