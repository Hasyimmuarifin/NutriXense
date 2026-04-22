// lib/screens/insights_screen.dart
// AI Insights page – displays smart recommendations, plant health summary, and actions

import 'package:flutter/material.dart';
import '../models/dummy_data.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';
import '../widgets/insight_card_widget.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final List<InsightCard> _insights;
  int? _expandedIndex;
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Critical', 'Warning', 'Good'];

  @override
  void initState() {
    super.initState();
    _insights = DummyData.getInsights();
  }

  List<InsightCard> get _filteredInsights {
    if (_selectedFilter == 'All') return _insights;
    return _insights.where((i) {
      switch (_selectedFilter) {
        case 'Critical':
          return i.severity == InsightSeverity.critical;
        case 'Warning':
          return i.severity == InsightSeverity.warning;
        case 'Good':
          return i.severity == InsightSeverity.good;
        default:
          return true;
      }
    }).toList();
  }

  int get _criticalCount =>
      _insights.where((i) => i.severity == InsightSeverity.critical).length;
  int get _warningCount =>
      _insights.where((i) => i.severity == InsightSeverity.warning).length;
  int get _goodCount =>
      _insights.where((i) => i.severity == InsightSeverity.good).length;

  // Calculate overall plant health score
  int get _healthScore {
    final total = _insights.length;
    final good = _goodCount;
    final warning = _warningCount;
    return (((good * 100) + (warning * 60)) / total).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            backgroundColor: AppTheme.bgCard,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.cardGradient,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'AI Insights',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Plant Health Report',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Spacer(),
                        // ─── Health summary row ───────────────────────────
                        Row(
                          children: [
                            // Score
                            _buildScoreCircle(),
                            const SizedBox(width: 20),
                            // Stat breakdown
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildStatRow(
                                    Icons.error_outline_rounded,
                                    '$_criticalCount Critical',
                                    AppTheme.statusLow,
                                  ),
                                  const SizedBox(height: 6),
                                  _buildStatRow(
                                    Icons.warning_amber_rounded,
                                    '$_warningCount Warnings',
                                    AppTheme.statusHigh,
                                  ),
                                  const SizedBox(height: 6),
                                  _buildStatRow(
                                    Icons.check_circle_outline_rounded,
                                    '$_goodCount Optimal',
                                    const Color(0xFF69F0AE),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── AI summary banner ──────────────────────────────────────
                _buildAISummaryBanner(),
                const SizedBox(height: 16),

                // ─── Filter chips ───────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filters.map((f) {
                      final isSelected = _selectedFilter == f;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedFilter = f;
                          _expandedIndex = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryGreen
                                : AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // ─── Insight cards ──────────────────────────────────────────
                ..._filteredInsights.asMap().entries.map((entry) {
                  final i = entry.key;
                  final insight = entry.value;
                  return TweenAnimationBuilder<double>(
                    key: ValueKey('${insight.title}_$_selectedFilter'),
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 300 + i * 60),
                    curve: Curves.easeOut,
                    builder: (context, v, child) => Transform.translate(
                      offset: Offset(0, 20 * (1 - v)),
                      child: Opacity(opacity: v, child: child),
                    ),
                    child: InsightCardWidget(
                      insight: insight,
                      expanded: _expandedIndex == i,
                      onTap: () => setState(() {
                        _expandedIndex = _expandedIndex == i ? null : i;
                      }),
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // ─── Last updated ───────────────────────────────────────────
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 12, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Text(
                        'Updated just now • Powered by NutriAI v2.1',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCircle() {
    final Color scoreColor = _healthScore >= 70
        ? AppTheme.statusNormal
        : _healthScore >= 50
            ? AppTheme.statusHigh
            : AppTheme.statusLow;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.15),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$_healthScore',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          const Text(
            'Score',
            style: TextStyle(
              fontSize: 9,
              color: Colors.white60,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAISummaryBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              size: 20,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NutriAI Summary',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your plant shows signs of nitrogen deficiency and acidic soil. Immediate action on nitrogen and pH correction is recommended to prevent further stress. Phosphorus and moisture levels are optimal.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}