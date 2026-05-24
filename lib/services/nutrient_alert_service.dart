import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/sensor_data.dart';

class NutrientAlertService {
  NutrientAlertService._();

  static final NutrientAlertService instance = NutrientAlertService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.nutrixense/alerts');
  static const Duration _repeatInterval = Duration(minutes: 5);

  final Map<String, String> _lastStatuses = {};
  final Map<String, DateTime> _lastAlertTimes = {};

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initializeAlerts');
    } on PlatformException catch (error) {
      // Alerts should never interrupt sensor monitoring if Android rejects setup.
      debugPrint('Alert initialization failed: ${error.message}');
    }
  }

  Future<void> handleReadings(List<SensorReading> readings) async {
    final now = DateTime.now();
    final abnormalReadings =
        readings.where((reading) => reading.status != 'Normal').toList();

    if (abnormalReadings.isEmpty) {
      _lastStatuses.clear();
      return;
    }

    final readingsToAlert = abnormalReadings.where((reading) {
      final previousStatus = _lastStatuses[reading.label];
      final lastAlertTime = _lastAlertTimes[reading.label];
      final repeatDue = lastAlertTime == null ||
          now.difference(lastAlertTime) >= _repeatInterval;

      return previousStatus != reading.status || repeatDue;
    }).toList();

    for (final reading in readings) {
      if (reading.status == 'Normal') {
        _lastStatuses.remove(reading.label);
      } else {
        _lastStatuses[reading.label] = reading.status;
      }
    }

    if (readingsToAlert.isEmpty) return;

    for (final reading in readingsToAlert) {
      _lastAlertTimes[reading.label] = now;
    }

    final message = readingsToAlert.map(_formatAlertLine).join('\n');

    try {
      await _channel.invokeMethod<void>('showNutrientAlert', {
        'title': 'Nutrient threshold alert',
        'message': message,
      });
    } on PlatformException catch (error) {
      debugPrint('Alert notification failed: ${error.message}');
    }
  }

  String _formatAlertLine(SensorReading reading) {
    final direction = reading.status == 'Low' ? 'below' : 'above';
    final threshold =
        reading.status == 'Low' ? reading.minNormal : reading.maxNormal;

    return '${reading.label}: ${reading.value.toStringAsFixed(1)} ${reading.unit} '
        'is $direction ${threshold.toStringAsFixed(1)} ${reading.unit}';
  }
}
