import 'package:flutter/material.dart';

import 'sensor_data.dart';

class AiRecommendationResponse {
  final int plantHealthPercentage;
  final String sensorSummary;
  final RecommendationGroups recommendations;
  final AutomationTriggers automationTriggers;

  const AiRecommendationResponse({
    required this.plantHealthPercentage,
    required this.sensorSummary,
    required this.recommendations,
    required this.automationTriggers,
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
    );
  }

  AiRecommendationResponse withAutomationGuard({
    required bool canActivateWaterPump,
    required bool canActivateNitrogenPump,
    required bool canActivatePhosphorusPump,
    required bool canActivatePotassiumPump,
  }) {
    return AiRecommendationResponse(
      plantHealthPercentage: plantHealthPercentage,
      sensorSummary: sensorSummary,
      recommendations: recommendations,
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
    return recommendations.all.map((item) => item.toInsightCard()).toList();
  }
}

class RecommendationGroups {
  final List<AiRecommendationItem> all;
  final List<AiRecommendationItem> critical;
  final List<AiRecommendationItem> warning;
  final List<AiRecommendationItem> good;

  const RecommendationGroups({
    required this.all,
    required this.critical,
    required this.warning,
    required this.good,
  });

  factory RecommendationGroups.fromJson(Map<String, dynamic> json) {
    return RecommendationGroups(
      all: _readItems(json['all']),
      critical: _readItems(json['critical']),
      warning: _readItems(json['warning']),
      good: _readItems(json['good']),
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
      status: (json['status'] ?? 'warning').toString().toLowerCase(),
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
      case 'critical':
        return InsightSeverity.critical;
      case 'good':
        return InsightSeverity.good;
      case 'warning':
      default:
        return InsightSeverity.warning;
    }
  }

  String get _icon {
    switch (_severity) {
      case InsightSeverity.critical:
        return '!';
      case InsightSeverity.warning:
        return '~';
      case InsightSeverity.good:
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
