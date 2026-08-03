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

    // Filter out N, P, K as individual alerts since they follow EC status
    final abnormalReadings = readings.where((reading) {
      final key = _sensorKeyForReading(reading);
      if (key == 'nitrogen' || key == 'phosphorus' || key == 'potassium') {
        return false;
      }
      return reading.status != 'Normal' && !mutedSensorKeys.contains(key);
    }).toList();

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

    final alertData = _buildDynamicAlertTitleAndMessage(readingsToAlert, readings);
    final title = alertData['title']!;
    final message = alertData['message']!;

    if (message.isEmpty) return;

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
        'title': title,
        'message': message,
      });
    } on PlatformException catch (error) {
      debugPrint('Alert notification failed: ${error.message}');
    }
  }

  Map<String, String> _buildDynamicAlertTitleAndMessage(
    List<SensorReading> readingsToAlert,
    List<SensorReading> allReadings,
  ) {
    final ecReading = allReadings.cast<SensorReading?>().firstWhere(
          (r) => r != null && _sensorKeyForReading(r) == 'ec',
          orElse: () => null,
        );
    final nReading = allReadings.cast<SensorReading?>().firstWhere(
          (r) => r != null && _sensorKeyForReading(r) == 'nitrogen',
          orElse: () => null,
        );
    final pReading = allReadings.cast<SensorReading?>().firstWhere(
          (r) => r != null && _sensorKeyForReading(r) == 'phosphorus', 
          orElse: () => null,
        );
    final kReading = allReadings.cast<SensorReading?>().firstWhere(
          (r) => r != null && _sensorKeyForReading(r) == 'potassium',
          orElse: () => null,
        );

    final activeAlerts = readingsToAlert.where((r) {
      final key = _sensorKeyForReading(r);
      return key == 'ph' || key == 'moisture' || key == 'temperature' || key == 'ec';
    }).toList();

    if (activeAlerts.isEmpty) {
      return {'title': 'Peringatan Sensor', 'message': ''};
    }

    final isEcLow = ecReading != null &&
        activeAlerts.any((r) => _sensorKeyForReading(r) == 'ec' && r.status == 'Low');

    String title;
    String message;

    if (activeAlerts.length == 1) {
      final alert = activeAlerts.first;
      final key = _sensorKeyForReading(alert);
      final isLow = alert.status == 'Low';

      if (key == 'ec') {
        if (isLow) {
          title = 'Nutrisi Tanaman Menurun';
          final nStr = nReading != null ? '${nReading.value.toStringAsFixed(0)} mg/kg' : '-';
          final pStr = pReading != null ? '${pReading.value.toStringAsFixed(0)} mg/kg' : '-';
          final kStr = kReading != null ? '${kReading.value.toStringAsFixed(0)} mg/kg' : '-';
          final minEcStr = ecReading!.minNormal.toStringAsFixed(1);
          message = 'Nilai EC (${ecReading.value.toStringAsFixed(1)} mS/cm) di bawah batas minimal normal ($minEcStr mS/cm). Estimasi tren NPK sekarang: (N = $nStr, P = $pStr, K = $kStr).';
        } else {
          title = 'Peringatan Nutrisi Tinggi';
          message = 'Nilai EC (${alert.value.toStringAsFixed(1)} mS/cm) di atas batas maksimal normal (${alert.maxNormal.toStringAsFixed(1)} mS/cm).';
        }
      } else if (key == 'ph') {
        title = isLow ? 'Peringatan pH Tanah Terlalu Asam' : 'Peringatan pH Tanah Terlalu Basa';
        final dir = isLow
            ? 'di bawah batas minimal normal ${alert.minNormal.toStringAsFixed(1)} pH'
            : 'di atas batas maksimal normal ${alert.maxNormal.toStringAsFixed(1)} pH';
        message = 'Nilai pH (${alert.value.toStringAsFixed(1)} pH) $dir.';
      } else if (key == 'temperature') {
        title = isLow ? 'Peringatan Suhu Tanah Rendah' : 'Peringatan Suhu Tanah Tinggi';
        final dir = isLow
            ? 'di bawah batas minimal normal ${alert.minNormal.toStringAsFixed(1)} °C'
            : 'di atas batas maksimal normal ${alert.maxNormal.toStringAsFixed(1)} °C';
        message = 'Suhu tanah (${alert.value.toStringAsFixed(1)} °C) $dir.';
      } else if (key == 'moisture') {
        title = isLow ? 'Peringatan Kelembapan Tanah Rendah' : 'Peringatan Kelembapan Tanah Tinggi';
        final dir = isLow
            ? 'di bawah batas minimal normal ${alert.minNormal.toStringAsFixed(0)} %'
            : 'di atas batas maksimal normal ${alert.maxNormal.toStringAsFixed(0)} %';
        message = 'Kelembapan tanah (${alert.value.toStringAsFixed(0)} %) $dir.';
      } else {
        title = 'Peringatan Sensor';
        message = _formatAlertLine(alert);
      }
    } else {
      title = isEcLow ? 'Peringatan Nutrisi & Lingkungan' : 'Peringatan Parameter Lingkungan';
      final lines = <String>[];
      for (final alert in activeAlerts) {
        final key = _sensorKeyForReading(alert);
        if (key == 'ec' && alert.status == 'Low') {
          final nStr = nReading != null ? '${nReading.value.toStringAsFixed(0)} mg/kg' : '-';
          final pStr = pReading != null ? '${pReading.value.toStringAsFixed(0)} mg/kg' : '-';
          final kStr = kReading != null ? '${kReading.value.toStringAsFixed(0)} mg/kg' : '-';
          final minEcStr = ecReading!.minNormal.toStringAsFixed(1);
          lines.add('• EC (${ecReading.value.toStringAsFixed(1)} mS/cm) di bawah batas minimal normal ($minEcStr mS/cm). Estimasi tren NPK sekarang: (N = $nStr, P = $pStr, K = $kStr).');
        } else {
          lines.add('• ${_formatAlertLine(alert)}');
        }
      }
      message = lines.join('\n');
    }

    return {'title': title, 'message': message};
  }

  String _formatAlertLine(SensorReading reading) {
    final sensorLabel = _alertSensorLabel(reading.label);
    final direction = (reading.status == 'Low' || reading.status == 'Tren Menurun')
        ? 'di bawah batas minimal'
        : 'di atas batas maksimal';
    final threshold =
        (reading.status == 'Low' || reading.status == 'Tren Menurun')
            ? reading.minNormal
            : reading.maxNormal;

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
