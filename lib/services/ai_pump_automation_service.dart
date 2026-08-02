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

    final hasDeviceTelemetry =
        await _pumpStateService.waitForFreshDeviceTelemetry();
    if (!_pumpStateService.isConnected || !hasDeviceTelemetry) {
      throw StateError(
        'Perangkat IoT tidak terhubung. Rekomendasi AI tidak dijalankan.',
      );
    }

    final startedAt = DateTime.now();
    DocumentReference<Map<String, dynamic>>? logRef;

    try {
      logRef = await _createRunningLog(
        pumpCommands,
        startedAt: startedAt,
      );

      final sortedCommands = [...pumpCommands]
        ..sort((a, b) => a.relay.compareTo(b.relay));

      for (var i = 0; i < sortedCommands.length; i++) {
        final command = sortedCommands[i];

        await _pumpStateService.setRelay(
          command.relay,
          true,
          source: _aiSource,
          requireConfirmation: false,
        );

        await Future.delayed(command.duration);

        await _pumpStateService.setRelay(
          command.relay,
          false,
          source: _aiSource,
          requireConfirmation: false,
        );

        if (i < sortedCommands.length - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      for (final command in pumpCommands) {
        try {
          await _pumpStateService.setRelay(
            command.relay,
            false,
            source: _aiSource,
          );
        } catch (_) {
          // Best-effort shutdown only.
        }
      }
      if (logRef != null) {
        await _completeLog(
          logRef,
          pumpCommands,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
        );
      }
    }

    return AiPumpAutomationResult(
      activatedPumps: pumpCommands.map((command) => command.label).toList(),
      reason: reason,
    );
  }

  Future<DocumentReference<Map<String, dynamic>>?> _createRunningLog(
    List<_PumpCommand> pumpCommands, {
    required DateTime startedAt,
  }) async {
    try {
      final durationMsByRelay = {
        for (final command in pumpCommands)
          '${command.relay}': command.duration.inMilliseconds,
      };
      final maxDuration = _maxDuration(pumpCommands);

      final ref = _firestore.collection(_pumpLogsCollection).doc();
      await ref.set({
        'reason': _aiLogTitle,
        'action': 'running',
        'relays': pumpCommands.map((command) => command.relay).toList(),
        'pumpLabels': pumpCommands.map((command) => command.label).toList(),
        'durationMs': maxDuration.inMilliseconds,
        'durationMsByRelay': durationMsByRelay,
        'createdAt': Timestamp.fromDate(startedAt),
        'startedAt': Timestamp.fromDate(startedAt),
        'metadata': {
          'source': _aiSource,
          'state': 'running',
          'title': _aiLogTitle,
        },
      });
      return ref;
    } catch (error) {
      debugPrint('AI pump running log failed: $error');
      return null;
    }
  }

  Future<void> _completeLog(
    DocumentReference<Map<String, dynamic>>? logRef,
    List<_PumpCommand> pumpCommands, {
    required DateTime startedAt,
    required DateTime finishedAt,
  }) async {
    if (logRef == null) return;

    try {
      final durationMsByRelay = {
        for (final command in pumpCommands)
          '${command.relay}': command.duration.inMilliseconds,
      };
      final actualDurationMs = finishedAt.difference(startedAt).inMilliseconds;

      await logRef.set({
        'reason': _aiLogTitle,
        'action': 'completed',
        'relays': pumpCommands.map((command) => command.relay).toList(),
        'pumpLabels': pumpCommands.map((command) => command.label).toList(),
        'durationMs': actualDurationMs,
        'durationMsByRelay': durationMsByRelay,
        'finishedAt': Timestamp.fromDate(finishedAt),
        'metadata': {
          'source': _aiSource,
          'state': 'completed',
          'title': _aiLogTitle,
        },
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('AI pump completed log failed: $error');
    }
  }

  Duration _maxDuration(List<_PumpCommand> pumpCommands) {
    return pumpCommands
        .map((command) => command.duration)
        .reduce((a, b) => a > b ? a : b);
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
