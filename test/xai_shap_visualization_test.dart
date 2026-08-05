import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrixense/models/ai_recommendation.dart';
import 'package:nutrixense/widgets/xai_shap_visualization_widget.dart';

void main() {
  testWidgets('XaiShapVisualizationWidget renders correctly with beeswarm title and CustomPaint',
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

    expect(find.textContaining('Visualisasi XAI SHAP'), findsOneWidget);
    expect(find.textContaining('SHapley Additive exPlanations'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
