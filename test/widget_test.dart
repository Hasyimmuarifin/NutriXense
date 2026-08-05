import 'package:flutter_test/flutter_test.dart';
import 'package:nutrixense/models/ai_recommendation.dart';
import 'package:nutrixense/models/sensor_data.dart';
import 'package:nutrixense/services/gemini_recommendation_service.dart';

void main() {
  test('pump recommendation can keep an adjusted duration', () {
    const recommendation = PumpFertilizationRecommendation(
      relay: 1,
      pumpIndex: 0,
      pumpName: 'Pompa A',
      nutrient: 'Nitrogen',
      unit: 'mg/kg',
      currentValue: 60,
      targetMinimum: 80,
      deficit: 20,
      deficitPercent: 25,
      recommendedSeconds: 70,
      reason: 'Nitrogen is below the minimum threshold.',
    );

    final adjusted = recommendation.copyWith(recommendedSeconds: 95);

    expect(adjusted.relay, 1);
    expect(adjusted.recommendedSeconds, 95);
    expect(adjusted.deficit, 20);
  });

  test('daily schedule recommendation parses Control-compatible data', () {
    final schedule = DailyFertilizationScheduleRecommendation.fromJson({
      'hour': 7,
      'minute': 0,
      'pumpIndexes': [0, 1, 2],
      'durationSeconds': 90,
      'reason': 'Daily AI fertilization recommendation.',
    });

    expect(schedule, isNotNull);
    expect(schedule!.formattedTime, '07:00');
    expect(schedule.hasPumps, isTrue);
    expect(schedule.durationSeconds, 90);
  });

  test('Pompa D (Air) is NOT triggered by high temperature alone when moisture is normal', () {
    final history = [
      SensorDataPoint(
        nitrogen: 100,
        phosphorus: 100,
        potassium: 100,
        ph: 6.5,
        moisture: 60.0, // Normal moisture (> 40%)
        temperature: 35.0, // High temperature (> 30°C)
        ec: 1500,
        time: DateTime.now(),
      ),
    ];
    final input = AiRecommendationAgronomicInput(
      plantType: plantTypeProfiles.first,
      landAreaSquareMeters: 0.01,
      fertilizerConcentration: const FertilizerSolutionConcentration(
        nitrogenMgPerLiter: 100,
        phosphorusMgPerLiter: 100,
        potassiumMgPerLiter: 100,
      ),
      plantingMedium: plantingMediumProfiles.first,
      analysisWindow: defaultAnalysisWindowProfile,
    );
    final thresholds = input.plantType.thresholds;

    final response = GeminiRecommendationService.buildDeterministicDecisionPlan(
      SensorHistorySummary.fromHistory(history),
      input,
      thresholds,
    );

    final pumps = (response['pump_recommendations'] as List? ?? []).cast<Map<String, dynamic>>();
    final waterPump = pumps.where((p) => p['relay'] == 4).firstOrNull;

    expect(waterPump, isNull, reason: 'High temperature alone should not trigger Pompa D when moisture is normal');
  });

  test('Pompa D (Air) applies evapotranspiration bonus when moisture is low AND temperature is high', () {
    final history = [
      SensorDataPoint(
        nitrogen: 100,
        phosphorus: 100,
        potassium: 100,
        ph: 6.5,
        moisture: 30.0, // Low moisture (< 40%)
        temperature: 35.0, // High temperature (> 30°C)
        ec: 1500,
        time: DateTime.now(),
      ),
    ];
    final input = AiRecommendationAgronomicInput(
      plantType: plantTypeProfiles.first,
      landAreaSquareMeters: 0.01,
      fertilizerConcentration: const FertilizerSolutionConcentration(
        nitrogenMgPerLiter: 100,
        phosphorusMgPerLiter: 100,
        potassiumMgPerLiter: 100,
      ),
      plantingMedium: plantingMediumProfiles.first,
      analysisWindow: defaultAnalysisWindowProfile,
    );
    final thresholds = input.plantType.thresholds;

    final response = GeminiRecommendationService.buildDeterministicDecisionPlan(
      SensorHistorySummary.fromHistory(history),
      input,
      thresholds,
    );

    final pumps = (response['pump_recommendations'] as List? ?? []).cast<Map<String, dynamic>>();
    final waterPump = pumps.where((p) => p['relay'] == 4).firstOrNull;

    expect(waterPump, isNotNull, reason: 'Low moisture should trigger Pompa D');
    expect(waterPump!['reason'], contains('evapotranspirasi'));
  });
}
