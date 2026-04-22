// lib/widgets/mini_line_chart.dart
// A compact sparkline chart used on the Home dashboard

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MiniLineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const MiniLineChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final spots = List.generate(
      values.length,
      (i) => FlSpot(i.toDouble(), values[i]),
    );

    final minY = values.reduce((a, b) => a < b ? a : b) * 0.92;
    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.08;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.4,
              color: color,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withOpacity(0.3),
                    color.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }
}