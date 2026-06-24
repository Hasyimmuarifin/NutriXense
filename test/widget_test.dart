import 'package:flutter_test/flutter_test.dart';
import 'package:nutrixense/models/ai_recommendation.dart';

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
}
