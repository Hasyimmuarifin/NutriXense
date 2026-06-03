import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'ai_pump_automation_service.dart';
import 'threshold_config_service.dart';

class RuleBasedPumpAutomationService {
  static final RuleBasedPumpAutomationService instance =
      RuleBasedPumpAutomationService._();

  factory RuleBasedPumpAutomationService({
    FirebaseFirestore? firestore,
    AiPumpAutomationService? pumpAutomationService,
    Duration checkInterval = const Duration(minutes: 1),
  }) {
    return RuleBasedPumpAutomationService._(
      firestore: firestore,
      pumpAutomationService: pumpAutomationService,
      checkInterval: checkInterval,
    );
  }

  RuleBasedPumpAutomationService._({
    FirebaseFirestore? firestore,
    AiPumpAutomationService? pumpAutomationService,
    this.checkInterval = const Duration(minutes: 1),
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _pumpAutomationService =
            pumpAutomationService ?? AiPumpAutomationService();

  final FirebaseFirestore _firestore;
  final AiPumpAutomationService _pumpAutomationService;
  final ThresholdConfigService _thresholdConfigService =
      ThresholdConfigService.instance;
  final Duration checkInterval;

  Timer? _timer;
  bool _isChecking = false;
  Map<int, DateTime> _lastActivationByRelay = {};

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _checkLatestReading();
    _timer = Timer.periodic(checkInterval, (_) => _checkLatestReading());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkLatestReading() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final snapshot = await _firestore
          .collection('sensor_data')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return;

      final reading =
          _RuleSensorReading.fromFirestore(snapshot.docs.first.data());
      final relays = _relaysForLowParameters(reading);
      if (relays.isEmpty) return;

      final now = DateTime.now();
      final allowedRelays = relays.where((relay) {
        final lastActivation = _lastActivationByRelay[relay];
        return lastActivation == null ||
            now.difference(lastActivation) >= checkInterval;
      }).toSet();

      if (allowedRelays.isEmpty) return;

      await _pumpAutomationService.applyRelays(
        allowedRelays,
        reason: 'Rule-based automatic pump control',
      );

      _lastActivationByRelay = {
        ..._lastActivationByRelay,
        for (final relay in allowedRelays) relay: now,
      };
    } catch (_) {
      // Keep the periodic rule engine alive when Firestore or MQTT is unavailable.
    } finally {
      _isChecking = false;
    }
  }

  Set<int> _relaysForLowParameters(_RuleSensorReading reading) {
    final relays = <int>{};

    if (_isLow(
      reading.nitrogen,
      _thresholdConfigService.value('min_nitrogen', 40),
    )) {
      relays.add(1);
    }
    if (_isLow(
      reading.phosphorus,
      _thresholdConfigService.value('min_phosphorus', 20),
    )) {
      relays.add(2);
    }
    if (_isLow(
      reading.potassium,
      _thresholdConfigService.value('min_potassium', 40),
    )) {
      relays.add(3);
    }
    if (_isLow(
      reading.moisture,
      _thresholdConfigService.value('min_moisture', 40),
    )) {
      relays.add(4);
    }
    if (_isLow(
      reading.ec,
      _thresholdConfigService.value('min_ec', 1.0),
    )) {
      relays.addAll({1, 2, 3});
    }

    return relays;
  }

  bool _isLow(double? value, num? minimum) {
    return value != null && minimum != null && value < minimum;
  }
}

class _RuleSensorReading {
  const _RuleSensorReading({
    this.nitrogen,
    this.phosphorus,
    this.potassium,
    this.ph,
    this.temperature,
    this.moisture,
    this.ec,
  });

  final double? nitrogen;
  final double? phosphorus;
  final double? potassium;
  final double? ph;
  final double? temperature;
  final double? moisture;
  final double? ec;

  factory _RuleSensorReading.fromFirestore(Map<String, dynamic> data) {
    return _RuleSensorReading(
      nitrogen: _readDouble(data, ['N', 'n', 'nitrogen']),
      phosphorus: _readDouble(data, ['P', 'p', 'phosphorus']),
      potassium: _readDouble(data, ['K', 'k', 'potassium']),
      ph: _readDouble(data, ['pH', 'ph', 'PH']),
      temperature: _readDouble(data, ['Temp', 'temp', 'temperature']),
      moisture: _readDouble(data, ['Moisture', 'moisture']),
      ec: _readDouble(data, ['EC', 'ec', 'electrical_conductivity']),
    );
  }

  static double? _readDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}
