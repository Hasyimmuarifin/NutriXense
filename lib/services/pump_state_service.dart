import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'mqtt_service.dart';

class PumpStateService {
  PumpStateService._();

  static final PumpStateService instance = PumpStateService._();
  static const Duration _manualCommandGracePeriod = Duration(seconds: 4);

  final MQTTService _mqttService = MQTTService();
  final ValueNotifier<Map<int, bool>> relayStates =
      ValueNotifier<Map<int, bool>>({
    1: false,
    2: false,
    3: false,
    4: false,
  });

  StreamSubscription<Map<String, dynamic>>? _mqttSub;
  final Map<int, _PendingRelayCommand> _pendingRelayCommands = {};
  bool _started = false;

  bool get isConnected => _mqttService.isConnected;

  Future<void> start() async {
    await _mqttService.init();
    if (!_mqttService.isConnected) return;

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
    _pendingRelayCommands[relay] = _PendingRelayCommand(
      expectedState: isOn,
      sentAt: DateTime.now(),
    );
    _setRelayState(relay, isOn);
    unawaited(_writeManualPumpLog(relay, isOn));
  }

  void _syncRelayStates(Map<String, dynamic> data) {
    var nextStates = relayStates.value;
    var changed = false;
    final now = DateTime.now();

    for (var relay = 1; relay <= 4; relay++) {
      final rawState = data['relay$relay'];
      if (rawState == null) continue;

      final parsedState = rawState is num
          ? rawState.toInt()
          : int.tryParse(rawState.toString());
      if (parsedState == null) continue;

      final isOn = parsedState == 1;
      final pendingCommand = _pendingRelayCommands[relay];
      if (pendingCommand != null) {
        final isStillFresh =
            now.difference(pendingCommand.sentAt) <= _manualCommandGracePeriod;

        if (isOn == pendingCommand.expectedState) {
          _pendingRelayCommands.remove(relay);
        } else if (isStillFresh) {
          continue;
        } else {
          _pendingRelayCommands.remove(relay);
        }
      }

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

  Future<void> _writeManualPumpLog(int relay, bool isOn) async {
    try {
      final timestamp = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('pump_activity_logs').add({
        'relays': [relay],
        'pumpLabels': [_relayLabel(relay)],
        'durationMs': 0,
        'reason': isOn
            ? 'Kontrol manual pompa dinyalakan'
            : 'Kontrol manual pompa dimatikan',
        'action': isOn ? 'on' : 'off',
        'metadata': {
          'source': 'manual_control',
          'relay': relay,
          'state': isOn ? 'on' : 'off',
        },
        'startedAt': timestamp,
        'finishedAt': timestamp,
        'createdAt': timestamp,
      });
    } catch (error) {
      debugPrint('Manual pump log write failed: $error');
    }
  }

  String _relayLabel(int relay) {
    switch (relay) {
      case 1:
        return 'Pompa A (N)';
      case 2:
        return 'Pompa B (P)';
      case 3:
        return 'Pompa C (K)';
      case 4:
        return 'Pompa D (Air)';
      default:
        return 'Relay $relay';
    }
  }

  Future<void> dispose() async {
    await _mqttSub?.cancel();
    _mqttSub = null;
    _pendingRelayCommands.clear();
    _started = false;
  }
}

class _PendingRelayCommand {
  const _PendingRelayCommand({
    required this.expectedState,
    required this.sentAt,
  });

  final bool expectedState;
  final DateTime sentAt;
}
