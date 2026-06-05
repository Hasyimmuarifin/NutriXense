// lib/screens/insights_screen.dart
// AI Insights page – displays smart recommendations, plant health summary, and actions

import 'package:flutter/material.dart';
import '../models/ai_recommendation.dart';
import '../models/sensor_data.dart';
import '../services/ai_pump_automation_service.dart';
import '../services/alert_count_service.dart';
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
  final AiPumpAutomationService _pumpAutomationService =
      AiPumpAutomationService();
  final AlertCountService _alertCountService = AlertCountService.instance;
  List<InsightCard> _insights = [];
  AiRecommendationResponse? _aiResponse;
  int? _expandedIndex;
  String _selectedFilter = 'All';
  bool _isRequesting = false;
  bool _isApplyingAutomation = false;
  Object? _requestError;
  DateTime? _lastUpdated;
  AiPumpAutomationResult? _lastAutomationResult;

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
      _alertCountService.updateFromAiRecommendation(
        criticalCount: response.recommendations.critical.length,
        warningCount: response.recommendations.warning.length,
      );
      await _applyPumpAutomation(response.automationTriggers);
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestError = e);
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  Future<void> _applyPumpAutomation(AutomationTriggers triggers) async {
    if (!triggers.hasActivePump) {
      setState(() => _lastAutomationResult = AiPumpAutomationResult(
            activatedPumps: const [],
            reason: triggers.reason,
          ));
      return;
    }

    setState(() => _isApplyingAutomation = true);

    try {
      final result = await _pumpAutomationService.apply(triggers);
      if (!mounted) return;
      setState(() => _lastAutomationResult = result);
      _showAutomationSnackBar(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestError = e);
    } finally {
      if (mounted) {
        setState(() => _isApplyingAutomation = false);
      }
    }
  }

  void _showAutomationSnackBar(AiPumpAutomationResult result) {
    if (!result.hasActivatedPump) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'AI activated ${result.activatedPumps.join(', ')} for 5 seconds.',
        ),
        backgroundColor: AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Gradient App Bar ────────────────────────────────────────────
          SliverAppBar(
            pinned: false,
            expandedHeight: 220,
            backgroundColor: AppTheme.bgPrimary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: const Alignment(0, 1),
                        child: Opacity(
                          opacity: 0.06,
                          child: Image.asset(
                            'assets/images/w_nutrixense_cropped.png',
                            width: 280,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Image.asset(
                                        'assets/images/w_nutrixense.png',
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.contain,
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'NutriXense',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.25),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'AI Insights',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Plant Health Report',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                _buildScoreCircle(),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildStatPill(
                                        Icons.error_outline_rounded,
                                        '$_criticalCount Critical',
                                        AppTheme.statusLow,
                                      ),
                                      _buildStatPill(
                                        Icons.warning_amber_rounded,
                                        '$_warningCount Warnings',
                                        AppTheme.statusHigh,
                                      ),
                                      _buildStatPill(
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
                  ],
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
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 4,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 12, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Text(
                        _lastUpdated == null
                            ? 'Belum ada rekomendasi AI • Powered by Gemini'
                            : 'Updated ${_formatUpdateTime(_lastUpdated!)} • Powered by Gemini',
                        textAlign: TextAlign.center,
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

  Widget _buildStatPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAISummaryBanner() {
    final summary = _aiResponse?.sensorSummary ??
        'Tekan tombol untuk memeriksa kondisi tanaman terbaru dan mendapatkan saran perawatan yang mudah dipahami.';
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
                if (_lastAutomationResult != null) ...[
                  const SizedBox(height: 10),
                  _buildAutomationResult(_lastAutomationResult!),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRequesting || _isApplyingAutomation
                        ? null
                        : _requestAiRecommendation,
                    icon: _isRequesting || _isApplyingAutomation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      _isRequesting
                          ? 'Menganalisis...'
                          : _isApplyingAutomation
                              ? 'Applying pump automation...'
                              : 'Request AI Recommendation',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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
          Icons.eco_rounded,
          triggers.activateNitrogenPump ? 'Pump A N: ON' : 'Pump A N: OFF',
          triggers.activateNitrogenPump,
        ),
        _buildTriggerChip(
          Icons.grass_rounded,
          triggers.activatePhosphorusPump ? 'Pump B P: ON' : 'Pump B P: OFF',
          triggers.activatePhosphorusPump,
        ),
        _buildTriggerChip(
          Icons.local_florist_rounded,
          triggers.activatePotassiumPump ? 'Pump C K: ON' : 'Pump C K: OFF',
          triggers.activatePotassiumPump,
        ),
        _buildTriggerChip(
          Icons.water_drop_rounded,
          triggers.activateWaterPump ? 'Pump D Water: ON' : 'Pump D Water: OFF',
          triggers.activateWaterPump,
        ),
      ],
    );
  }

  Widget _buildAutomationResult(AiPumpAutomationResult result) {
    final text = result.hasActivatedPump
        ? 'Applied: ${result.activatedPumps.join(', ')}'
        : 'No pump activation needed';

    return Text(
      text,
      style: TextStyle(
        color: result.hasActivatedPump
            ? AppTheme.primaryGreen
            : AppTheme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
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
