// lib/models/sensor_data.dart
// Data models for all sensor readings in NutriXense
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single nutrient/sensor reading
class SensorReading {
  final String label;
  final String unit;
  final double value;
  final double minNormal;
  final double maxNormal;
  final String icon;
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

  double get normalizedValue {
    final range = maxNormal - minNormal;
    if (range == 0) return 0;
    return ((value - minNormal) / range).clamp(0, 1);
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
      nitrogen: (data['nitrogen'] ?? 0).toDouble(),
      phosphorus: (data['phosphorus'] ?? 0).toDouble(),
      potassium: (data['potassium'] ?? 0).toDouble(),
      ph: (data['ph'] ?? 0).toDouble(),
      moisture: (data['moisture'] ?? 0).toDouble(),
      temperature: (data['temperature'] ?? 0).toDouble(),
      time: (data['timestamp'] as Timestamp).toDate(),
    );
  }
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