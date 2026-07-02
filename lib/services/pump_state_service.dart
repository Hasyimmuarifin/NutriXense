import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mqtt_service.dart';

class PumpStateService {
  PumpStateService._();

  static final PumpStateService instance = PumpStateService._();

  final MQTTService _mqttService = MQTTService();
  final ValueNotifier<Map<int, bool>> relayStates =
      ValueNotifier<Map<int, bool>>({
    1: false,
    2: false,
    3: false,
    4: false,
  });

  StreamSubscription<Map<String, dynamic>>? _mqttSub;
  bool _started = false;

  bool get isConnected => _mqttService.isConnected;

  Future<void> start() async {
    await _mqttService.init();
    if (!_mqttService.isConnected) return;

    _mqttService.subscribe('nutrixense/control');
    _mqttService.subscribe('nutrixense/sensor');

    if (_started) return;
    _started = true;
    _mqttSub = _mqttService.sensorStream.listen(_syncRelayStates);
  }

  Future<void> setRelay(int relay, bool isOn) async {
    await start();
    if (!_mqttService.isConnected) {
      throw StateError('MQTT is not connected.');
    }

    _mqttService.setRelay(relay, isOn);
    _setRelayState(relay, isOn);
  }

  void _syncRelayStates(Map<String, dynamic> data) {
    var nextStates = relayStates.value;
    var changed = false;

    for (var relay = 1; relay <= 4; relay++) {
      final rawState = data['relay$relay'];
      if (rawState == null) continue;

      final parsedState = rawState is num
          ? rawState.toInt()
          : int.tryParse(rawState.toString());
      if (parsedState == null) continue;

      final isOn = parsedState == 1;
      if (nextStates[relay] == isOn) continue;

      if (!changed) {
        nextStates = Map<int, bool>.from(nextStates);
      }
      nextStates[relay] = isOn;
      changed = true;
    }

    if (changed) {
      relayStates.value = nextStates;
    }
  }

  void _setRelayState(int relay, bool isOn) {
    if (relay < 1 || relay > 4 || relayStates.value[relay] == isOn) {
      return;
    }

    relayStates.value = {
      ...relayStates.value,
      relay: isOn,
    };
  }

  Future<void> dispose() async {
    await _mqttSub?.cancel();
    _mqttSub = null;
    _started = false;
  }
}
