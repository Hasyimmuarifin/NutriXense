// lib/widgets/insight_card_widget.dart
// Reusable widget for displaying AI-generated insight/recommendation cards

import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';

class InsightCardWidget extends StatelessWidget {
  final InsightCard insight;
  final bool expanded;
  final VoidCallback? onTap;

  const InsightCardWidget({
    super.key,
    required this.insight,
    this.expanded = false,
    this.onTap,
  });

  Color get _borderColor {
    switch (insight.severity) {
      case InsightSeverity.kritis:
        return AppTheme.statusLow;
      case InsightSeverity.awas:
        return AppTheme.statusHigh;
      case InsightSeverity.baik:
        return AppTheme.statusNormal;
    }
  }

  Color get _bgColor {
    switch (insight.severity) {
      case InsightSeverity.kritis:
        return const Color(0xFFFFF5F5);
      case InsightSeverity.awas:
        return const Color(0xFFFFFBF0);
      case InsightSeverity.baik:
        return const Color(0xFFF1FBF4);
    }
  }

  String get _severityLabel {
    switch (insight.severity) {
      case InsightSeverity.kritis:
        return 'ACTION REQUIRED';
      case InsightSeverity.awas:
        return 'MONITOR';
      case InsightSeverity.baik:
        return 'OPTIMAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: _borderColor,
              width: 4,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: _borderColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Top row ────────────────────────────────────────────────────
              Row(
                children: [
                  Text(insight.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Severity badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _borderColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _severityLabel,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _borderColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          insight.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textLight,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ─── Description ─────────────────────────────────────────────────
              Text(
                insight.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),

              // ─── Action (expanded) ───────────────────────────────────────────
              if (expanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _buildExpandedInfoRow(
                  icon: Icons.psychology_alt_rounded,
                  label: 'Alasan AI',
                  text: insight.action,
                ),
                if (insight.recommendation.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildExpandedInfoRow(
                    icon: Icons.agriculture_rounded,
                    label: 'Tindak Lanjut',
                    text: insight.recommendation,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedInfoRow({
    required IconData icon,
    required String label,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 15,
          color: _borderColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: _borderColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: _borderColor,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
