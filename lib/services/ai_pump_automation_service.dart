import '../models/ai_recommendation.dart';
import 'mqtt_service.dart';

class AiPumpAutomationResult {
  const AiPumpAutomationResult({
    required this.activatedPumps,
    required this.reason,
  });

  final List<String> activatedPumps;
  final String reason;

  bool get hasActivatedPump => activatedPumps.isNotEmpty;
}

class AiPumpAutomationService {
  AiPumpAutomationService({
    MQTTService? mqttService,
    this.pulseDuration = const Duration(seconds: 5),
  }) : _mqttService = mqttService ?? MQTTService();

  final MQTTService _mqttService;
  final Duration pulseDuration;

  Future<AiPumpAutomationResult> apply(
    AutomationTriggers triggers,
  ) async {
    return _applyCommands(
      <_PumpCommand>[
        if (triggers.activateNitrogenPump)
          const _PumpCommand(relay: 1, label: 'Pump A (N)'),
        if (triggers.activatePhosphorusPump)
          const _PumpCommand(relay: 2, label: 'Pump B (P)'),
        if (triggers.activatePotassiumPump)
          const _PumpCommand(relay: 3, label: 'Pump C (K)'),
        if (triggers.activateWaterPump)
          const _PumpCommand(relay: 4, label: 'Pump D (Air)'),
      ],
      reason: triggers.reason,
    );
  }

  Future<AiPumpAutomationResult> applyRelays(
    Set<int> relays, {
    required String reason,
  }) {
    return _applyCommands(
      relays.map(_commandForRelay).whereType<_PumpCommand>().toList(),
      reason: reason,
    );
  }

  Future<AiPumpAutomationResult> _applyCommands(
    List<_PumpCommand> pumpCommands, {
    required String reason,
  }) async {
    if (pumpCommands.isEmpty) {
      return AiPumpAutomationResult(
        activatedPumps: const [],
        reason: reason,
      );
    }

    await _mqttService.init();
    if (!_mqttService.isConnected) {
      throw StateError(
          'MQTT is not connected, so AI pump automation was not applied.');
    }

    try {
      for (final command in pumpCommands) {
        _mqttService.setRelay(command.relay, true);
      }

      await Future.delayed(pulseDuration);
    } finally {
      for (final command in pumpCommands) {
        _mqttService.setRelay(command.relay, false);
      }
    }

    return AiPumpAutomationResult(
      activatedPumps: pumpCommands.map((command) => command.label).toList(),
      reason: reason,
    );
  }

  _PumpCommand? _commandForRelay(int relay) {
    switch (relay) {
      case 1:
        return const _PumpCommand(relay: 1, label: 'Pump A (N)');
      case 2:
        return const _PumpCommand(relay: 2, label: 'Pump B (P)');
      case 3:
        return const _PumpCommand(relay: 3, label: 'Pump C (K)');
      case 4:
        return const _PumpCommand(relay: 4, label: 'Pump D (Air)');
      default:
        return null;
    }
  }
}

class _PumpCommand {
  const _PumpCommand({
    required this.relay,
    required this.label,
  });

  final int relay;
  final String label;
}
