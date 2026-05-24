import 'package:flutter/foundation.dart';

import '../models/sensor_data.dart';

class AlertCountService {
  AlertCountService._();

  static final AlertCountService instance = AlertCountService._();

  final ValueNotifier<int> alertCount = ValueNotifier<int>(0);

  void updateFromAiRecommendation({
    required int criticalCount,
    required int warningCount,
  }) {
    alertCount.value = criticalCount + warningCount;
  }

  void updateFromSensorReadings(List<SensorReading> readings) {
    alertCount.value =
        readings.where((reading) => reading.status != 'Normal').length;
  }
}
