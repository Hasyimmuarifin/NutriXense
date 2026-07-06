import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/sensor_data.dart';
import 'threshold_config_service.dart';
import 'threshold_notification_cooldown_service.dart';

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
      await _channel.invokeMethod<void>('stopBackgroundAlertMonitor');
    } on PlatformException catch (error) {
      // Alerts should never interrupt sensor monitoring if Android rejects setup.
      debugPrint('Alert initialization failed: ${error.message}');
    }
  }

  Future<void> syncBackgroundAlertConfig({
    Set<String> mutedSensorKeys = const {},
  }) async {
    try {
      await _channel.invokeMethod<void>('syncBackgroundThresholds', {
        'thresholdsJson': jsonEncode(
          _backgroundConfig(mutedSensorKeys: mutedSensorKeys),
        ),
      });
    } on PlatformException catch (error) {
      debugPrint('Background alert config sync failed: ${error.message}');
    }
  }

  Future<void> handleReadings(
    List<SensorReading> readings, {
    Set<String> mutedSensorKeys = const {},
  }) async {
    final now = DateTime.now();
    final abnormalReadings = readings
        .where((reading) =>
            reading.status != 'Normal' &&
            !mutedSensorKeys.contains(_sensorKeyForReading(reading)))
        .toList();

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
      final sensorKey = _sensorKeyForReading(reading);
      if (reading.status == 'Normal' || mutedSensorKeys.contains(sensorKey)) {
        _lastStatuses.remove(reading.label);
        _lastAlertTimes.remove(reading.label);
      } else {
        _lastStatuses[reading.label] = reading.status;
      }
    }

    if (readingsToAlert.isEmpty) return;

    for (final reading in readingsToAlert) {
      _lastAlertTimes[reading.label] = now;
    }

    final message = readingsToAlert.map(_formatAlertLine).join('\n');
    final canShowNotification = await ThresholdNotificationCooldownService
        .instance
        .tryAcquireNotificationSlot();

    if (!canShowNotification) {
      debugPrint(
        'Threshold alert notification suppressed by shared 5-minute cooldown.',
      );
      return;
    }

    try {
      await _channel.invokeMethod<void>('showNutrientAlert', {
        'title': 'Peringatan Nutrisi Tanaman',
        'message': message,
      });
    } on PlatformException catch (error) {
      debugPrint('Alert notification failed: ${error.message}');
    }
  }

  String _formatAlertLine(SensorReading reading) {
    final sensorLabel = _alertSensorLabel(reading.label);
    final direction = reading.status == 'Low'
        ? 'di bawah batas minimal'
        : 'di atas batas maksimal';
    final threshold =
        reading.status == 'Low' ? reading.minNormal : reading.maxNormal;

    return '$sensorLabel: ${reading.value.toStringAsFixed(1)} ${reading.unit} '
        '$direction ${threshold.toStringAsFixed(1)} ${reading.unit}';
  }

  String _alertSensorLabel(String label) {
    switch (label) {
      case 'pH Level':
        return 'pH';
      case 'Moisture':
      case 'Soil Moisture':
        return 'Kelembapan';
      case 'Temp':
      case 'Temperature':
        return 'Suhu';
      case 'Electrical Conductivity':
        return 'EC';
      default:
        return label;
    }
  }

  Map<String, dynamic> _backgroundConfig({
    Set<String> mutedSensorKeys = const {},
  }) {
    return {
      ...ThresholdConfigService.instance.all(),
      'buzzer_muted': {
        'nitrogen': mutedSensorKeys.contains('nitrogen'),
        'phosphorus': mutedSensorKeys.contains('phosphorus'),
        'potassium': mutedSensorKeys.contains('potassium'),
        'ph': mutedSensorKeys.contains('ph'),
        'moisture': mutedSensorKeys.contains('moisture'),
        'temperature': mutedSensorKeys.contains('temperature'),
        'ec': mutedSensorKeys.contains('ec'),
      },
    };
  }

  String _sensorKeyForReading(SensorReading reading) {
    switch (reading.label) {
      case 'Nitrogen':
        return 'nitrogen';
      case 'Fosfor':
        return 'phosphorus';
      case 'Kalium':
        return 'potassium';
      case 'pH Level':
        return 'ph';
      case 'Moisture':
        return 'moisture';
      case 'Temp':
        return 'temperature';
      case 'Electrical Conductivity':
        return 'ec';
      default:
        return reading.label.toLowerCase().replaceAll(' ', '_');
    }
  }
}
