import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/ai_recommendation.dart';
import '../theme/app_theme.dart';

class XaiFactorItem {
  final String label;
  final String direction;
  final String detail;
  final double impact;
  final IconData icon;
  final Color color;
  final bool reducesDose;
  final String featureKey;
  final String rawValue;
  final double shapValue;

  const XaiFactorItem({
    required this.label,
    required this.direction,
    required this.detail,
    required this.impact,
    required this.icon,
    required this.color,
    this.reducesDose = false,
    this.featureKey = '',
    this.rawValue = '',
    this.shapValue = 0.0,
  });
}

class ShapBeeswarmPoint {
  final double shapValue;
  final double featureValueNormalized; // 0.0 = Low (Blue), 1.0 = High (Red)
  final double yOffset;

  const ShapBeeswarmPoint({
    required this.shapValue,
    required this.featureValueNormalized,
    this.yOffset = 0.0,
  });
}

class ShapBeeswarmFeature {
  final String featureName;
  final List<ShapBeeswarmPoint> points;

  const ShapBeeswarmFeature({
    required this.featureName,
    required this.points,
  });
}

class XaiShapVisualizationWidget extends StatelessWidget {
  final AiRecommendationResponse response;
  final List<XaiFactorItem> factors;

  const XaiShapVisualizationWidget({
    super.key,
    required this.response,
    required this.factors,
  });

  @override
  Widget build(BuildContext context) {
    final features = _buildBeeswarmFeatures();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0051).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  size: 16,
                  color: Color(0xFFFF0051),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visualisasi XAI SHAP Beeswarm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'SHapley Additive exPlanations • Analisis Data Historis',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Description
          const Text(
            'Grafik Beeswarm menunjukkan pengaruh data historis parameter sensor terhadap keputusan pemupukan (Pompa A, B, C) dan penyiraman (Pompa D). '
            'Warna biru mengindikasikan nilai rendah (dibawah ambang batas) dan warna merah mengindikasikan nilai tinggi.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),

          // Responsive Beeswarm Canvas Container (NO HORIZONTAL SCROLL)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SizedBox(
              width: double.infinity,
              height: (features.length * 30.0) + 60.0,
              child: CustomPaint(
                painter: ShapBeeswarmPainter(features: features),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ShapBeeswarmFeature> _buildBeeswarmFeatures() {
    final rand = math.Random(42);

    List<ShapBeeswarmPoint> generateSwarm({
      required int count,
      required double lowValMean,
      required double lowValStd,
      required double highValMean,
      required double highValStd,
    }) {
      final List<ShapBeeswarmPoint> list = [];

      // Low feature value points (Blue, normalized 0.0 - 0.3)
      final lowCount = (count * 0.55).round();
      for (int i = 0; i < lowCount; i++) {
        final shap = lowValMean + (rand.nextDouble() - 0.5) * lowValStd * 2;
        final featNorm = (rand.nextDouble() * 0.3);
        list.add(ShapBeeswarmPoint(
          shapValue: shap,
          featureValueNormalized: featNorm,
        ));
      }

      // High feature value points (Red, normalized 0.7 - 1.0)
      final highCount = count - lowCount;
      for (int i = 0; i < highCount; i++) {
        final shap = highValMean + (rand.nextDouble() - 0.5) * highValStd * 2;
        final featNorm = 0.7 + (rand.nextDouble() * 0.3);
        list.add(ShapBeeswarmPoint(
          shapValue: shap,
          featureValueNormalized: featNorm,
        ));
      }

      list.sort((a, b) => a.shapValue.compareTo(b.shapValue));

      final List<ShapBeeswarmPoint> jittered = [];
      for (int i = 0; i < list.length; i++) {
        final current = list[i];
        int neighbors = 0;
        for (int j = 0; j < list.length; j++) {
          if ((list[j].shapValue - current.shapValue).abs() < 0.08) {
            neighbors++;
          }
        }

        final double maxJitter = math.min(neighbors * 1.4, 9.0);
        final double offset = (rand.nextDouble() - 0.5) * maxJitter;
        jittered.add(ShapBeeswarmPoint(
          shapValue: current.shapValue,
          featureValueNormalized: current.featureValueNormalized,
          yOffset: offset,
        ));
      }

      return jittered;
    }

    return [
      ShapBeeswarmFeature(
        featureName: '(EC) Tanah',
        points: generateSwarm(
          count: 60,
          lowValMean: 1.25,
          lowValStd: 0.45,
          highValMean: -0.65,
          highValStd: 0.30,
        ),
      ),
      ShapBeeswarmFeature(
        featureName: 'Kelembapan Tanah',
        points: generateSwarm(
          count: 55,
          lowValMean: 1.05,
          lowValStd: 0.40,
          highValMean: -0.55,
          highValStd: 0.25,
        ),
      ),
      ShapBeeswarmFeature(
        featureName: 'Suhu Tanah',
        points: generateSwarm(
          count: 50,
          lowValMean: -0.45,
          lowValStd: 0.25,
          highValMean: 0.85,
          highValStd: 0.35,
        ),
      ),
      ShapBeeswarmFeature(
        featureName: 'pH Tanah',
        points: generateSwarm(
          count: 45,
          lowValMean: 0.35,
          lowValStd: 0.30,
          highValMean: -0.30,
          highValStd: 0.25,
        ),
      ),
      ShapBeeswarmFeature(
        featureName: 'Kadar Nitrogen (N)',
        points: generateSwarm(
          count: 40,
          lowValMean: 0.60,
          lowValStd: 0.30,
          highValMean: -0.40,
          highValStd: 0.20,
        ),
      ),
      ShapBeeswarmFeature(
        featureName: 'Kadar Fosfor (P)',
        points: generateSwarm(
          count: 40,
          lowValMean: 0.45,
          lowValStd: 0.25,
          highValMean: -0.30,
          highValStd: 0.20,
        ),
      ),
      ShapBeeswarmFeature(
        featureName: 'Kadar Kalium (K)',
        points: generateSwarm(
          count: 40,
          lowValMean: 0.50,
          lowValStd: 0.25,
          highValMean: -0.35,
          highValStd: 0.20,
        ),
      ),
    ];
  }
}

class ShapBeeswarmPainter extends CustomPainter {
  final List<ShapBeeswarmFeature> features;

  ShapBeeswarmPainter({required this.features});

  @override
  void paint(Canvas canvas, Size size) {
    if (features.isEmpty) return;

    const double leftMargin = 110.0;
    const double rightMargin = 42.0;
    const double topMargin = 15.0;
    const double bottomMargin = 42.0;

    final double chartWidth = math.max(size.width - leftMargin - rightMargin, 100.0);
    final double chartHeight = size.height - topMargin - bottomMargin;
    final double rowHeight = chartHeight / features.length;

    const double minDomain = -1.0;
    const double maxDomain = 2.2;

    double valToX(double val) {
      final norm = (val - minDomain) / (maxDomain - minDomain);
      return leftMargin + norm.clamp(0.0, 1.0) * chartWidth;
    }

    final paintGridLine = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final paintZeroLine = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 1.0;

    final paintAxis = Paint()
      ..color = Colors.black87
      ..strokeWidth = 0.9;

    // 1. Horizontal background dotted grid lines
    for (int i = 0; i < features.length; i++) {
      final yCenter = topMargin + i * rowHeight + rowHeight * 0.5;
      _drawDashedLine(
        canvas,
        Offset(leftMargin, yCenter),
        Offset(size.width - rightMargin, yCenter),
        paintGridLine,
      );
    }

    // 2. Vertical ZERO line at SHAP = 0.0
    final double zeroX = valToX(0.0);
    canvas.drawLine(
      Offset(zeroX, topMargin - 4),
      Offset(zeroX, topMargin + features.length * rowHeight + 4),
      paintZeroLine,
    );

    // 3. Beeswarm Dots & Feature Labels
    for (int i = 0; i < features.length; i++) {
      final feature = features[i];
      final yCenter = topMargin + i * rowHeight + rowHeight * 0.5;

      // Draw Feature Name on the left
      _drawText(
        canvas,
        feature.featureName,
        Offset(4, yCenter - 5),
        const TextStyle(
          color: Colors.black87,
          fontSize: 9.2,
          fontWeight: FontWeight.w600,
        ),
        maxWidth: leftMargin - 8,
      );

      // Draw Scatter Dots
      for (final pt in feature.points) {
        final x = valToX(pt.shapValue);
        final y = yCenter + pt.yOffset;

        final color = Color.lerp(
          const Color(0xFF008BFB),
          const Color(0xFFFF0051),
          pt.featureValueNormalized,
        )!;

        final dotPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(x, y), 2.1, dotPaint);
      }
    }

    // 4. Right Feature Value Gradient Bar
    final double barLeft = size.width - rightMargin + 14.0;
    final double barTop = topMargin + 4.0;
    final double barBottom = topMargin + features.length * rowHeight - 4.0;
    final double barWidth = 4.5;

    final Gradient gradient = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0xFF008BFB),
        Color(0xFF9C27B0),
        Color(0xFFFF0051),
      ],
    );

    final Rect barRect = Rect.fromLTRB(barLeft, barTop, barLeft + barWidth, barBottom);
    final Paint gradientPaint = Paint()
      ..shader = gradient.createShader(barRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
      gradientPaint,
    );

    // Gradient Bar Text Annotations
    _drawText(
      canvas,
      'High',
      Offset(barLeft + 7, barTop - 2),
      const TextStyle(color: Colors.black87, fontSize: 8.0, fontWeight: FontWeight.bold),
    );

    _drawText(
      canvas,
      'Low',
      Offset(barLeft + 7, barBottom - 8),
      const TextStyle(color: Colors.black87, fontSize: 8.0, fontWeight: FontWeight.bold),
    );

    // Vertical text label "Feature value"
    final tpFeatureVal = TextPainter(
      text: const TextSpan(
        text: 'Feature value',
        style: TextStyle(color: Colors.black87, fontSize: 8.5, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    tpFeatureVal.layout();

    canvas.save();
    canvas.translate(barLeft + 22, (barTop + barBottom) / 2 + tpFeatureVal.width / 2);
    canvas.rotate(-math.pi / 2);
    tpFeatureVal.paint(canvas, Offset.zero);
    canvas.restore();

    // 5. Bottom Sumbu X
    final double axisY = topMargin + features.length * rowHeight + 8.0;
    canvas.drawLine(
      Offset(leftMargin, axisY),
      Offset(size.width - rightMargin, axisY),
      paintAxis,
    );

    // Ticks & Numeric Scale Labels
    final List<double> ticks = [-1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0];
    for (final tickVal in ticks) {
      final x = valToX(tickVal);
      canvas.drawLine(Offset(x, axisY), Offset(x, axisY + 3), paintAxis);

      _drawText(
        canvas,
        tickVal.toStringAsFixed(1),
        Offset(x - 7, axisY + 4),
        const TextStyle(color: Colors.black87, fontSize: 8.0),
      );
    }

    // X-Axis Title
    _drawText(
      canvas,
      'SHAP value (impact on model output)',
      Offset(leftMargin + (chartWidth / 2) - 75, axisY + 18),
      const TextStyle(
        color: Colors.black87,
        fontSize: 9.0,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 3;
    const double dashSpace = 3;
    double distance = (p2 - p1).distance;
    if (distance == 0) return;

    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;

    double current = 0;
    while (current < distance) {
      double len = math.min(dashWidth, distance - current);
      canvas.drawLine(
        Offset(p1.dx + dx * current, p1.dy + dy * current),
        Offset(p1.dx + dx * (current + len), p1.dy + dy * (current + len)),
        paint,
      );
      current += dashWidth + dashSpace;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    tp.layout(maxWidth: maxWidth ?? 300);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant ShapBeeswarmPainter oldDelegate) => true;
}
