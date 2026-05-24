import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ThresholdConfigService {
  ThresholdConfigService._();

  static final ThresholdConfigService instance = ThresholdConfigService._();
  static const String _storageKey = 'nutrixense_threshold_config';

  final Map<String, double> _thresholds = {
    'min_nitrogen': 40,
    'max_nitrogen': 80,
    'min_phosphorus': 20,
    'max_phosphorus': 60,
    'min_potassium': 40,
    'max_potassium': 100,
    'min_ph': 5.8,
    'max_ph': 7.2,
    'min_moisture': 40,
    'max_moisture': 80,
    'min_temperature': 18,
    'max_temperature': 35,
    'min_ec': 1.0,
    'max_ec': 3.0,
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawConfig = prefs.getString(_storageKey);
    if (rawConfig == null) return;

    final decoded = jsonDecode(rawConfig);
    if (decoded is! Map<String, dynamic>) return;

    final savedThresholds = <String, double>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is num) {
        savedThresholds[entry.key] = value.toDouble();
      } else if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) savedThresholds[entry.key] = parsed;
      }
    }

    _thresholds.addAll(savedThresholds);
  }

  double value(String key, double fallback) {
    return _thresholds[key] ?? fallback;
  }

  Map<String, double> all() {
    return Map.unmodifiable(_thresholds);
  }

  Future<void> update(Map<String, double> thresholds) async {
    _thresholds.addAll(thresholds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_thresholds));
  }
}
