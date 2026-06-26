import 'package:flutter/material.dart';

import 'pump_flow_rate.dart';
import 'sensor_data.dart';

class AiRecommendationResponse {
  final int plantHealthPercentage;
  final String sensorSummary;
  final RecommendationGroups recommendations;
  final AutomationTriggers automationTriggers;
  final List<PumpFertilizationRecommendation> pumpRecommendations;
  final DailyFertilizationScheduleRecommendation? dailyScheduleRecommendation;

  const AiRecommendationResponse({
    required this.plantHealthPercentage,
    required this.sensorSummary,
    required this.recommendations,
    required this.automationTriggers,
    this.pumpRecommendations = const [],
    this.dailyScheduleRecommendation,
  });

  factory AiRecommendationResponse.fromJson(Map<String, dynamic> json) {
    return AiRecommendationResponse(
      plantHealthPercentage:
          _readInt(json['plant_health_percentage']).clamp(0, 100),
      sensorSummary: (json['sensor_summary'] ?? '').toString(),
      recommendations: RecommendationGroups.fromJson(
        _readMap(json['recommendations']),
      ),
      automationTriggers: AutomationTriggers.fromJson(
        _readMap(json['automation_triggers']),
      ),
      pumpRecommendations: _readPumpRecommendations(
        json['pump_recommendations'],
      ),
      dailyScheduleRecommendation:
          DailyFertilizationScheduleRecommendation.fromJson(
        _readMap(json['daily_schedule_recommendation']),
      ),
    );
  }

  AiRecommendationResponse copyWith({
    int? plantHealthPercentage,
    String? sensorSummary,
    RecommendationGroups? recommendations,
    AutomationTriggers? automationTriggers,
    List<PumpFertilizationRecommendation>? pumpRecommendations,
    Object? dailyScheduleRecommendation = _unset,
  }) {
    return AiRecommendationResponse(
      plantHealthPercentage:
          plantHealthPercentage ?? this.plantHealthPercentage,
      sensorSummary: sensorSummary ?? this.sensorSummary,
      recommendations: recommendations ?? this.recommendations,
      automationTriggers: automationTriggers ?? this.automationTriggers,
      pumpRecommendations: pumpRecommendations ?? this.pumpRecommendations,
      dailyScheduleRecommendation:
          identical(dailyScheduleRecommendation, _unset)
              ? this.dailyScheduleRecommendation
              : dailyScheduleRecommendation
                  as DailyFertilizationScheduleRecommendation?,
    );
  }

  AiRecommendationResponse withAutomationGuard({
    required bool canActivateWaterPump,
    required bool canActivateNitrogenPump,
    required bool canActivatePhosphorusPump,
    required bool canActivatePotassiumPump,
  }) {
    return copyWith(
      automationTriggers: automationTriggers.copyWith(
        activateWaterPump:
            automationTriggers.activateWaterPump && canActivateWaterPump,
        activateNitrogenPump:
            automationTriggers.activateNitrogenPump && canActivateNitrogenPump,
        activatePhosphorusPump: automationTriggers.activatePhosphorusPump &&
            canActivatePhosphorusPump,
        activatePotassiumPump: automationTriggers.activatePotassiumPump &&
            canActivatePotassiumPump,
      ),
    );
  }

  List<InsightCard> toInsightCards() {
    return recommendations.semua.map((item) => item.toInsightCard()).toList();
  }
}

class PumpFertilizationRecommendation {
  final int relay;
  final int pumpIndex;
  final String pumpName;
  final String nutrient;
  final String unit;
  final double currentValue;
  final double targetMinimum;
  final double deficit;
  final double deficitPercent;
  final int recommendedSeconds;
  final String reason;

  const PumpFertilizationRecommendation({
    required this.relay,
    required this.pumpIndex,
    required this.pumpName,
    required this.nutrient,
    required this.unit,
    required this.currentValue,
    required this.targetMinimum,
    required this.deficit,
    required this.deficitPercent,
    required this.recommendedSeconds,
    required this.reason,
  });

  factory PumpFertilizationRecommendation.fromJson(
    Map<String, dynamic> json,
  ) {
    final relay = _readInt(json['relay']);
    return PumpFertilizationRecommendation(
      relay: relay,
      pumpIndex: _readInt(json['pump_index']).clamp(0, 3),
      pumpName: (json['pump_name'] ?? 'Pump $relay').toString(),
      nutrient: (json['nutrient'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      currentValue: _readDouble(json['current_value']),
      targetMinimum: _readDouble(json['target_minimum']),
      deficit: _readDouble(json['deficit']),
      deficitPercent: _readDouble(json['deficit_percent']),
      recommendedSeconds: _atLeastFive(_readInt(json['recommended_seconds'])),
      reason: (json['reason'] ?? '').toString(),
    );
  }

  PumpFertilizationRecommendation copyWith({
    int? recommendedSeconds,
  }) {
    return PumpFertilizationRecommendation(
      relay: relay,
      pumpIndex: pumpIndex,
      pumpName: pumpName,
      nutrient: nutrient,
      unit: unit,
      currentValue: currentValue,
      targetMinimum: targetMinimum,
      deficit: deficit,
      deficitPercent: deficitPercent,
      recommendedSeconds: recommendedSeconds ?? this.recommendedSeconds,
      reason: reason,
    );
  }

  String get formattedDeficitPercent =>
      '${deficitPercent.toStringAsFixed(1).replaceFirst(RegExp(r'\.?0+$'), '')}%';

  double get averageFlowRateMlPerSecond {
    return PumpFlowRates.byPumpIndex(pumpIndex).averageMlPerSecond;
  }

  double get estimatedVolumeMl {
    return averageFlowRateMlPerSecond * recommendedSeconds;
  }
}

class DailyFertilizationScheduleRecommendation {
  final int hour;
  final int minute;
  final Set<int> pumpIndexes;
  final int durationSeconds;
  final String reason;

  const DailyFertilizationScheduleRecommendation({
    required this.hour,
    required this.minute,
    required this.pumpIndexes,
    required this.durationSeconds,
    required this.reason,
  });

  factory DailyFertilizationScheduleRecommendation.fromPlan({
    required List<PumpFertilizationRecommendation> recommendations,
    required String reason,
  }) {
    final durationSeconds = recommendations.isEmpty
        ? 0
        : recommendations
            .map((item) => item.recommendedSeconds)
            .reduce((a, b) => a > b ? a : b);

    return DailyFertilizationScheduleRecommendation(
      hour: 7,
      minute: 0,
      pumpIndexes: recommendations.map((item) => item.pumpIndex).toSet(),
      durationSeconds: durationSeconds,
      reason: reason,
    );
  }

  static DailyFertilizationScheduleRecommendation? fromJson(
    Map<String, dynamic> json,
  ) {
    final pumpIndexes = json['pump_indexes'] ?? json['pumpIndexes'];
    if (json.isEmpty || pumpIndexes is! List) return null;

    final parsedPumpIndexes = pumpIndexes.whereType<int>().toSet();
    if (parsedPumpIndexes.isEmpty) return null;

    final hour = _readInt(json['hour']);
    final minute = _readInt(json['minute']);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return DailyFertilizationScheduleRecommendation(
      hour: hour,
      minute: minute,
      pumpIndexes: parsedPumpIndexes,
      durationSeconds: _atLeastFive(
          _readInt(json['duration_seconds'] ?? json['durationSeconds'])),
      reason: (json['reason'] ?? '').toString(),
    );
  }

  bool get hasPumps => pumpIndexes.isNotEmpty && durationSeconds > 0;

  String get formattedTime {
    final hourText = hour.toString().padLeft(2, '0');
    final minuteText = minute.toString().padLeft(2, '0');
    return '$hourText:$minuteText';
  }
}

class RecommendationGroups {
  final List<AiRecommendationItem> semua;
  final List<AiRecommendationItem> kritis;
  final List<AiRecommendationItem> awas;
  final List<AiRecommendationItem> baik;

  const RecommendationGroups({
    required this.semua,
    required this.kritis,
    required this.awas,
    required this.baik,
  });

  factory RecommendationGroups.fromJson(Map<String, dynamic> json) {
    final kritis = _readItems(_readFirst(json, ['kritis', 'critical']));
    final awas = _readItems(_readFirst(json, ['awas', 'warning']));
    final baik = _readItems(_readFirst(json, ['baik', 'good', 'normal']));
    final semua = _readItems(_readFirst(json, ['semua', 'all']));

    return RecommendationGroups(
      semua: semua.isNotEmpty ? semua : [...kritis, ...awas, ...baik],
      kritis: kritis,
      awas: awas,
      baik: baik,
    );
  }
}

class AiRecommendationItem {
  final String id;
  final String title;
  final String status;
  final String message;
  final String explanation;
  final String recommendation;

  const AiRecommendationItem({
    required this.id,
    required this.title,
    required this.status,
    required this.message,
    required this.explanation,
    required this.recommendation,
  });

  factory AiRecommendationItem.fromJson(Map<String, dynamic> json) {
    final explanation = (json['explanation'] ?? '').toString();
    return AiRecommendationItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Rekomendasi').toString(),
      status: (json['status'] ?? 'awas').toString().toLowerCase(),
      message: (json['message'] ?? '').toString(),
      explanation: explanation,
      recommendation:
          (json['recommendation'] ?? json['action'] ?? explanation).toString(),
    );
  }

  InsightCard toInsightCard() {
    return InsightCard(
      title: title,
      description: message,
      icon: _icon,
      severity: _severity,
      action: explanation,
      recommendation: recommendation,
    );
  }

  InsightSeverity get _severity {
    switch (status) {
      case 'kritis':
        return InsightSeverity.kritis;
      case 'baik':
        return InsightSeverity.baik;
      case 'awas':
      default:
        return InsightSeverity.awas;
    }
  }

  String get _icon {
    switch (_severity) {
      case InsightSeverity.kritis:
        return '!';
      case InsightSeverity.awas:
        return '~';
      case InsightSeverity.baik:
        return '+';
    }
  }
}

class AutomationTriggers {
  final bool activateWaterPump;
  final bool activateNitrogenPump;
  final bool activatePhosphorusPump;
  final bool activatePotassiumPump;
  final String reason;

  const AutomationTriggers({
    required this.activateWaterPump,
    required this.activateNitrogenPump,
    required this.activatePhosphorusPump,
    required this.activatePotassiumPump,
    required this.reason,
  });

  factory AutomationTriggers.fromJson(Map<String, dynamic> json) {
    final fertilizerRequested = json['activate_fertilizer_pump'] == true;
    return AutomationTriggers(
      activateWaterPump: json['activate_water_pump'] == true,
      activateNitrogenPump:
          json['activate_nitrogen_pump'] == true || fertilizerRequested,
      activatePhosphorusPump:
          json['activate_phosphorus_pump'] == true || fertilizerRequested,
      activatePotassiumPump:
          json['activate_potassium_pump'] == true || fertilizerRequested,
      reason: (json['reason'] ?? '').toString(),
    );
  }

  AutomationTriggers copyWith({
    bool? activateWaterPump,
    bool? activateNitrogenPump,
    bool? activatePhosphorusPump,
    bool? activatePotassiumPump,
    String? reason,
  }) {
    return AutomationTriggers(
      activateWaterPump: activateWaterPump ?? this.activateWaterPump,
      activateNitrogenPump: activateNitrogenPump ?? this.activateNitrogenPump,
      activatePhosphorusPump:
          activatePhosphorusPump ?? this.activatePhosphorusPump,
      activatePotassiumPump:
          activatePotassiumPump ?? this.activatePotassiumPump,
      reason: reason ?? this.reason,
    );
  }

  bool get activateFertilizerPump =>
      activateNitrogenPump || activatePhosphorusPump || activatePotassiumPump;

  bool get hasActivePump =>
      activateWaterPump ||
      activateNitrogenPump ||
      activatePhosphorusPump ||
      activatePotassiumPump;

  IconData get waterIcon =>
      activateWaterPump ? Icons.water_drop_rounded : Icons.water_drop_outlined;

  IconData get fertilizerIcon =>
      activateFertilizerPump ? Icons.eco_rounded : Icons.eco_outlined;
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

Object? _readFirst(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) return json[key];
  }
  return null;
}

List<AiRecommendationItem> _readItems(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => AiRecommendationItem.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .toList();
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _atLeastFive(int value) {
  return value < 5 ? 5 : value;
}

double _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<PumpFertilizationRecommendation> _readPumpRecommendations(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => PumpFertilizationRecommendation.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .where((item) => item.relay >= 1 && item.relay <= 4)
      .toList();
}

const Object _unset = Object();
