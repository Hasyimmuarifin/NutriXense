import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mqtt_service.dart';

class PumpStateService {
  PumpStateService._();

  static final PumpStateService instance = PumpStateService._();
  static const Duration _manualCommandGracePeriod = Duration(seconds: 4);
  static const Duration _deviceTelemetryTimeout = Duration(seconds: 5);
  static const Duration _relayConfirmationTimeout = Duration(seconds: 4);

  final MQTTService _mqttService = MQTTService();
  final ValueNotifier<Map<int, bool>> relayStates =
      ValueNotifier<Map<int, bool>>({
    1: false,
    2: false,
    3: false,
    4: false,
  });
  final ValueNotifier<int> _telemetryVersion = ValueNotifier<int>(0);

  StreamSubscription<Map<String, dynamic>>? _mqttSub;
  final Map<int, _PendingRelayCommand> _pendingRelayCommands = {};
  bool _started = false;
  DateTime? _lastTelemetryAt;

  bool get isConnected => _mqttService.isConnected;
  bool get hasFreshDeviceTelemetry {
    final lastTelemetryAt = _lastTelemetryAt;
    if (lastTelemetryAt == null) return false;

    return DateTime.now().difference(lastTelemetryAt) <=
        _deviceTelemetryTimeout;
  }

  Future<void> start() async {
    await _mqttService.init();
    if (!_mqttService.isConnected) return;

    _mqttService.subscribe('nutrixense/sensor');

    if (_started) return;
    _started = true;
    _mqttSub = _mqttService.sensorStream.listen(_syncRelayStates);
  }

  Future<bool> waitForFreshDeviceTelemetry({
    Duration timeout = _deviceTelemetryTimeout,
  }) async {
    await start();
    if (!_mqttService.isConnected) return false;
    if (hasFreshDeviceTelemetry) return true;

    final completer = Completer<bool>();
    late VoidCallback listener;
    Timer? timer;

    void finish(bool value) {
      timer?.cancel();
      _telemetryVersion.removeListener(listener);
      if (!completer.isCompleted) completer.complete(value);
    }

    listener = () {
      if (hasFreshDeviceTelemetry) finish(true);
    };

    _telemetryVersion.addListener(listener);
    timer = Timer(timeout, () => finish(false));
    listener();

    return completer.future;
  }

  Future<void> setRelay(
    int relay,
    bool isOn, {
    String source = 'manual_control',
    String? reason,
    bool requireConfirmation = false,
    Duration confirmationTimeout = _relayConfirmationTimeout,
  }) async {
    await start();
    if (!_mqttService.isConnected) {
      throw StateError('MQTT is not connected.');
    }
    if (requireConfirmation && !hasFreshDeviceTelemetry) {
      throw StateError(
        'Perangkat IoT tidak mengirim telemetry terbaru, perintah relay dibatalkan.',
      );
    }

    _mqttService.setRelay(relay, isOn, source: source);
    _pendingRelayCommands[relay] = _PendingRelayCommand(
      expectedState: isOn,
      sentAt: DateTime.now(),
    );
    if (requireConfirmation) {
      await _waitForRelayState(
        relay,
        isOn,
        timeout: confirmationTimeout,
      );
    }
  }

  Future<void> setExclusiveRelay(
    int activeRelay, {
    String source = 'manual_control',
    bool requireConfirmation = false,
    Duration confirmationTimeout = _relayConfirmationTimeout,
  }) async {
    await start();
    if (!_mqttService.isConnected) {
      throw StateError('MQTT is not connected.');
    }
    if (requireConfirmation && !hasFreshDeviceTelemetry) {
      throw StateError(
        'Perangkat IoT tidak mengirim telemetry terbaru, perintah relay dibatalkan.',
      );
    }

    _mqttService.setExclusiveRelay(activeRelay, source: source);
    final now = DateTime.now();
    for (var r = 1; r <= 4; r++) {
      _pendingRelayCommands[r] = _PendingRelayCommand(
        expectedState: r == activeRelay,
        sentAt: now,
      );
    }
    if (requireConfirmation) {
      await _waitForRelayState(
        activeRelay,
        true,
        timeout: confirmationTimeout,
      );
    }
  }

  Future<void> turnAllRelaysOff({
    String source = 'manual_control',
  }) async {
    await start();
    if (!_mqttService.isConnected) return;

    _mqttService.turnAllRelaysOff(source: source);
    final now = DateTime.now();
    for (var r = 1; r <= 4; r++) {
      _pendingRelayCommands[r] = _PendingRelayCommand(
        expectedState: false,
        sentAt: now,
      );
    }
  }

  void _syncRelayStates(Map<String, dynamic> data) {
    var nextStates = relayStates.value;
    var changed = false;
    final now = DateTime.now();
    var hasRelayTelemetry = false;

    for (var relay = 1; relay <= 4; relay++) {
      final rawState = data['relay$relay'];
      if (rawState == null) continue;

      final parsedState = rawState is num
          ? rawState.toInt()
          : int.tryParse(rawState.toString());
      if (parsedState == null) continue;
      hasRelayTelemetry = true;

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

    if (hasRelayTelemetry) {
      _lastTelemetryAt = now;
      _telemetryVersion.value++;
    }
    if (changed) {
      relayStates.value = nextStates;
    }
  }

  Future<void> _waitForRelayState(
    int relay,
    bool expectedState, {
    required Duration timeout,
  }) async {
    if (relayStates.value[relay] == expectedState && hasFreshDeviceTelemetry) {
      return;
    }

    final completer = Completer<void>();
    late VoidCallback listener;
    Timer? timer;

    void finish([Object? error]) {
      timer?.cancel();
      relayStates.removeListener(listener);
      if (completer.isCompleted) return;
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    }

    listener = () {
      if (relayStates.value[relay] == expectedState &&
          hasFreshDeviceTelemetry) {
        finish();
      }
    };

    relayStates.addListener(listener);
    timer = Timer(timeout, () {
      _pendingRelayCommands.remove(relay);
      finish(
        TimeoutException(
          'Perangkat IoT tidak mengonfirmasi Relay $relay ${expectedState ? 'ON' : 'OFF'}.',
          timeout,
        ),
      );
    });
    listener();

    await completer.future;
  }

  Future<void> dispose() async {
    await _mqttSub?.cancel();
    _mqttSub = null;
    _pendingRelayCommands.clear();
    _started = false;
    _lastTelemetryAt = null;
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
