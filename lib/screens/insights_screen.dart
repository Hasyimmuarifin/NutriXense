// lib/screens/insights_screen.dart
// AI Insights page – displays smart recommendations, plant health summary, and actions

import 'package:cloud_firestore/cloud_firestore.dart';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<InsightCard> _insights = [];
  AiRecommendationResponse? _aiResponse;
  int? _expandedIndex;
  String _selectedFilter = 'All';
  bool _isRequesting = false;
  bool _isApplyingAutomation = false;
  bool _isAddingSchedule = false;
  bool _scheduleAdded = false;
  Object? _requestError;
  DateTime? _lastUpdated;
  AiPumpAutomationResult? _lastAutomationResult;
  final Map<int, int> _adjustedPumpSeconds = {};

  final List<String> _filters = ['All', 'Kritis', 'Awas', 'Baik'];

  List<InsightCard> get _filteredInsights {
    if (_selectedFilter == 'All') return _insights;
    return _insights.where((i) {
      switch (_selectedFilter) {
        case 'Kritis':
          return i.severity == InsightSeverity.kritis;
        case 'Awas':
          return i.severity == InsightSeverity.awas;
        case 'Baik':
          return i.severity == InsightSeverity.baik;
        default:
          return true;
      }
    }).toList();
  }

  int get _criticalCount =>
      _insights.where((i) => i.severity == InsightSeverity.kritis).length;
  int get _warningCount =>
      _insights.where((i) => i.severity == InsightSeverity.awas).length;
  int get _goodCount =>
      _insights.where((i) => i.severity == InsightSeverity.baik).length;

  // Calculate overall plant health score
  int get _healthScore {
    if (_aiResponse != null) return _aiResponse!.plantHealthPercentage;
    final total = _insights.length;
    if (total == 0) return 0;
    final baik = _goodCount;
    final awas = _warningCount;
    return (((baik * 100) + (awas * 60)) / total).round();
  }

  String get _requestErrorMessage {
    final error = _requestError;
    if (error == null) return '';
    if (error is AiRecommendationException) return error.message;

    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('rate limit') ||
        lower.contains('rate-limit') ||
        lower.contains('resource exhausted') ||
        lower.contains('free_tier') ||
        lower.contains('free tier')) {
      return 'Kuota Gemini API sedang habis atau terkena rate limit. Aplikasi akan memakai analisis DSS lokal bila data sensor tersedia; coba lagi nanti untuk respons penuh dari Gemini.';
    }

    if (lower.contains('503') ||
        lower.contains('generativeaiexception') ||
        lower.contains('server error') ||
        lower.contains('unavailable') ||
        lower.contains('overloaded') ||
        lower.contains('traffic') ||
        lower.contains('timeout')) {
      return 'AI sedang sibuk karena trafik tinggi. Silakan coba lagi dalam beberapa saat.';
    }

    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
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
        _lastAutomationResult = null;
        _scheduleAdded = false;
        _adjustedPumpSeconds
          ..clear()
          ..addEntries(
            response.pumpRecommendations.map(
              (item) => MapEntry(item.relay, item.recommendedSeconds),
            ),
          );
      });
      _alertCountService.updateFromAiRecommendation(
        criticalCount: response.recommendations.kritis.length,
        warningCount: response.recommendations.awas.length,
      );
      if (mounted) {
        setState(() => _isRequesting = false);
      }
      await _showRecommendationPopup(response);
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestError = e);
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  List<PumpFertilizationRecommendation> get _adjustedPumpRecommendations {
    final recommendations = _aiResponse?.pumpRecommendations ?? const [];
    return recommendations
        .map(
          (item) => item.copyWith(
            recommendedSeconds:
                _adjustedPumpSeconds[item.relay] ?? item.recommendedSeconds,
          ),
        )
        .toList(growable: false);
  }

  int _recommendedScheduleDuration({required int fallback}) {
    final recommendations = _adjustedPumpRecommendations;
    if (recommendations.isEmpty) return fallback;
    return recommendations
        .map((item) => item.recommendedSeconds)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<void> _confirmPumpRecommendation() async {
    final recommendations = _adjustedPumpRecommendations;
    if (recommendations.isEmpty) {
      setState(() => _lastAutomationResult = AiPumpAutomationResult(
            activatedPumps: const [],
            reason: _aiResponse?.automationTriggers.reason ?? '',
          ));
      return;
    }

    setState(() => _isApplyingAutomation = true);

    try {
      final result =
          await _pumpAutomationService.applyRecommendations(recommendations);
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

  Future<void> _addRecommendedSchedule() async {
    final response = _aiResponse;
    final schedule = response?.dailyScheduleRecommendation;
    if (schedule == null || !schedule.hasPumps) return;

    final recommendations = _adjustedPumpRecommendations;
    final durationSeconds = recommendations.isEmpty
        ? schedule.durationSeconds
        : recommendations
            .map((item) => item.recommendedSeconds)
            .reduce((a, b) => a > b ? a : b);
    final id = DateTime.now().microsecondsSinceEpoch;

    setState(() => _isAddingSchedule = true);
    try {
      await _firestore.collection('watering_schedules').doc('$id').set({
        'id': id,
        'hour': schedule.hour,
        'minute': schedule.minute,
        'pumpIndexes': schedule.pumpIndexes.toList()..sort(),
        'durationSeconds': durationSeconds,
        'repeatsDaily': true,
        'enabled': true,
        'source': 'gemini_ai_recommendation',
        'reason': schedule.reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _scheduleAdded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'AI daily schedule added to Control at ${schedule.formattedTime}.',
          ),
          backgroundColor: AppTheme.primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestError = e);
    } finally {
      if (mounted) setState(() => _isAddingSchedule = false);
    }
  }

  Future<void> _showRecommendationPopup(
    AiRecommendationResponse response,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final recommendations = response.pumpRecommendations;
            final schedule = response.dailyScheduleRecommendation;
            final hasSchedule = schedule != null && schedule.hasPumps;
            final durationSeconds = _recommendedScheduleDuration(
              fallback: schedule?.durationSeconds ?? 0,
            );

            Future<void> refreshDialog(Future<void> Function() action) async {
              await action();
              if (mounted) setDialogState(() {});
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.82,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppTheme.primaryGreen,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Rekomendasi Pemupukan AI',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cancel',
                            onPressed: _isApplyingAutomation
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              response.sensorSummary,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (recommendations.isEmpty)
                              _buildNoPumpRecommendationBox()
                            else ...[
                              const Text(
                                'Rencana Pemupukan',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Sesuaikan durasi sebelum menekan Konfirmasi.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...recommendations.map(
                                (item) => _buildPumpRecommendationTile(
                                  item,
                                  onDurationChanged: () =>
                                      setDialogState(() {}),
                                ),
                              ),
                            ],
                            if (hasSchedule) ...[
                              const SizedBox(height: 8),
                              _buildSchedulePopupInfo(
                                schedule: schedule,
                                durationSeconds: durationSeconds,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasSchedule) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isAddingSchedule || _scheduleAdded
                                    ? null
                                    : () => refreshDialog(
                                          _addRecommendedSchedule,
                                        ),
                                icon: _isAddingSchedule
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _scheduleAdded
                                            ? Icons.check_circle_rounded
                                            : Icons.event_available_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  _scheduleAdded
                                      ? 'Jadwal Ditambahkan ke Control'
                                      : 'Tambah Jadwal Otomatis ke Control',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryBlue,
                                  side: BorderSide(
                                    color:
                                        AppTheme.primaryBlue.withOpacity(0.35),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isApplyingAutomation
                                      ? null
                                      : () => Navigator.of(dialogContext).pop(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.textSecondary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isApplyingAutomation ||
                                          recommendations.isEmpty
                                      ? null
                                      : () async {
                                          if (dialogContext.mounted) {
                                            Navigator.of(dialogContext).pop();
                                          }
                                          await _confirmPumpRecommendation();
                                        },
                                  icon: _isApplyingAutomation
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_circle_rounded,
                                          size: 18,
                                        ),
                                  label: const Text('Konfirmasi'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primaryGreen,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAutomationSnackBar(AiPumpAutomationResult result) {
    if (!result.hasActivatedPump) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Confirmed: ${result.activatedPumps.join(', ')} applied with adjusted duration.',
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
                              'Kesehatan Tanaman',
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
                                        '$_criticalCount Kritis',
                                        AppTheme.statusLow,
                                      ),
                                      _buildStatPill(
                                        Icons.warning_amber_rounded,
                                        '$_warningCount Awas',
                                        AppTheme.statusHigh,
                                      ),
                                      _buildStatPill(
                                        Icons.check_circle_outline_rounded,
                                        '$_goodCount Baik',
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
                if (_aiResponse != null) ...[
                  const SizedBox(height: 12),
                  _buildPumpRecommendationPanel(_aiResponse!),
                ],
                if (_lastAutomationResult != null) ...[
                  const SizedBox(height: 10),
                  _buildAutomationResult(_lastAutomationResult!),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRequesting ||
                            _isApplyingAutomation ||
                            _isAddingSchedule
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
                          : 'Minta Rekomendasi AI',
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
          triggers.activateNitrogenPump
              ? 'Pompa A N: Direkomendasikan'
              : 'Pompa A N: Normal',
          triggers.activateNitrogenPump,
        ),
        _buildTriggerChip(
          Icons.grass_rounded,
          triggers.activatePhosphorusPump
              ? 'Pompa B P: Direkomendasikan'
              : 'Pompa B P: Normal',
          triggers.activatePhosphorusPump,
        ),
        _buildTriggerChip(
          Icons.local_florist_rounded,
          triggers.activatePotassiumPump
              ? 'Pompa C K: Direkomendasikan'
              : 'Pompa C K: Normal',
          triggers.activatePotassiumPump,
        ),
        _buildTriggerChip(
          Icons.water_drop_rounded,
          triggers.activateWaterPump
              ? 'Pompa D Air: Direkomendasikan'
              : 'Pompa D Air: Normal',
          triggers.activateWaterPump,
        ),
      ],
    );
  }

  Widget _buildPumpRecommendationPanel(AiRecommendationResponse response) {
    final recommendations = response.pumpRecommendations;
    final label = recommendations.isEmpty
        ? 'Lihat Hasil Rekomendasi AI'
        : 'Lihat ${recommendations.length} Rekomendasi Pemupukan';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isApplyingAutomation
            ? null
            : () => _showRecommendationPopup(response),
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryGreen,
          side: BorderSide(color: AppTheme.primaryGreen.withOpacity(0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        ),
      ),
    );
  }

  Widget _buildPumpRecommendationTile(
      PumpFertilizationRecommendation recommendation,
      {VoidCallback? onDurationChanged}) {
    final seconds = _adjustedPumpSeconds[recommendation.relay] ??
        recommendation.recommendedSeconds;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${recommendation.pumpName} - ${recommendation.nutrient}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$seconds detik',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${recommendation.reason} Defisit ${recommendation.formattedDeficitPercent}.',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
          Slider(
            value: seconds.toDouble(),
            min: 5,
            max: 300,
            divisions: 59,
            label: '$seconds detik',
            activeColor: AppTheme.primaryGreen,
            onChanged: (value) {
              setState(() {
                _adjustedPumpSeconds[recommendation.relay] = value.round();
              });
              onDurationChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoPumpRecommendationBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.statusNormal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.statusNormal.withOpacity(0.2)),
      ),
      child: const Text(
        'Tidak ada pompa yang perlu dijalankan. Semua nilai utama sudah berada pada ambang aman atau tidak membutuhkan koreksi langsung.',
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.textSecondary,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSchedulePopupInfo({
    required DailyFertilizationScheduleRecommendation schedule,
    required int durationSeconds,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recommended Daily Schedule',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rekomendasi jadwal harian pukul ${schedule.formattedTime} selama $durationSeconds detik. Gunakan tombol di bawah popup untuk menambahkannya ke menu Control.',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationResult(AiPumpAutomationResult result) {
    final text = result.hasActivatedPump
        ? 'Telah dikonfirmasi : ${result.activatedPumps.join(', ')}'
        : 'Tidak perlu mengaktifkan pompa';

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
              _requestErrorMessage,
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
