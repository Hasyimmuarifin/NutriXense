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
    required bool canActivateFertilizerPump,
  }) {
    return AiRecommendationResponse(
      plantHealthPercentage: plantHealthPercentage,
      sensorSummary: sensorSummary,
      recommendations: recommendations,
      automationTriggers: automationTriggers.copyWith(
        activateWaterPump:
            automationTriggers.activateWaterPump && canActivateWaterPump,
        activateFertilizerPump: automationTriggers.activateFertilizerPump &&
            canActivateFertilizerPump,
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

  const AiRecommendationItem({
    required this.id,
    required this.title,
    required this.status,
    required this.message,
    required this.explanation,
  });

  factory AiRecommendationItem.fromJson(Map<String, dynamic> json) {
    return AiRecommendationItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Rekomendasi').toString(),
      status: (json['status'] ?? 'warning').toString().toLowerCase(),
      message: (json['message'] ?? '').toString(),
      explanation: (json['explanation'] ?? '').toString(),
    );
  }

  InsightCard toInsightCard() {
    return InsightCard(
      title: title,
      description: message,
      icon: _icon,
      severity: _severity,
      action: explanation,
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
  final bool activateFertilizerPump;
  final String reason;

  const AutomationTriggers({
    required this.activateWaterPump,
    required this.activateFertilizerPump,
    required this.reason,
  });

  factory AutomationTriggers.fromJson(Map<String, dynamic> json) {
    return AutomationTriggers(
      activateWaterPump: json['activate_water_pump'] == true,
      activateFertilizerPump: json['activate_fertilizer_pump'] == true,
      reason: (json['reason'] ?? '').toString(),
    );
  }

  AutomationTriggers copyWith({
    bool? activateWaterPump,
    bool? activateFertilizerPump,
    String? reason,
  }) {
    return AutomationTriggers(
      activateWaterPump: activateWaterPump ?? this.activateWaterPump,
      activateFertilizerPump:
          activateFertilizerPump ?? this.activateFertilizerPump,
      reason: reason ?? this.reason,
    );
  }

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
