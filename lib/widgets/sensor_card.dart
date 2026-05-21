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
    final sensorColor = Color(reading.colorHex);

    // ─── Dynamic UI based on status ─────────────────────────────
    Color borderColor;
    Color glowColor;
    Color backgroundTint;

    switch (reading.status) {
      case 'Low':
        borderColor = AppTheme.statusLow;
        glowColor = AppTheme.statusLow.withOpacity(0.005);
        backgroundTint = AppTheme.statusLow.withOpacity(0.005);
        break;

      case 'High':
        borderColor = AppTheme.statusHigh;
        glowColor = AppTheme.statusHigh.withOpacity(0.005);
        backgroundTint = AppTheme.statusHigh.withOpacity(0.005);
        break;

      default:
        borderColor = AppTheme.statusNormal;
        glowColor = AppTheme.statusNormal.withOpacity(0.005);
        backgroundTint = AppTheme.statusNormal.withOpacity(0.005);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: backgroundTint,
          borderRadius: BorderRadius.circular(22),

          // ─── Dynamic Border ───────────────────────────────
          border: Border.all(
            color: borderColor.withOpacity(0.22),
            width: 1.4,
          ),

          // ─── Dynamic Shadow / Glow ───────────────────────
          boxShadow: [
            BoxShadow(
              color: glowColor,
              blurRadius: 14,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),

            // Soft dark shadow for depth
            BoxShadow(
              color: borderColor.withOpacity(0.08),
              blurRadius: 10,
              spreadRadius: 0.2,
              offset: const Offset(0, 2),
            ),
          ],
        ),

        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header row: icon + status badge ─────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Sensor Icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: sensorColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Image.asset(
                        reading.icon,
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  // Status Badge
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

              // ─── Value display ────────────────────────────────
              Text(
                '${reading.value}',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: sensorColor,
                  height: 1.0,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                reading.unit,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 10),

              // ─── Progress bar ─────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4),

                child: LinearProgressIndicator(
                  value: reading.normalizedValue,
                  backgroundColor: sensorColor.withOpacity(0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    sensorColor,
                  ),
                  minHeight: 5.5,
                ),
              ),

              const SizedBox(height: 10),

              // ─── Label ────────────────────────────────────────
              Text(
                reading.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}