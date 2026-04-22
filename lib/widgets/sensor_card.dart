// lib/widgets/sensor_card.dart
// Reusable card widget that displays a single sensor reading with status indicator

import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';

class SensorCard extends StatelessWidget {
  final SensorReading reading;
  final VoidCallback? onTap;

  const SensorCard({
    super.key,
    required this.reading,
    this.onTap,
  });

  Color get _statusColor {
    switch (reading.status) {
      case 'Low':
        return AppTheme.statusLow;
      case 'High':
        return AppTheme.statusHigh;
      default:
        return AppTheme.statusNormal;
    }
  }

  IconData get _statusIcon {
    switch (reading.status) {
      case 'Low':
        return Icons.arrow_downward_rounded;
      case 'High':
        return Icons.arrow_upward_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Color(reading.colorHex).withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header row: icon + status badge ────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(reading.colorHex).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        reading.icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _statusIcon,
                          size: 11,
                          color: _statusColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          reading.status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _statusColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // ─── Value display ───────────────────────────────────────────────
              Text(
                '${reading.value}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(reading.colorHex),
                  height: 1.0,
                ),
              ),
              Text(
                reading.unit,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),

              // ─── Progress bar ────────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: reading.normalizedValue,
                  backgroundColor: Color(reading.colorHex).withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(reading.colorHex),
                  ),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 8),

              // ─── Label ───────────────────────────────────────────────────────
              Text(
                reading.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}