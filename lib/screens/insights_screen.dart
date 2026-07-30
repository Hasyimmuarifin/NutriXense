// lib/screens/insights_screen.dart
// AI Insights page – displays smart recommendations, plant health summary, and actions

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_recommendation.dart';
import '../models/pump_flow_rate.dart';
import '../models/sensor_data.dart';
import '../services/ai_pump_automation_service.dart';
import '../services/alert_count_service.dart';
import '../services/gemini_recommendation_service.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/insight_card_widget.dart';

const int _maxCustomPumpDurationSeconds = 30;

class _XaiContributionItem {
  const _XaiContributionItem({
    required this.label,
    required this.detail,
    required this.score,
    required this.share,
    required this.featureValueRatio,
    required this.color,
  });

  final String label;
  final String detail;
  final double score;
  final double share;
  final double featureValueRatio;
  final Color color;
}

class _XaiBeeswarmPainter extends CustomPainter {
  const _XaiBeeswarmPainter(this.items);

  final List<_XaiContributionItem> items;

  static const Color _lowFeatureColor = Color(0xFF0B8CE8);
  static const Color _midFeatureColor = Color(0xFF7B5CD6);
  static const Color _highFeatureColor = Color(0xFFE6005C);

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || size.width <= 0 || size.height <= 0) return;

    final leftLabelWidth = size.width < 360 ? 82.0 : 102.0;
    const rightLegendWidth = 48.0;
    const topPadding = 28.0;
    const bottomPadding = 34.0;
    final plotLeft = leftLabelWidth;
    final plotRight = math.max(plotLeft + 80, size.width - rightLegendWidth);
    final plotWidth = plotRight - plotLeft;
    final plotCenterX = plotLeft + (plotWidth / 2);
    final rowHeight = (size.height - topPadding - bottomPadding) / items.length;
    const maxImpact = 6.0;
    final maxScore = items
        .map((item) => item.score.abs())
        .fold<double>(0, (max, score) => math.max(max, score));

    _drawText(
      canvas,
      'Ringkasan penjelasan lokal',
      const Offset(0, 0),
      const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: plotRight,
    );

    final gridPaint = Paint()
      ..color = AppTheme.textLight.withOpacity(0.18)
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = AppTheme.textSecondary.withOpacity(0.42)
      ..strokeWidth = 1.2;

    for (var index = 0; index < items.length; index++) {
      final rowCenterY = topPadding + (rowHeight * (index + 0.5));
      _drawDashedLine(
        canvas,
        Offset(plotLeft, rowCenterY),
        Offset(plotRight, rowCenterY),
        gridPaint,
      );
      _drawText(
        canvas,
        items[index].label,
        Offset(0, rowCenterY - 7),
        const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
        ),
        maxWidth: leftLabelWidth - 8,
        maxLines: 1,
      );
      canvas.drawCircle(
        Offset(leftLabelWidth - 6, rowCenterY),
        2.4,
        Paint()..color = items[index].color.withOpacity(0.85),
      );
    }

    canvas.drawLine(
      Offset(plotCenterX, topPadding - 6),
      Offset(plotCenterX, size.height - bottomPadding + 4),
      zeroPaint,
    );

    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final rowCenterY = topPadding + (rowHeight * (index + 0.5));
      final normalizedScore =
          maxScore <= 0 ? item.share.clamp(0.0, 1.0) : item.score / maxScore;
      final rowImpact = 1.2 + (normalizedScore.clamp(0.0, 1.0) * 4.8);
      final pointCount = 16 + (normalizedScore * 12).round();

      for (var pointIndex = 0; pointIndex < pointCount; pointIndex++) {
        final noiseA = _unitNoise(index, pointIndex, 1);
        final noiseB = _unitNoise(index, pointIndex, 2);
        final noiseC = _unitNoise(index, pointIndex, 3);
        final noiseD = _unitNoise(index, pointIndex, 4);
        final positiveSide = noiseA > 0.25;
        final sideMultiplier = positiveSide ? 1.0 : -0.62;
        final magnitude = rowImpact * (0.18 + (noiseB * 0.82));
        final xImpact = (sideMultiplier * magnitude).clamp(
          -maxImpact,
          maxImpact,
        );
        final x = plotCenterX + (xImpact / maxImpact) * (plotWidth / 2);
        final yJitter = (noiseC - 0.5) * rowHeight * 0.54;
        final y = rowCenterY + yJitter;
        final featureValue =
            (item.featureValueRatio * 0.72 + noiseD * 0.28).clamp(0.0, 1.0);
        final color = _featureColor(featureValue).withOpacity(0.82);

        canvas.drawCircle(
          Offset(x.toDouble(), y),
          2.25 + (noiseD * 0.75),
          Paint()..color = color,
        );
      }
    }

    _drawAxis(canvas, size, plotLeft, plotCenterX, plotRight);
    _drawFeatureValueLegend(canvas, size, plotRight + 8, topPadding);
  }

  void _drawAxis(
    Canvas canvas,
    Size size,
    double plotLeft,
    double plotCenterX,
    double plotRight,
  ) {
    final axisY = size.height - 24;
    final tickPaint = Paint()
      ..color = AppTheme.textLight.withOpacity(0.55)
      ..strokeWidth = 1;

    canvas.drawLine(
        Offset(plotLeft, axisY), Offset(plotRight, axisY), tickPaint);
    for (final tick in [
      (x: plotLeft, label: '-6'),
      (x: plotCenterX, label: '0'),
      (x: plotRight, label: '6'),
    ]) {
      canvas.drawLine(
        Offset(tick.x, axisY - 3),
        Offset(tick.x, axisY + 3),
        tickPaint,
      );
      _drawText(
        canvas,
        tick.label,
        Offset(tick.x - 7, axisY + 5),
        const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
        maxWidth: 18,
      );
    }

    _drawText(
      canvas,
      'Kontribusi XAI pada keputusan pompa',
      Offset(plotLeft, size.height - 10),
      const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 7,
        fontWeight: FontWeight.w900,
      ),
      maxWidth: size.width - plotLeft - 2,
      maxLines: 1,
    );
  }

  void _drawFeatureValueLegend(
    Canvas canvas,
    Size size,
    double x,
    double top,
  ) {
    final barHeight = size.height - top - 42;
    if (barHeight <= 40) return;

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, top, 5, barHeight),
      const Radius.circular(999),
    );
    final gradient = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [_lowFeatureColor, _midFeatureColor, _highFeatureColor],
    ).createShader(barRect.outerRect);

    canvas.drawRRect(barRect, Paint()..shader = gradient);
    _drawText(
      canvas,
      'Tinggi',
      Offset(x + 9, top - 2),
      const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 6.5,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: 30,
    );
    _drawText(
      canvas,
      'Rendah',
      Offset(x + 9, top + barHeight - 8),
      const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 6.5,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: 34,
    );

    canvas.save();
    canvas.translate(x + 22, top + (barHeight / 2) + 26);
    canvas.rotate(-math.pi / 2);
    _drawText(
      canvas,
      'Nilai fitur',
      Offset.zero,
      const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 8,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: barHeight,
    );
    canvas.restore();
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    var x = start.dx;
    while (x < end.dx) {
      canvas.drawLine(
        Offset(x, start.dy),
        Offset(math.min(x + dashWidth, end.dx), end.dy),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      ellipsis: '...',
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  double _unitNoise(int row, int point, int salt) {
    final value = math.sin((row + 1) * 12.9898 + (point + 1) * 78.233 + salt);
    final scaled = value * 43758.5453;
    return scaled - scaled.floorToDouble();
  }

  Color _featureColor(double value) {
    if (value < 0.5) {
      return Color.lerp(_lowFeatureColor, _midFeatureColor, value * 2)!;
    }
    return Color.lerp(_midFeatureColor, _highFeatureColor, (value - 0.5) * 2)!;
  }

  @override
  bool shouldRepaint(covariant _XaiBeeswarmPainter oldDelegate) {
    return oldDelegate.items != items;
  }
}

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
  AiRecommendationAgronomicInput? _lastAgronomicInput;
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
    final compact = lower.replaceAll(RegExp(r'[\s_\-]'), '');
    final isDailyLimit = (lower.contains('429') ||
            lower.contains('quota') ||
            lower.contains('resource exhausted') ||
            lower.contains('rate limit') ||
            lower.contains('rate-limit')) &&
        (lower.contains('requests per day') ||
            lower.contains('request per day') ||
            lower.contains('per day') ||
            lower.contains('daily') ||
            lower.contains('rpd') ||
            compact.contains('requestsperday') ||
            compact.contains('requestperday'));

    if (isDailyLimit) {
      return 'Kuota harian Gemini API (RPD) sudah tercapai. Aplikasi memakai analisis DSS/XAI lokal agar rekomendasi tetap tersedia.';
    }

    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('rate limit') ||
        lower.contains('rate-limit') ||
        lower.contains('resource exhausted') ||
        lower.contains('free_tier') ||
        lower.contains('free tier')) {
      return 'Gemini API terkena limit sementara (RPM/TPM) atau kuota non-harian. Aplikasi tidak memakai fallback lokal otomatis; tunggu beberapa saat lalu coba lagi.';
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

    return raw.replaceFirst(RegExp(r'^(Exception|Bad state):\s*'), '');
  }

  Future<void> _promptAndRequestAiRecommendation() async {
    final input = await _showAgronomicInputDialog();
    if (input == null || !mounted) return;

    await _requestAiRecommendation(input);
  }

  Future<void> _requestAiRecommendation(
    AiRecommendationAgronomicInput input,
  ) async {
    setState(() {
      _isRequesting = true;
      _requestError = null;
      _expandedIndex = null;
      _lastAgronomicInput = input;
    });

    try {
      final response = await _recommendationService.requestRecommendation(
        input: input,
      );
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
              (item) => MapEntry(
                item.relay,
                _clampCustomPumpDuration(item.recommendedSeconds),
              ),
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

  Future<AiRecommendationAgronomicInput?> _showAgronomicInputDialog() async {
    return showDialog<AiRecommendationAgronomicInput>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _LandAreaInputDialog(
          initialInput: _lastAgronomicInput,
          formatLandArea: _formatLandArea,
          parseLandAreaNumber: _parseLandAreaSquareMeters,
        );
      },
    );
  }

  List<PumpFertilizationRecommendation> get _adjustedPumpRecommendations {
    final recommendations = _aiResponse?.pumpRecommendations ?? const [];
    return recommendations
        .map(
          (item) => item.copyWith(
            recommendedSeconds: _clampCustomPumpDuration(
              _adjustedPumpSeconds[item.relay] ?? item.recommendedSeconds,
            ),
          ),
        )
        .toList(growable: false);
  }

  int _recommendedScheduleDuration({required int fallback}) {
    final recommendations = _adjustedPumpRecommendations;
    if (recommendations.isEmpty) return _clampCustomPumpDuration(fallback);
    return _clampCustomPumpDuration(
      recommendations
          .map((item) => item.recommendedSeconds)
          .reduce((a, b) => a > b ? a : b),
    );
  }

  int _clampCustomPumpDuration(int seconds) {
    return seconds.clamp(1, _maxCustomPumpDurationSeconds).toInt();
  }

  double? _parseLandAreaSquareMeters(String input) {
    var text = input
        .toLowerCase()
        .replaceAll('m²', '')
        .replaceAll('m2', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    if (text.isEmpty) return null;

    text = text.replaceAll(RegExp(r'[^0-9\.,]'), '');
    if (text.isEmpty) return null;

    final hasComma = text.contains(',');
    final hasDot = text.contains('.');
    if (hasComma) {
      text = text.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(text);
    }

    if (hasDot) {
      final parts = text.split('.');
      final looksLikeThousands = parts.length > 1 &&
          parts.first != '0' &&
          parts.skip(1).every((part) => part.length == 3);
      if (looksLikeThousands) {
        return double.tryParse(parts.join());
      }
    }

    return double.tryParse(text);
  }

  String _formatLandArea(double value) {
    if (value >= 1000 && value == value.roundToDouble()) {
      return value.round().toString().replaceAllMapped(
            RegExp(r'\B(?=(\d{3})+(?!\d))'),
            (_) => '.',
          );
    }

    final fixed = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value < 0.01 ? 4 : 2);
    if (!fixed.contains('.')) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatAnalysisWindowLabel(AiAnalysisWindowProfile window) {
    final start = window.customStartAt;
    final end = window.customEndAt;
    if (!window.isCustom || start == null || end == null) return window.label;

    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return 'Custom ${DateFormat('dd/MM/yyyy HH:mm').format(start)}-${DateFormat('HH:mm').format(end)}';
    }

    return 'Custom ${DateFormat('dd/MM HH:mm').format(start)}-${DateFormat('dd/MM HH:mm').format(end)}';
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
      showAppTextSnackBar(
        context,
        _requestErrorMessage,
        AppTheme.statusLow,
      );
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
    final durationSeconds = _recommendedScheduleDuration(
      fallback: schedule.durationSeconds,
    );
    final durationSecondsByPump = {
      for (final item in recommendations)
        '${item.pumpIndex}': _clampCustomPumpDuration(item.recommendedSeconds),
    };
    final id = DateTime.now().microsecondsSinceEpoch;

    setState(() => _isAddingSchedule = true);
    try {
      await _firestore.collection('watering_schedules').doc('$id').set({
        'id': id,
        'hour': schedule.hour,
        'minute': schedule.minute,
        'pumpIndexes': schedule.pumpIndexes.toList()..sort(),
        'durationSeconds': durationSeconds,
        if (durationSecondsByPump.isNotEmpty)
          'durationSecondsByPump': durationSecondsByPump,
        'repeatsDaily': true,
        'enabled': true,
        'source': 'gemini_ai_recommendation',
        'reason': schedule.reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _scheduleAdded = true);
      showAppTextSnackBar(
        context,
        'AI daily schedule added to Control at ${schedule.formattedTime}.',
        AppTheme.primaryGreen,
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
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppTheme.primaryGreen,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Rekomendasi Pemupukan AI',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 21,
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
                            _buildXaiVisualizationPanel(response),
                            const SizedBox(height: 12),
                            Text(
                              response.sensorSummary,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.textSecondary,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // if (_lastAgronomicInput != null) ...[
                            //   const SizedBox(height: 10),
                            //   _buildAgronomicInputInfoBox(
                            //     _lastAgronomicInput!,
                            //   ),
                            // ],
                            const SizedBox(height: 14),
                            if (recommendations.isEmpty)
                              _buildNoPumpRecommendationBox()
                            else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primaryGreen.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        AppTheme.primaryGreen.withOpacity(0.18),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.water_drop_rounded,
                                      size: 20,
                                      color: AppTheme.primaryGreen,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Rencana Pemupukan',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 19,
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...recommendations.map(
                                (item) => _buildPumpRecommendationTile(
                                  item,
                                  onDurationChanged: () =>
                                      setDialogState(() {}),
                                ),
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
                                      ? 'Rekomendasi Ditambahkan ke Jadwal'
                                      : 'Tambah Rekomendasi ke Jadwal Harian',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryBlue,
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
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
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
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
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
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

    showAppTextSnackBar(
      context,
      'Berhasil: Pompa ${result.activatedPumps.join(', ')} telah dijalankan dengan durasi yang telah disesuaikan.',
      AppTheme.primaryGreen,
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
                            const SizedBox(height: 16),
                            const Text(
                              'Kesehatan Tanaman',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildScoreCircle(),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatPill(
                                          Icons.error_outline_rounded,
                                          '$_criticalCount Kritis',
                                          AppTheme.statusLow,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildStatPill(
                                          Icons.warning_amber_rounded,
                                          '$_warningCount Awas',
                                          AppTheme.statusHigh,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildStatPill(
                                          Icons.check_circle_outline_rounded,
                                          '$_goodCount Baik',
                                          const Color(0xFF69F0AE),
                                        ),
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
                const SizedBox(height: 18),

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
      width: 88,
      height: 88,
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
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          const Text(
            'Score',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white60,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(IconData icon, String label, Color color) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  size: 21,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Ringkasan Gemini AI',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (triggers != null) ...[
            const SizedBox(height: 12),
            _buildAutomationTriggerRow(triggers),
          ],
          if (_aiResponse != null) ...[
            const SizedBox(height: 12),
            _buildXaiVisualizationPanel(_aiResponse!),
            const SizedBox(height: 12),
            _buildPumpRecommendationPanel(_aiResponse!),
          ],
          if (_lastAgronomicInput != null) ...[
            const SizedBox(height: 10),
            _buildAgronomicInputInfoBox(_lastAgronomicInput!),
          ],
          if (_lastAutomationResult != null) ...[
            const SizedBox(height: 10),
            _buildAutomationResult(_lastAutomationResult!),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _isRequesting || _isApplyingAutomation || _isAddingSchedule
                      ? null
                      : _promptAndRequestAiRecommendation,
              icon: _isRequesting || _isApplyingAutomation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                _isRequesting ? 'Menganalisis...' : 'Minta Rekomendasi AI',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
              ? 'Pompa A (N) : Direkomendasikan'
              : 'Nitrogen (N): Cukup',
          triggers.activateNitrogenPump,
        ),
        _buildTriggerChip(
          Icons.grass_rounded,
          triggers.activatePhosphorusPump
              ? 'Pompa B (P) : Direkomendasikan'
              : 'Fosfor (P): Cukup',
          triggers.activatePhosphorusPump,
        ),
        _buildTriggerChip(
          Icons.local_florist_rounded,
          triggers.activatePotassiumPump
              ? 'Pompa C (K) : Direkomendasikan'
              : 'Kalium (K): Cukup',
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

  Widget _buildAgronomicInputInfoBox(AiRecommendationAgronomicInput input) {
    final analysisLabel = _formatAnalysisWindowLabel(input.analysisWindow);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.straighten_rounded,
            size: 16,
            color: AppTheme.primaryBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${input.plantType.label} • Analisis $analysisLabel • Area sensor 100 cm² • N/P/K ${_formatLandArea(input.fertilizerConcentration.nitrogenMgPerLiter)}/${_formatLandArea(input.fertilizerConcentration.phosphorusMgPerLiter)}/${_formatLandArea(input.fertilizerConcentration.potassiumMgPerLiter)} mg/L • ${input.plantingMedium.label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXaiVisualizationPanel(AiRecommendationResponse response) {
    final items = _buildXaiContributionItems(response);
    final hasPumpCorrection = items.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  size: 17,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Visualisasi XAI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _buildXaiMethodPill('Post-Hoc'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasPumpCorrection
                ? 'Kontribusi dihitung dari besar defisit sensor terhadap ambang minimum pada rentang timestamp terpilih. Skor ini menjelaskan keputusan lokal untuk rekomendasi saat ini.'
                : 'Tidak ada koreksi pompa yang dominan pada rentang timestamp terpilih. Penjelasan lokal tetap diturunkan dari skor kesehatan tanaman dan status ambang sensor.',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (hasPumpCorrection)
            _buildXaiBeeswarmPlot(items)
          else
            _buildNoXaiCorrectionRow(response),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildXaiMethodPill('Local Explainable'),
              _buildXaiMethodPill('SHAP-style Contribution'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildXaiBeeswarmPlot(List<_XaiContributionItem> items) {
    final plotHeight = (items.length * 34.0 + 82).clamp(190.0, 290.0);

    return Container(
      width: double.infinity,
      height: plotHeight,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.14)),
      ),
      child: CustomPaint(
        painter: _XaiBeeswarmPainter(items),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildNoXaiCorrectionRow(AiRecommendationResponse response) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.statusNormal,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Skor kesehatan ${response.plantHealthPercentage}%. Tidak ada defisit N/P/K atau kelembapan yang membutuhkan durasi pompa.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXaiMethodPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.primaryBlue,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<_XaiContributionItem> _buildXaiContributionItems(
    AiRecommendationResponse response,
  ) {
    final recommendations = response.pumpRecommendations;
    if (recommendations.isEmpty) return const [];

    final normalizedScores = recommendations
        .map((item) {
          final score = _xaiRawScore(item);
          return score > 0 ? score : item.recommendedSeconds.toDouble();
        })
        .where((score) => score > 0)
        .toList(growable: false);
    final totalScore = normalizedScores.isEmpty
        ? 0.0
        : normalizedScores.reduce((a, b) => a + b);
    if (totalScore <= 0) return const [];

    final items = recommendations.map((item) {
      final score = _xaiRawScore(item);
      final normalizedScore =
          score > 0 ? score : item.recommendedSeconds.toDouble();
      return _XaiContributionItem(
        label: _xaiContributionLabel(item),
        detail: _xaiContributionDetail(item),
        score: normalizedScore,
        share: normalizedScore / totalScore,
        featureValueRatio: _xaiFeatureValueRatio(item),
        color: _xaiContributionColor(item),
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return items;
  }

  double _xaiRawScore(PumpFertilizationRecommendation item) {
    final deficitPercent = item.deficitPercent.abs();
    if (deficitPercent > 0) return deficitPercent;
    final target = item.targetMinimum.abs();
    if (target > 0) return (item.deficit.abs() / target) * 100;
    return item.recommendedSeconds.toDouble();
  }

  String _xaiContributionDetail(PumpFertilizationRecommendation item) {
    final current = _formatLandArea(item.currentValue);
    final target = _formatLandArea(item.targetMinimum);
    final seconds = _clampCustomPumpDuration(item.recommendedSeconds);
    final context = _xaiContributionContext(item);

    if (context.contains('suhu') ||
        context.contains('temperature') ||
        context.contains('temp')) {
      return 'Nilai $current ${item.unit} > batas $target ${item.unit}; durasi $seconds detik.';
    }

    return 'Nilai $current ${item.unit} < target $target ${item.unit}; durasi $seconds detik.';
  }

  double _xaiFeatureValueRatio(PumpFertilizationRecommendation item) {
    final target = item.targetMinimum.abs();
    if (target <= 0) return 0.5;
    return (item.currentValue / target).clamp(0.0, 1.4) / 1.4;
  }

  String _xaiContributionLabel(PumpFertilizationRecommendation item) {
    final context = _xaiContributionContext(item);
    if (context.contains('suhu') ||
        context.contains('temperature') ||
        context.contains('temp')) {
      return 'Suhu Tinggi (Penyiraman)';
    }
    if (context.contains('ec') &&
        (context.contains('nitrogen') || context.contains('stok n'))) {
      return 'N (EC Rendah)';
    }
    if (context.contains('nitrogen')) return 'Tren Nitrogen (N)';
    if (context.contains('fosfor') || context.contains('phosphorus')) {
      return context.contains('ec') ? 'P (EC Rendah)' : 'Tren Fosfor (P)';
    }
    if (context.contains('kalium') || context.contains('potassium')) {
      return context.contains('ec') ? 'K (EC Rendah)' : 'Tren Kalium (K)';
    }
    if (context.contains('air') ||
        context.contains('water') ||
        context.contains('moisture') ||
        context.contains('kelembapan')) {
      return 'Defisit Kelembapan';
    }
    return 'Defisit ${item.nutrient}';
  }

  Color _xaiContributionColor(PumpFertilizationRecommendation item) {
    final context = _xaiContributionContext(item);
    if (context.contains('suhu') ||
        context.contains('temperature') ||
        context.contains('temp')) {
      return AppTheme.statusLow;
    }
    if (context.contains('nitrogen')) return AppTheme.primaryGreen;
    if (context.contains('fosfor') || context.contains('phosphorus')) {
      return AppTheme.primaryBlue;
    }
    if (context.contains('kalium') || context.contains('potassium')) {
      return AppTheme.statusHigh;
    }
    if (context.contains('air') ||
        context.contains('water') ||
        context.contains('moisture') ||
        context.contains('kelembapan')) {
      return AppTheme.lightBlue;
    }
    return AppTheme.textSecondary;
  }

  String _xaiContributionContext(PumpFertilizationRecommendation item) {
    return '${item.nutrient} ${item.pumpName} ${item.reason}'.toLowerCase();
  }

  Widget _buildPumpRecommendationTile(
      PumpFertilizationRecommendation recommendation,
      {VoidCallback? onDurationChanged}) {
    final seconds = _clampCustomPumpDuration(
      _adjustedPumpSeconds[recommendation.relay] ??
          recommendation.recommendedSeconds,
    );
    final flowRate = recommendation.averageFlowRateMlPerSecond;
    final estimatedVolumeMl = flowRate * seconds;
    final sliderMax = _durationSliderMax(seconds);
    final doseWarning = _pumpDoseWarningText(recommendation);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.12)),
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
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$seconds detik',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${recommendation.reason} Defisit ${recommendation.formattedDeficitPercent}.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFlowInfoChip(
                icon: Icons.speed_rounded,
                label:
                    'Debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik',
              ),
              _buildFlowInfoChip(
                icon: Icons.water_drop_rounded,
                label:
                    'Estimasi ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml',
              ),
            ],
          ),
          if (doseWarning != null) ...[
            const SizedBox(height: 8),
            _buildPumpDoseWarning(doseWarning),
          ],
          const SizedBox(height: 6),
          Slider(
            value: seconds.toDouble(),
            min: 1,
            max: sliderMax.toDouble(),
            divisions: sliderMax - 1,
            label: '$seconds detik',
            activeColor: AppTheme.primaryGreen,
            onChanged: (value) {
              setState(() {
                _adjustedPumpSeconds[recommendation.relay] =
                    _clampCustomPumpDuration(value.round());
              });
              onDurationChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  String? _pumpDoseWarningText(
    PumpFertilizationRecommendation recommendation,
  ) {
    final isFertilizerPump =
        recommendation.relay >= 1 && recommendation.relay <= 3;
    if (!isFertilizerPump) return null;

    final reason = recommendation.reason.toLowerCase();
    final recommendedSeconds = recommendation.recommendedSeconds;
    if (reason.contains('larutan sangat pekat') || recommendedSeconds <= 1) {
      return 'Peringatan dosis: larutan sangat pekat, rekomendasi dikunci ke durasi minimum aman 1 detik.';
    }
    if (reason.contains('larutan sangat encer') ||
        recommendedSeconds >= _maxCustomPumpDurationSeconds) {
      return 'Peringatan dosis: larutan sangat encer, rekomendasi mencapai batas aman $_maxCustomPumpDurationSeconds detik. Lakukan koreksi bertahap dan ukur ulang EC/pH.';
    }
    return null;
  }

  Widget _buildPumpDoseWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.statusHigh.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.statusHigh.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppTheme.statusHigh,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _durationSliderMax(int seconds) {
    return _maxCustomPumpDurationSeconds;
  }

  Widget _buildFlowInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryGreen),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
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
          fontSize: 13,
          color: AppTheme.textSecondary,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
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

class _LandAreaInputDialog extends StatefulWidget {
  const _LandAreaInputDialog({
    required this.initialInput,
    required this.formatLandArea,
    required this.parseLandAreaNumber,
  });

  final AiRecommendationAgronomicInput? initialInput;
  final String Function(double value) formatLandArea;
  final double? Function(String input) parseLandAreaNumber;

  @override
  State<_LandAreaInputDialog> createState() => _LandAreaInputDialogState();
}

const double _fixedAiRecommendationAreaSquareMeters = 0.01;

class _LandAreaInputDialogState extends State<_LandAreaInputDialog> {
  late final TextEditingController _nitrogenController;
  late final TextEditingController _phosphorusController;
  late final TextEditingController _potassiumController;
  late final TextEditingController _customPlantTypeController;
  late final TextEditingController _customMediumController;
  late final TextEditingController _customDepthController;
  late final TextEditingController _customBulkDensityController;
  late PlantTypeProfile _selectedPlantType;
  late PlantingMediumProfile _selectedMedium;
  late AiAnalysisWindowProfile _selectedAnalysisWindow;
  late DateTime _customAnalysisStartAt;
  late DateTime _customAnalysisEndAt;
  late bool _manualCustomMediumProfile;
  String? _fertilizerErrorText;
  String? _customAnalysisWindowErrorText;
  String? _customPlantTypeErrorText;
  String? _customMediumErrorText;
  String? _customMediumProfileErrorText;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialInput;
    final initialConcentration = initial?.fertilizerConcentration ??
        const FertilizerSolutionConcentration(
          nitrogenMgPerLiter: 100,
          phosphorusMgPerLiter: 100,
          potassiumMgPerLiter: 100,
        );
    _selectedPlantType = _initialPlantType(initial?.plantType);
    _selectedMedium = _initialMedium(initial?.plantingMedium);
    _selectedAnalysisWindow = _initialAnalysisWindow(initial?.analysisWindow);
    final initialCustomEnd = initial?.analysisWindow.customEndAt;
    final customEnd = initialCustomEnd ?? DateTime.now();
    _customAnalysisEndAt = customEnd;
    _customAnalysisStartAt = initial?.analysisWindow.customStartAt ??
        customEnd.subtract(const Duration(hours: 12));
    _manualCustomMediumProfile =
        _hasManualCustomMediumProfile(initial?.plantingMedium);
    _nitrogenController = TextEditingController(
      text: widget.formatLandArea(initialConcentration.nitrogenMgPerLiter),
    );
    _phosphorusController = TextEditingController(
      text: widget.formatLandArea(initialConcentration.phosphorusMgPerLiter),
    );
    _potassiumController = TextEditingController(
      text: widget.formatLandArea(initialConcentration.potassiumMgPerLiter),
    );
    _customPlantTypeController = TextEditingController(
      text: _selectedPlantType.id == customPlantTypeProfile.id
          ? initial?.plantType.label ?? ''
          : '',
    );
    _customMediumController = TextEditingController(
      text: _selectedMedium.id == customPlantingMediumProfile.id
          ? initial?.plantingMedium.label ?? ''
          : '',
    );
    _customDepthController = TextEditingController(
      text: widget.formatLandArea(
        initial?.plantingMedium.assumedDepthCm ??
            customPlantingMediumProfile.assumedDepthCm,
      ),
    );
    _customBulkDensityController = TextEditingController(
      text: widget.formatLandArea(
        initial?.plantingMedium.bulkDensityKgPerM3 ??
            customPlantingMediumProfile.bulkDensityKgPerM3,
      ),
    );
  }

  @override
  void dispose() {
    _nitrogenController.dispose();
    _phosphorusController.dispose();
    _potassiumController.dispose();
    _customPlantTypeController.dispose();
    _customMediumController.dispose();
    _customDepthController.dispose();
    _customBulkDensityController.dispose();
    super.dispose();
  }

  PlantTypeProfile _initialPlantType(PlantTypeProfile? initial) {
    if (initial == null) return plantTypeProfiles.first;
    return plantTypeProfiles.firstWhere(
      (profile) => profile.id == initial.id,
      orElse: () => customPlantTypeProfile,
    );
  }

  PlantingMediumProfile _initialMedium(PlantingMediumProfile? initial) {
    if (initial == null) return plantingMediumProfiles[1];
    return plantingMediumProfiles.firstWhere(
      (profile) => profile.id == initial.id,
      orElse: () => customPlantingMediumProfile,
    );
  }

  AiAnalysisWindowProfile _initialAnalysisWindow(
    AiAnalysisWindowProfile? initial,
  ) {
    if (initial == null) return defaultAnalysisWindowProfile;
    if (initial.isCustom) return initial;
    return analysisWindowProfiles.firstWhere(
      (profile) => profile.id == initial.id && !profile.isCustom,
      orElse: () => defaultAnalysisWindowProfile,
    );
  }

  bool get _usesCustomPlantType =>
      _selectedPlantType.id == customPlantTypeProfile.id;

  bool get _usesCustomMedium =>
      _selectedMedium.id == customPlantingMediumProfile.id;

  bool get _usesCustomAnalysisWindow => _selectedAnalysisWindow.isCustom;

  AiAnalysisWindowProfile get _analysisWindowDropdownValue =>
      _usesCustomAnalysisWindow
          ? customAnalysisWindowProfile
          : _selectedAnalysisWindow;

  bool _hasManualCustomMediumProfile(PlantingMediumProfile? initial) {
    if (initial == null || !initial.id.startsWith('custom_medium_')) {
      return false;
    }

    return (initial.assumedDepthCm - customPlantingMediumProfile.assumedDepthCm)
                .abs() >
            0.0001 ||
        (initial.bulkDensityKgPerM3 -
                    customPlantingMediumProfile.bulkDensityKgPerM3)
                .abs() >
            0.0001;
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  void _confirm() {
    final nitrogen = _parseNonNegativeNumber(_nitrogenController.text);
    final phosphorus = _parseNonNegativeNumber(_phosphorusController.text);
    final potassium = _parseNonNegativeNumber(_potassiumController.text);
    if (nitrogen == null ||
        phosphorus == null ||
        potassium == null ||
        nitrogen < 0 ||
        phosphorus < 0 ||
        potassium < 0 ||
        (nitrogen == 0 && phosphorus == 0 && potassium == 0)) {
      setState(() {
        _fertilizerErrorText =
            'Isi minimal satu konsentrasi larutan pupuk lebih dari 0 mg/L.';
      });
      return;
    }

    final plantType = _buildSelectedPlantType();
    final medium = _buildSelectedMedium();
    if (plantType == null || medium == null) return;
    final analysisWindow = _buildSelectedAnalysisWindow();
    if (analysisWindow == null) return;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      AiRecommendationAgronomicInput(
        plantType: plantType,
        landAreaSquareMeters: _fixedAiRecommendationAreaSquareMeters,
        fertilizerConcentration: FertilizerSolutionConcentration(
          nitrogenMgPerLiter: nitrogen,
          phosphorusMgPerLiter: phosphorus,
          potassiumMgPerLiter: potassium,
        ),
        plantingMedium: medium,
        analysisWindow: analysisWindow,
      ),
    );
  }

  AiAnalysisWindowProfile? _buildSelectedAnalysisWindow() {
    if (!_usesCustomAnalysisWindow) return _selectedAnalysisWindow;

    final start = DateTime(
      _customAnalysisStartAt.year,
      _customAnalysisStartAt.month,
      _customAnalysisStartAt.day,
      _customAnalysisStartAt.hour,
      _customAnalysisStartAt.minute,
    );
    final end = DateTime(
      _customAnalysisEndAt.year,
      _customAnalysisEndAt.month,
      _customAnalysisEndAt.day,
      _customAnalysisEndAt.hour,
      _customAnalysisEndAt.minute,
      59,
      999,
    );

    if (!end.isAfter(start)) {
      setState(() {
        _customAnalysisWindowErrorText =
            'Waktu akhir harus setelah waktu mulai.';
      });
      return null;
    }

    return AiAnalysisWindowProfile.customRange(
      startAt: start,
      endAt: end,
    );
  }

  PlantTypeProfile? _buildSelectedPlantType() {
    if (!_usesCustomPlantType) return _selectedPlantType;

    final label = _normalizedText(_customPlantTypeController.text);
    if (label.isEmpty) {
      setState(() {
        _customPlantTypeErrorText = 'Masukkan nama jenis tanaman.';
      });
      return null;
    }

    return PlantTypeProfile(
      id: _customProfileId('custom_plant', label),
      label: label,
      scientificName: 'Tanaman kustom',
      contextNote:
          'Tanaman ini dimasukkan manual oleh pengguna. NutriXense akan menyesuaikan rekomendasi dari data sensor dan media tanam yang Anda masukkan.',
      thresholds: customPlantTypeProfile.thresholds,
    );
  }

  PlantingMediumProfile? _buildSelectedMedium() {
    if (!_usesCustomMedium) return _selectedMedium;

    final label = _normalizedText(_customMediumController.text);
    if (label.isEmpty) {
      setState(() {
        _customMediumErrorText = 'Masukkan nama media tanam.';
      });
      return null;
    }

    var depth = customPlantingMediumProfile.assumedDepthCm;
    var bulkDensity = customPlantingMediumProfile.bulkDensityKgPerM3;
    if (_manualCustomMediumProfile) {
      final manualDepth = _parsePositiveNumber(_customDepthController.text);
      final manualBulkDensity =
          _parsePositiveNumber(_customBulkDensityController.text);
      if (manualDepth == null ||
          manualBulkDensity == null ||
          manualDepth < 1 ||
          manualDepth > 50 ||
          manualBulkDensity < 100 ||
          manualBulkDensity > 2000) {
        setState(() {
          _customMediumProfileErrorText =
              'Isi kedalaman 1-50 cm dan bulk density 100-2000 kg/m3.';
        });
        return null;
      }

      depth = manualDepth;
      bulkDensity = manualBulkDensity;
    }

    if (depth < 1 || depth > 50 || bulkDensity < 100 || bulkDensity > 2000) {
      setState(() {
        _customMediumProfileErrorText =
            'Isi kedalaman 1-50 cm dan bulk density 100-2000 kg/m3.';
      });
      return null;
    }

    return PlantingMediumProfile(
      id: _customProfileId('custom_medium', label),
      label: label,
      assumedDepthCm: depth,
      bulkDensityKgPerM3: bulkDensity,
      note: _manualCustomMediumProfile
          ? 'Media tanam ini dimasukkan manual oleh pengguna. NutriXense memakai kedalaman dan bulk density yang Anda masukkan sebagai input perhitungan terkontrol.'
          : 'Media tanam ini dimasukkan manual oleh pengguna. NutriXense memakai asumsi standar kedalaman 20 cm dan bulk density 900 kg/m3.',
    );
  }

  String _normalizedText(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _customProfileId(String prefix, String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? prefix : '${prefix}_$slug';
  }

  double? _parsePositiveNumber(String input) {
    final parsed = widget.parseLandAreaNumber(input);
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  double? _parseNonNegativeNumber(String input) {
    final parsed = widget.parseLandAreaNumber(input);
    return parsed == null || parsed < 0 ? null : parsed;
  }

  double get _displayDepthCm {
    if (!_usesCustomMedium) return _selectedMedium.assumedDepthCm;
    if (!_manualCustomMediumProfile) {
      return customPlantingMediumProfile.assumedDepthCm;
    }
    return _parsePositiveNumber(_customDepthController.text) ??
        customPlantingMediumProfile.assumedDepthCm;
  }

  double get _displayBulkDensityKgPerM3 {
    if (!_usesCustomMedium) return _selectedMedium.bulkDensityKgPerM3;
    if (!_manualCustomMediumProfile) {
      return customPlantingMediumProfile.bulkDensityKgPerM3;
    }
    return _parsePositiveNumber(_customBulkDensityController.text) ??
        customPlantingMediumProfile.bulkDensityKgPerM3;
  }

  String get _displayMediumNote {
    if (!_usesCustomMedium) return _selectedMedium.note;
    if (_manualCustomMediumProfile) {
      return 'Nilai kedalaman dan bulk density mengikuti input manual.';
    }
    return 'Jika tidak tahu, biarkan otomatis memakai asumsi standar.';
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      filled: true,
      fillColor: AppTheme.bgPrimary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppTheme.primaryGreen.withOpacity(0.22),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppTheme.primaryGreen,
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
    );
  }

  Widget _buildConcentrationField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDecoration(label: '$label mg/L', hint: '100'),
      onChanged: (_) {
        if (_fertilizerErrorText == null) return;
        setState(() => _fertilizerErrorText = null);
      },
    );
  }

  Widget _buildFixedAreaInfoBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.crop_free_rounded,
            size: 18,
            color: AppTheme.primaryGreen,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Area rekomendasi dikunci 100 cm² atau 0,01 m² sesuai area efektif sensor. Nilai N, P, dan K dipakai sebagai tren estimasi, sedangkan dosis nutrisi divalidasi terutama dari EC dan batas aman pompa kecil.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomAnalysisDate({required bool isStart}) async {
    final current = isStart ? _customAnalysisStartAt : _customAnalysisEndAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;

    _setCustomAnalysisDateTime(
      isStart: isStart,
      value: DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      ),
    );
  }

  Future<void> _pickCustomAnalysisTime({required bool isStart}) async {
    final current = isStart ? _customAnalysisStartAt : _customAnalysisEndAt;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;

    _setCustomAnalysisDateTime(
      isStart: isStart,
      value: DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  void _setCustomAnalysisDateTime({
    required bool isStart,
    required DateTime value,
  }) {
    setState(() {
      _customAnalysisWindowErrorText = null;
      if (isStart) {
        _customAnalysisStartAt = value;
        if (!_customAnalysisEndAt.isAfter(_customAnalysisStartAt)) {
          _customAnalysisEndAt =
              _customAnalysisStartAt.add(const Duration(hours: 1));
        }
        return;
      }

      _customAnalysisEndAt = value;
      if (!_customAnalysisEndAt.isAfter(_customAnalysisStartAt)) {
        _customAnalysisStartAt =
            _customAnalysisEndAt.subtract(const Duration(hours: 1));
      }
    });
  }

  Widget _buildCustomAnalysisRangeFields() {
    Widget dateTimeRow({
      required String label,
      required DateTime value,
      required VoidCallback onDateTap,
      required VoidCallback onTimeTap,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDateTimeButton(
                  icon: Icons.calendar_month_rounded,
                  label: DateFormat('dd/MM/yyyy').format(value),
                  onTap: onDateTap,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: _buildDateTimeButton(
                  icon: Icons.schedule_rounded,
                  label: DateFormat('HH:mm').format(value),
                  onTap: onTimeTap,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        dateTimeRow(
          label: 'Mulai',
          value: _customAnalysisStartAt,
          onDateTap: () => _pickCustomAnalysisDate(isStart: true),
          onTimeTap: () => _pickCustomAnalysisTime(isStart: true),
        ),
        const SizedBox(height: 12),
        dateTimeRow(
          label: 'Sampai',
          value: _customAnalysisEndAt,
          onDateTap: () => _pickCustomAnalysisDate(isStart: false),
          onTimeTap: () => _pickCustomAnalysisTime(isStart: false),
        ),
        if (_customAnalysisWindowErrorText != null) ...[
          const SizedBox(height: 6),
          Text(
            _customAnalysisWindowErrorText!,
            style: const TextStyle(
              color: AppTheme.statusLow,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateTimeButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.bgPrimary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.22)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryGreen),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      title: const Text(
        'Minta Rekomendasi AI',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Isi data dasar di bawah ini agar Gemini AI memberikan hasil Rekomendasi yang sesuai.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<AiAnalysisWindowProfile>(
              value: _analysisWindowDropdownValue,
              isExpanded: true,
              decoration: _inputDecoration(label: 'Rentang analisis'),
              items: analysisWindowProfiles.map((window) {
                return DropdownMenuItem<AiAnalysisWindowProfile>(
                  value: window,
                  child: Text(
                    window.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedAnalysisWindow = value.isCustom
                      ? AiAnalysisWindowProfile.customRange(
                          startAt: _customAnalysisStartAt,
                          endAt: _customAnalysisEndAt,
                        )
                      : value;
                  _customAnalysisWindowErrorText = null;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              _selectedAnalysisWindow.description,
              style: const TextStyle(
                color: AppTheme.textLight,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            if (_usesCustomAnalysisWindow) _buildCustomAnalysisRangeFields(),
            const SizedBox(height: 14),
            DropdownButtonFormField<PlantTypeProfile>(
              value: _selectedPlantType,
              isExpanded: true,
              decoration: _inputDecoration(label: 'Jenis tanaman'),
              items: plantTypeProfiles.map((plant) {
                return DropdownMenuItem<PlantTypeProfile>(
                  value: plant,
                  child: Text(
                    plant.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedPlantType = value;
                  _customPlantTypeErrorText = null;
                });
              },
            ),
            if (_usesCustomPlantType) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customPlantTypeController,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  label: 'Nama tanaman lainnya',
                  hint: 'Contoh: Pakcoy, Stroberi, Kentang',
                  errorText: _customPlantTypeErrorText,
                ),
                onChanged: (_) {
                  if (_customPlantTypeErrorText == null) return;
                  setState(() => _customPlantTypeErrorText = null);
                },
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _usesCustomPlantType
                  ? customPlantTypeProfile.contextNote
                  : '${_selectedPlantType.scientificName}. ${_selectedPlantType.contextNote}',
              style: const TextStyle(
                color: AppTheme.textLight,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _buildFixedAreaInfoBox(),
            const SizedBox(height: 16),
            const Text(
              'Konsentrasi larutan pupuk',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildConcentrationField(
                    controller: _nitrogenController,
                    label: 'N',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildConcentrationField(
                    controller: _phosphorusController,
                    label: 'P',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildConcentrationField(
                    controller: _potassiumController,
                    label: 'K',
                  ),
                ),
              ],
            ),
            if (_fertilizerErrorText != null) ...[
              const SizedBox(height: 6),
              Text(
                _fertilizerErrorText!,
                style: const TextStyle(
                  color: AppTheme.statusLow,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Biarkan 0 jika tidak menggunakan pupuk tertentu. Nilai lebih encer cenderung menambah durasi, tetapi rekomendasi tetap dibatasi oleh EC, pH, tren NPK, media, dan batas aman pompa.',
              style: TextStyle(
                color: AppTheme.textLight,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PlantingMediumProfile>(
              value: _selectedMedium,
              isExpanded: true,
              decoration: _inputDecoration(label: 'Jenis media tanam'),
              items: plantingMediumProfiles.map((medium) {
                return DropdownMenuItem<PlantingMediumProfile>(
                  value: medium,
                  child: Text(
                    medium.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedMedium = value;
                  _customMediumErrorText = null;
                  _customMediumProfileErrorText = null;
                  if (value.id != customPlantingMediumProfile.id) {
                    _manualCustomMediumProfile = false;
                  }
                });
              },
            ),
            if (_usesCustomMedium) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customMediumController,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  label: 'Nama media tanam lainnya',
                  hint: 'Contoh: Cocopeat, Rockwool, Hidroton',
                  errorText: _customMediumErrorText,
                ),
                onSubmitted: (_) => _confirm(),
                onChanged: (_) {
                  if (_customMediumErrorText == null) return;
                  setState(() => _customMediumErrorText = null);
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _manualCustomMediumProfile,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Atur manual kedalaman & kepadatan media tanam',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text(
                  'Matikan jika tidak tahu. NutriXense memakai 20 cm dan 900 kg/m3.',
                  style: TextStyle(
                    color: AppTheme.textLight,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                activeColor: AppTheme.primaryGreen,
                onChanged: (value) {
                  setState(() {
                    _manualCustomMediumProfile = value;
                    _customMediumProfileErrorText = null;
                  });
                },
              ),
              if (_manualCustomMediumProfile) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customDepthController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          label: 'Kedalaman cm',
                          hint: '20',
                        ),
                        onChanged: (_) {
                          if (_customMediumProfileErrorText == null) return;
                          setState(() => _customMediumProfileErrorText = null);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _customBulkDensityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        decoration: _inputDecoration(
                          label: 'Bulk density kg/m3',
                          hint: '900',
                        ),
                        onSubmitted: (_) => _confirm(),
                        onChanged: (_) {
                          if (_customMediumProfileErrorText == null) return;
                          setState(() => _customMediumProfileErrorText = null);
                        },
                      ),
                    ),
                  ],
                ),
                if (_customMediumProfileErrorText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _customMediumProfileErrorText!,
                    style: const TextStyle(
                      color: AppTheme.statusLow,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ],
            const SizedBox(height: 8),
            Text(
              'Asumsi: kedalaman ${widget.formatLandArea(_displayDepthCm)} cm, bulk density ${widget.formatLandArea(_displayBulkDensityKgPerM3)} kg/m3. $_displayMediumNote',
              style: const TextStyle(
                color: AppTheme.textLight,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _cancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('Konfirmasi'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
