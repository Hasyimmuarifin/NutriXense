import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
    FirebaseFirestore? firestore,
    PumpStateService? pumpStateService,
    this.pulseDuration = const Duration(seconds: 5),
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _pumpStateService = pumpStateService ?? PumpStateService.instance;

  static const String _pumpLogsCollection = 'pump_activity_logs';
  static const String _aiSource = 'ai_automation';
  static const String _aiLogTitle = 'Rekomendasi AI';

  final FirebaseFirestore _firestore;
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
          const _PumpCommand(relay: 4, label: 'Pompa D (Air)'),
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
              label: _standardPumpLabel(item.relay),
              duration: Duration(seconds: item.recommendedSeconds),
            ),
          )
          .toList(),
      reason:
          'AI recommendation confirmed by user with adjustable pump duration.',
    );
  }

  static String _standardPumpLabel(int relay) {
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

    final hasDeviceTelemetry =
        await _pumpStateService.waitForFreshDeviceTelemetry();
    if (!_pumpStateService.isConnected || !hasDeviceTelemetry) {
      throw StateError(
        'Perangkat IoT tidak terhubung. Rekomendasi AI tidak dijalankan.',
      );
    }

    final startedAt = DateTime.now();
    final sortedCommands = [...pumpCommands]
      ..sort((a, b) => a.relay.compareTo(b.relay));

    try {
      for (var i = 0; i < sortedCommands.length; i++) {
        final command = sortedCommands[i];

        await _pumpStateService.setExclusiveRelay(
          command.relay,
          source: _aiSource,
          requireConfirmation: false,
        );

        await Future.delayed(command.duration);

        await _pumpStateService.turnAllRelaysOff(
          source: _aiSource,
        );

        if (i < sortedCommands.length - 1) {
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    } finally {
      try {
        await _pumpStateService.turnAllRelaysOff(
          source: _aiSource,
        );
      } catch (_) {
        // Best-effort shutdown only.
      }

      await _writeCompletedLog(
        sortedCommands,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );
    }

    return AiPumpAutomationResult(
      activatedPumps: sortedCommands.map((command) => command.label).toList(),
      reason: reason,
    );
  }

  Future<void> _writeCompletedLog(
    List<_PumpCommand> pumpCommands, {
    required DateTime startedAt,
    required DateTime finishedAt,
  }) async {
    try {
      final durationMsByRelay = {
        for (final command in pumpCommands)
          '${command.relay}': command.duration.inMilliseconds,
      };

      // Total duration is the exact sum of confirmed pump active durations
      final totalPumpDurationMs = pumpCommands.fold<int>(
        0,
        (total, command) => total + command.duration.inMilliseconds,
      );

      await _firestore.collection(_pumpLogsCollection).add({
        'reason': _aiLogTitle,
        'action': 'completed',
        'relays': pumpCommands.map((command) => command.relay).toList(),
        'pumpLabels': pumpCommands.map((command) => command.label).toList(),
        'durationMs': totalPumpDurationMs,
        'durationMsByRelay': durationMsByRelay,
        'startedAt': Timestamp.fromDate(startedAt),
        'finishedAt': Timestamp.fromDate(finishedAt),
        'createdAt': Timestamp.fromDate(finishedAt),
        'metadata': {
          'source': _aiSource,
          'state': 'completed',
          'title': _aiLogTitle,
        },
      });
    } catch (error) {
      debugPrint('AI pump completed log failed: $error');
    }
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
