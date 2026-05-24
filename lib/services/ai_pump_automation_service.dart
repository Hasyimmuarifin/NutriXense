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
    final pumpCommands = <_PumpCommand>[
      if (triggers.activateNitrogenPump)
        const _PumpCommand(relay: 1, label: 'Pump A (N)'),
      if (triggers.activatePhosphorusPump)
        const _PumpCommand(relay: 2, label: 'Pump B (P)'),
      if (triggers.activatePotassiumPump)
        const _PumpCommand(relay: 3, label: 'Pump C (K)'),
      if (triggers.activateWaterPump)
        const _PumpCommand(relay: 4, label: 'Pump D (Air)'),
    ];

    if (pumpCommands.isEmpty) {
      return AiPumpAutomationResult(
        activatedPumps: const [],
        reason: triggers.reason,
      );
    }

    await _mqttService.init();
    if (!_mqttService.isConnected) {
      throw StateError(
          'MQTT is not connected, so AI pump automation was not applied.');
    }

    for (final command in pumpCommands) {
      _mqttService.setRelay(command.relay, true);
    }

    await Future.delayed(pulseDuration);

    for (final command in pumpCommands) {
      _mqttService.setRelay(command.relay, false);
    }

    return AiPumpAutomationResult(
      activatedPumps: pumpCommands.map((command) => command.label).toList(),
      reason: triggers.reason,
    );
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
