// lib/screens/insights_screen.dart
// AI Insights page – displays smart recommendations, plant health summary, and actions

import 'package:flutter/material.dart';
import '../models/ai_recommendation.dart';
import '../models/sensor_data.dart';
import '../services/gemini_recommendation_service.dart';
import '../theme/app_theme.dart';
import '../widgets/insight_card_widget.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final GeminiRecommendationService _recommendationService =
      GeminiRecommendationService();
  List<InsightCard> _insights = [];
  AiRecommendationResponse? _aiResponse;
  int? _expandedIndex;
  String _selectedFilter = 'All';
  bool _isRequesting = false;
  Object? _requestError;
  DateTime? _lastUpdated;

  final List<String> _filters = ['All', 'Critical', 'Warning', 'Good'];

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
    if (_aiResponse != null) return _aiResponse!.plantHealthPercentage;
    final total = _insights.length;
    if (total == 0) return 0;
    final good = _goodCount;
    final warning = _warningCount;
    return (((good * 100) + (warning * 60)) / total).round();
  }

  Future<void> _requestAiRecommendation() async {
    setState(() {
      _isRequesting = true;
      _requestError = null;
      _expandedIndex = null;
    });

    try {
      final response = await _recommendationService.requestRecommendation();
      if (!mounted) return;
      setState(() {
        _aiResponse = response;
        _insights = response.toInsightCards();
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestError = e);
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
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
                if (_requestError != null) ...[
                  _buildErrorBanner(),
                  const SizedBox(height: 16),
                ],

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
                if (_isRequesting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_filteredInsights.isEmpty)
                  _buildEmptyState()
                else
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
                        _lastUpdated == null
                            ? 'Belum ada rekomendasi AI • Powered by Gemini'
                            : 'Updated ${_formatUpdateTime(_lastUpdated!)} • Powered by Gemini',
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
          color: scoreColor.withOpacity(0.85),
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
    final summary = _aiResponse?.sensorSummary ??
        'Tekan tombol untuk menganalisis hingga 360 data sensor terbaru dari Firestore menggunakan Gemini.';
    final triggers = _aiResponse?.automationTriggers;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NutriAI Summary',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                if (triggers != null) ...[
                  const SizedBox(height: 12),
                  _buildAutomationTriggerRow(triggers),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRequesting ? null : _requestAiRecommendation,
                    icon: _isRequesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      _isRequesting
                          ? 'Menganalisis...'
                          : 'Request AI Recommendation',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationTriggerRow(AutomationTriggers triggers) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildTriggerChip(
          triggers.waterIcon,
          triggers.activateWaterPump ? 'Water: ON' : 'Water: OFF',
          triggers.activateWaterPump,
        ),
        _buildTriggerChip(
          triggers.fertilizerIcon,
          triggers.activateFertilizerPump
              ? 'Fertilizer: ON'
              : 'Fertilizer: OFF',
          triggers.activateFertilizerPump,
        ),
      ],
    );
  }

  Widget _buildTriggerChip(IconData icon, String label, bool active) {
    final color = active ? AppTheme.statusLow : AppTheme.textLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.statusLow.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.statusLow.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.statusLow,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _requestError.toString(),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.psychology_alt_outlined,
            color: AppTheme.textLight,
            size: 30,
          ),
          SizedBox(height: 8),
          Text(
            'Belum ada rekomendasi. Jalankan analisis AI untuk melihat insight tanaman.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatUpdateTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
