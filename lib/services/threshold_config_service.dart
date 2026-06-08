import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThresholdConfigService extends ChangeNotifier {
  ThresholdConfigService._();

  static final ThresholdConfigService instance = ThresholdConfigService._();
  static const String _storageKey = 'nutrixense_threshold_config';
  static const Map<String, double> _teaPotThresholds = {
    'min_nitrogen': 80,
    'max_nitrogen': 180,
    'min_phosphorus': 100,
    'max_phosphorus': 300,
    'min_potassium': 250,
    'max_potassium': 650,
    'min_ph': 4.5,
    'max_ph': 5.5,
    'min_moisture': 40,
    'max_moisture': 70,
    'min_temperature': 18,
    'max_temperature': 25,
    'min_ec': 1.2,
    'max_ec': 2.5,
  };
  static const Map<String, double> _legacyDefaultThresholds = {
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

  final Map<String, double> _thresholds = Map.of(_teaPotThresholds);

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

    if (_isLegacyDefaultConfig(savedThresholds)) {
      _thresholds
        ..clear()
        ..addAll(_teaPotThresholds);
      await prefs.setString(_storageKey, jsonEncode(_thresholds));
      return;
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
    notifyListeners();
  }

  bool _isLegacyDefaultConfig(Map<String, double> thresholds) {
    if (thresholds.length != _legacyDefaultThresholds.length) return false;

    for (final entry in _legacyDefaultThresholds.entries) {
      final value = thresholds[entry.key];
      if (value == null || (value - entry.value).abs() > 0.0001) {
        return false;
      }
    }

    return true;
  }
}
