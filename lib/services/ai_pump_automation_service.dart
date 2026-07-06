import '../models/ai_recommendation.dart';
import 'pump_state_service.dart';

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
    PumpStateService? pumpStateService,
    this.pulseDuration = const Duration(seconds: 5),
  }) : _pumpStateService = pumpStateService ?? PumpStateService.instance;

  final PumpStateService _pumpStateService;
  final Duration pulseDuration;

  Future<AiPumpAutomationResult> apply(
    AutomationTriggers triggers,
  ) async {
    return _applyCommands(
      <_PumpCommand>[
        if (triggers.activateNitrogenPump)
          const _PumpCommand(relay: 1, label: 'Pompa A (N)'),
        if (triggers.activatePhosphorusPump)
          const _PumpCommand(relay: 2, label: 'Pompa B (P)'),
        if (triggers.activatePotassiumPump)
          const _PumpCommand(relay: 3, label: 'Pompa C (K)'),
        if (triggers.activateWaterPump)
          const _PumpCommand(relay: 4, label: 'Pompa D (Water)'),
      ],
      reason: triggers.reason,
    );
  }

  Future<AiPumpAutomationResult> applyRecommendations(
    List<PumpFertilizationRecommendation> recommendations,
  ) {
    return _applyCommands(
      recommendations
          .where((item) => item.recommendedSeconds > 0)
          .map(
            (item) => _PumpCommand(
              relay: item.relay,
              label: '${item.pumpName} (${item.nutrient})',
              duration: Duration(seconds: item.recommendedSeconds),
            ),
          )
          .toList(),
      reason:
          'AI recommendation confirmed by user with adjustable pump duration.',
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

    await _pumpStateService.start();
    if (!_pumpStateService.isConnected) {
      throw StateError(
          'MQTT is not connected, so AI pump automation was not applied.');
    }

    try {
      for (final command in pumpCommands) {
        await _pumpStateService.setRelay(
          command.relay,
          true,
          source: 'ai_automation',
        );
      }

      final startedAt = DateTime.now();
      final sortedCommands = [...pumpCommands]
        ..sort((a, b) => a.duration.compareTo(b.duration));
      for (final command in sortedCommands) {
        final elapsed = DateTime.now().difference(startedAt);
        final remaining = command.duration - elapsed;
        if (remaining > Duration.zero) {
          await Future.delayed(remaining);
        }
        await _pumpStateService.setRelay(
          command.relay,
          false,
          source: 'ai_automation',
        );
      }
    } finally {
      for (final command in pumpCommands) {
        await _pumpStateService.setRelay(
          command.relay,
          false,
          source: 'ai_automation',
        );
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
        return _PumpCommand(
          relay: 1,
          label: 'Pompa A (N)',
          duration: pulseDuration,
        );
      case 2:
        return _PumpCommand(
          relay: 2,
          label: 'Pompa B (P)',
          duration: pulseDuration,
        );
      case 3:
        return _PumpCommand(
          relay: 3,
          label: 'Pompa C (K)',
          duration: pulseDuration,
        );
      case 4:
        return _PumpCommand(
          relay: 4,
          label: 'Pompa D (Air)',
          duration: pulseDuration,
        );
      default:
        return null;
    }
  }
}

class _PumpCommand {
  const _PumpCommand({
    required this.relay,
    required this.label,
    this.duration = const Duration(seconds: 5),
  });

  final int relay;
  final String label;
  final Duration duration;
}
