import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrixense/models/ai_recommendation.dart';
import 'package:nutrixense/widgets/xai_shap_visualization_widget.dart';

void main() {
  testWidgets('XaiShapVisualizationWidget renders correctly with SHAP items',
      (WidgetTester tester) async {
    const response = AiRecommendationResponse(
      plantHealthPercentage: 85,
      sensorSummary: 'Kondisi tanaman sehat dengan defisit ringan.',
      recommendations: RecommendationGroups(
        semua: [],
        kritis: [],
        awas: [],
        baik: [],
      ),
      automationTriggers: AutomationTriggers(
        activateNitrogenPump: true,
        activatePhosphorusPump: false,
        activatePotassiumPump: false,
        activateWaterPump: false,
        reason: 'EC rendah membuka pemupukan N.',
      ),
      xaiContributions: [
        XaiFeatureContribution(
          feature: 'ec_deficit',
          label: 'EC rendah',
          contribution: 3.5,
          featureValue: 450,
          featureValueRatio: 0.3,
          direction: 'Mendorong pemupukan',
          detail: 'EC di bawah target membuka rekomendasi nutrisi.',
        ),
        XaiFeatureContribution(
          feature: 'ph_acid_risk',
          label: 'pH terlalu asam',
          contribution: -2.1,
          featureValue: 5.2,
          featureValueRatio: 0.2,
          direction: 'Menahan durasi',
          detail: 'pH asam menahan dosis pupuk.',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: XaiShapVisualizationWidget(
              response: response,
              factors: [],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Visualisasi XAI SHAP'), findsOneWidget);
    expect(find.text('SHapley Additive exPlanations'), findsOneWidget);
    expect(find.text('EC rendah'), findsWidgets);
    expect(find.text('pH terlalu asam'), findsWidgets);
  });

  testWidgets('XaiShapVisualizationWidget filters Per Pompa tab by relay',
      (WidgetTester tester) async {
    const response = AiRecommendationResponse(
      plantHealthPercentage: 85,
      sensorSummary: 'Tes rekomendasi pompa.',
      recommendations: RecommendationGroups(
        semua: [],
        kritis: [],
        awas: [],
        baik: [],
      ),
      automationTriggers: AutomationTriggers(
        activateNitrogenPump: true,
        activatePhosphorusPump: false,
        activatePotassiumPump: false,
        activateWaterPump: false,
        reason: 'EC rendah',
      ),
      xaiContributions: [
        XaiFeatureContribution(
          feature: 'ec_deficit',
          label: 'EC rendah',
          contribution: 3.5,
          featureValue: 450,
          featureValueRatio: 0.3,
          direction: 'Mendorong pemupukan',
          detail: 'EC di bawah target.',
        ),
      ],
      pumpRecommendations: [
        PumpFertilizationRecommendation(
          relay: 1,
          pumpIndex: 0,
          pumpName: 'Pompa A (N)',
          nutrient: 'Nitrogen',
          unit: 'mg/L',
          currentValue: 80,
          targetMinimum: 120,
          deficit: 40,
          deficitPercent: 33,
          recommendedSeconds: 10,
          reason: 'Defisit Nitrogen.',
        ),
        PumpFertilizationRecommendation(
          relay: 2,
          pumpIndex: 1,
          pumpName: 'Pompa B (P)',
          nutrient: 'Fosfor',
          unit: 'mg/L',
          currentValue: 90,
          targetMinimum: 100,
          deficit: 10,
          deficitPercent: 10,
          recommendedSeconds: 5,
          reason: 'Defisit Fosfor.',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: XaiShapVisualizationWidget(
              response: response,
              factors: [],
            ),
          ),
        ),
      ),
    );

    // Switch to Per Pompa tab
    await tester.tap(find.text('Per Pompa'));
    await tester.pumpAndSettle();

    // Initially "Semua Pompa" shows both Pompa A and Pompa B
    expect(find.text('Pompa A (N)'), findsOneWidget);
    expect(find.text('Pompa B (P)'), findsOneWidget);

    // Tap "Pompa A (N)" filter chip
    await tester.tap(find.text('Pompa A (N)'));
    await tester.pumpAndSettle();

    // Should only show Pompa A, not Pompa B
    expect(find.text('Pompa A (N)'), findsOneWidget);
    expect(find.text('Pompa B (P)'), findsNothing);
  });
}
