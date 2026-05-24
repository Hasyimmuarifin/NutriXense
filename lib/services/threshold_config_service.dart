class ThresholdConfigService {
  ThresholdConfigService._();

  static final ThresholdConfigService instance = ThresholdConfigService._();

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

  double value(String key, double fallback) {
    return _thresholds[key] ?? fallback;
  }

  void update(Map<String, double> thresholds) {
    _thresholds.addAll(thresholds);
  }
}
