import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/ai_recommendation.dart';
import '../theme/app_theme.dart';

enum XaiShapViewMode {
  summaryBar('Bar SHAP'),
  matrix('Matriks Fitur'),
  pumpReasons('Per Pompa');

  final String label;
  const XaiShapViewMode(this.label);
}

class XaiShapVisualizationWidget extends StatefulWidget {
  final AiRecommendationResponse response;
  final List<XaiFactorItem> factors;

  const XaiShapVisualizationWidget({
    super.key,
    required this.response,
    required this.factors,
  });

  @override
  State<XaiShapVisualizationWidget> createState() =>
      _XaiShapVisualizationWidgetState();
}

class _XaiShapVisualizationWidgetState
    extends State<XaiShapVisualizationWidget> {
  XaiShapViewMode _viewMode = XaiShapViewMode.summaryBar;
  int _selectedRelayFilter = 0; // 0 = Semua, 1 = N, 2 = P, 3 = K, 4 = Air

  @override
  Widget build(BuildContext context) {
    final shapItems = _buildShapItems();
    final hasItems = shapItems.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryBlue,
                      AppTheme.primaryBlue.withOpacity(0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visualisasi XAI SHAP',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'SHapley Additive exPlanations',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _buildPillBadge(
                label: 'Post-Hoc XAI',
                color: AppTheme.primaryBlue,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Description
          Text(
            hasItems
                ? 'Analisis SHAP menghitung kontribusi matematis persis (SHAP Value φ) dari setiap parameter sensor dan faktor lingkungan dalam mendorong (+) atau menahan (-) nilai keputusan pemupukan.'
                : 'Tidak ada koreksi nutrisi yang dominan pada periode ini. Skor nutrisi tanaman dan status ambang berada dalam batas normal.',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          if (hasItems) ...[
            // View Mode Tab Switcher
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: XaiShapViewMode.values.map((mode) {
                  final isSelected = _viewMode == mode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(mode.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) setState(() => _viewMode = mode);
                      },
                      selectedColor: AppTheme.primaryBlue,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primaryBlue
                              : AppTheme.primaryBlue.withOpacity(0.15),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Relay Filter Buttons
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildRelayFilterChip(0, 'Semua Pompa', Icons.tune_rounded),
                  _buildRelayFilterChip(1, 'Pompa A (N)', Icons.eco_rounded),
                  _buildRelayFilterChip(2, 'Pompa B (P)', Icons.science_rounded),
                  _buildRelayFilterChip(3, 'Pompa C (K)', Icons.spa_rounded),
                  _buildRelayFilterChip(4, 'Pompa D (Air)', Icons.water_drop_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Content Panel based on active tab
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildActiveViewContent(shapItems),
            ),
          ] else ...[
            _buildNoShapCorrectionCard(),
          ],

          const SizedBox(height: 12),

          // Footer Tags
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPillBadge(
                  label: 'Local Explainable AI',
                  color: AppTheme.primaryGreen,
                ),
                _buildPillBadge(
                  label: 'SHAP Diverging Force',
                  color: AppTheme.primaryBlue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelayFilterChip(int relayId, String title, IconData icon) {
    final isSelected = _selectedRelayFilter == relayId;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _selectedRelayFilter = relayId),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryBlue.withOpacity(0.12)
                : Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryBlue
                  : AppTheme.textLight.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppTheme.primaryBlue : AppTheme.textLight,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveViewContent(List<XaiFactorItem> items) {
    final filtered = _filterItemsByRelay(items);

    switch (_viewMode) {
      case XaiShapViewMode.summaryBar:
        return _buildSummaryBarPlotPanel(filtered);
      case XaiShapViewMode.matrix:
        return _buildMatrixDetailPanel(filtered);
      case XaiShapViewMode.pumpReasons:
        return _buildPumpReasonsPanel();
    }
  }

  List<XaiFactorItem> _filterItemsByRelay(List<XaiFactorItem> items) {
    if (_selectedRelayFilter == 0) return items;
    if (_selectedRelayFilter == 1) {
      return items
          .where((e) =>
              e.label.contains('N') ||
              e.featureKey.contains('n_') ||
              e.detail.contains('Pompa A'))
          .toList();
    }
    if (_selectedRelayFilter == 2) {
      return items
          .where((e) =>
              e.label.contains('P') ||
              e.featureKey.contains('p_') ||
              e.detail.contains('Pompa B'))
          .toList();
    }
    if (_selectedRelayFilter == 3) {
      return items
          .where((e) =>
              e.label.contains('K') ||
              e.featureKey.contains('k_') ||
              e.detail.contains('Pompa C'))
          .toList();
    }
    if (_selectedRelayFilter == 4) {
      return items
          .where((e) =>
              e.label.toLowerCase().contains('air') ||
              e.label.toLowerCase().contains('kelembapan') ||
              e.label.toLowerCase().contains('suhu') ||
              e.detail.contains('Pompa D'))
          .toList();
    }
    return items;
  }

  // SHAP Summary Force / Bar Plot Panel
  Widget _buildSummaryBarPlotPanel(List<XaiFactorItem> items) {
    if (items.isEmpty) return _buildEmptyFilterState();

    final sortedItems = List<XaiFactorItem>.from(items)
      ..sort((a, b) => b.shapValue.abs().compareTo(a.shapValue.abs()));

    double maxAbsVal = 0.01;
    for (final item in sortedItems) {
      maxAbsVal = math.max(maxAbsVal, item.shapValue.abs());
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '(φ) Plot Diverging Force',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '<- Menahan  |  Mendorong ->',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ...sortedItems.map((item) {
            final val = item.shapValue;
            final isPositive = val >= 0;
            final absRatio = (val.abs() / maxAbsVal).clamp(0.03, 1.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(item.icon, size: 14, color: item.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${isPositive ? '+' : ''}${val.toStringAsFixed(2)} φ',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: item.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final totalWidth = constraints.maxWidth;
                      final center = totalWidth / 2;
                      final barWidth = (totalWidth / 2) * absRatio;

                      return Container(
                        height: 12,
                        width: totalWidth,
                        decoration: BoxDecoration(
                          color: AppTheme.textLight.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Stack(
                          children: [
                            // Center Axis
                            Positioned(
                              left: center - 0.75,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 1.5,
                                color: AppTheme.textLight.withOpacity(0.4),
                              ),
                            ),
                            // Bar
                            Positioned(
                              left: isPositive ? center : center - barWidth,
                              width: barWidth,
                              top: 1,
                              bottom: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isPositive
                                      ? AppTheme.primaryGreen
                                      : AppTheme.statusHigh,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Feature Matrix Detail Panel
  Widget _buildMatrixDetailPanel(List<XaiFactorItem> items) {
    if (items.isEmpty) return _buildEmptyFilterState();

    return Column(
      children: items.map((item) {
        final impactRatio = (item.impact.clamp(0, 100) / 100).toDouble();

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: item.color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: item.color.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 17, color: item.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: item.color.withOpacity(0.3)),
                          ),
                          child: Text(
                            item.direction,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: item.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: impactRatio,
                        minHeight: 5,
                        backgroundColor: AppTheme.textLight.withOpacity(0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(item.color),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.detail,
                      style: const TextStyle(
                        fontSize: 10.8,
                        color: AppTheme.textSecondary,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<PumpFertilizationRecommendation> _filterPumpRecommendationsByRelay(
    List<PumpFertilizationRecommendation> recommendations,
  ) {
    if (_selectedRelayFilter == 0) return recommendations;
    return recommendations.where((item) {
      if (item.relay == _selectedRelayFilter) return true;
      if (item.pumpIndex + 1 == _selectedRelayFilter) return true;
      if (_selectedRelayFilter == 1 &&
          (item.pumpName.contains('Pompa A') ||
              item.nutrient.contains('Nitrogen') ||
              item.nutrient.contains('N'))) {
        return true;
      }
      if (_selectedRelayFilter == 2 &&
          (item.pumpName.contains('Pompa B') ||
              item.nutrient.contains('Fosfor') ||
              item.nutrient.contains('P'))) {
        return true;
      }
      if (_selectedRelayFilter == 3 &&
          (item.pumpName.contains('Pompa C') ||
              item.nutrient.contains('Kalium') ||
              item.nutrient.contains('K'))) {
        return true;
      }
      if (_selectedRelayFilter == 4 &&
          (item.pumpName.contains('Pompa D') ||
              item.nutrient.toLowerCase().contains('air'))) {
        return true;
      }
      return false;
    }).toList();
  }

  // Pump Specific Reasons Panel
  Widget _buildPumpReasonsPanel() {
    final allRecommendations = widget.response.pumpRecommendations;
    final pumpRecommendations =
        _filterPumpRecommendationsByRelay(allRecommendations);
    if (pumpRecommendations.isEmpty) {
      return _buildEmptyFilterState();
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analisis Keputusan per Pompa',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...pumpRecommendations.map((item) {
            final color = _getPumpColor(item);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_getPumpIcon(item), size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.pumpName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${item.recommendedSeconds} Detik',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.reason,
                    style: const TextStyle(
                      fontSize: 10.8,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.nutrient.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Nutrisi Target: ${item.nutrient} (Current: ${item.currentValue} ${item.unit}, Min: ${item.targetMinimum} ${item.unit})',
                      style: const TextStyle(
                        fontSize: 9.8,
                        color: AppTheme.textLight,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyFilterState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textLight.withOpacity(0.15)),
      ),
      child: Center(
        child: Text(
          'Tidak ada data SHAP untuk filter pompa terpilih.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildNoShapCorrectionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.statusNormal,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Skor nutrisi tanaman ${widget.response.plantHealthPercentage}%. Seluruh parameter berada dalam rentang ideal sehingga tidak ada koreksi SHAP yang diperlukan.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<XaiFactorItem> _buildShapItems() {
    if (widget.response.xaiContributions.isNotEmpty) {
      return widget.response.xaiContributions.map((contrib) {
        final val = contrib.contribution;
        final isPositive = val >= 0;
        final color = isPositive ? AppTheme.primaryGreen : AppTheme.statusHigh;

        return XaiFactorItem(
          label: contrib.label,
          direction: contrib.direction,
          detail: contrib.detail,
          impact: (val.abs() * 15).clamp(10, 100).toDouble(),
          icon: _getIconForFeature(contrib.feature),
          color: color,
          reducesDose: !isPositive,
          featureKey: contrib.feature,
          rawValue: contrib.featureValue,
          shapValue: val,
        );
      }).toList();
    }

    return widget.factors.map((item) {
      final shapVal = item.reducesDose ? -(item.impact / 15.0) : (item.impact / 15.0);
      return XaiFactorItem(
        label: item.label,
        direction: item.direction,
        detail: item.detail,
        impact: item.impact,
        icon: item.icon,
        color: item.color,
        reducesDose: item.reducesDose,
        featureKey: item.featureKey,
        rawValue: item.rawValue,
        shapValue: shapVal,
      );
    }).toList();
  }

  IconData _getIconForFeature(String feature) {
    if (feature.contains('ec')) return Icons.bolt_rounded;
    if (feature.contains('n_') || feature.contains('nitrogen')) return Icons.eco_rounded;
    if (feature.contains('p_') || feature.contains('phosphorus')) return Icons.science_rounded;
    if (feature.contains('k_') || feature.contains('potassium')) return Icons.spa_rounded;
    if (feature.contains('ph')) return Icons.opacity_rounded;
    if (feature.contains('moisture') || feature.contains('water')) return Icons.water_drop_rounded;
    if (feature.contains('temp')) return Icons.thermostat_rounded;
    if (feature.contains('medium')) return Icons.terrain_rounded;
    return Icons.analytics_rounded;
  }

  IconData _getPumpIcon(PumpFertilizationRecommendation item) {
    if (item.relay == 4) return Icons.water_drop_rounded;
    return Icons.eco_rounded;
  }

  Color _getPumpColor(PumpFertilizationRecommendation item) {
    if (item.relay == 4) return AppTheme.lightBlue;
    if (item.relay == 1) return AppTheme.primaryGreen;
    if (item.relay == 2) return AppTheme.primaryBlue;
    if (item.relay == 3) return AppTheme.statusHigh;
    return AppTheme.primaryBlue;
  }
}

class XaiFactorItem {
  final String label;
  final String direction;
  final String detail;
  final double impact;
  final IconData icon;
  final Color color;
  final bool reducesDose;
  final String featureKey;
  final double rawValue;
  final double shapValue;

  const XaiFactorItem({
    required this.label,
    required this.direction,
    required this.detail,
    required this.impact,
    required this.icon,
    required this.color,
    required this.reducesDose,
    this.featureKey = '',
    this.rawValue = 0.0,
    this.shapValue = 0.0,
  });
}
