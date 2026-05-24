class ThresholdConfigService {
  ThresholdConfigService._();

  static final ThresholdConfigService instance = ThresholdConfigService._();

  final Map<String, double> _thresholds = {
    'min_nitrogen': 40,
    'min_phosphorus': 20,
    'min_potassium': 40,
    'min_ph': 5.8,
    'min_moisture': 40,
    'min_temperature': 18,
    'min_ec': 1.0,
  };

  double value(String key, double fallback) {
    return _thresholds[key] ?? fallback;
  }

  void update(Map<String, double> thresholds) {
    _thresholds.addAll(thresholds);
  }
}
