// lib/widgets/pump_card.dart
// Reusable card for individual pump toggle control

import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';

class PumpCard extends StatelessWidget {
  final PumpController pump;
  final ValueChanged<bool> onToggle;

  const PumpCard({
    super.key,
    required this.pump,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isOn = pump.isOn;
    final activeColor = isOn ? AppTheme.primaryGreen : Colors.grey.shade400;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOn
              ? AppTheme.primaryGreen.withOpacity(0.4)
              : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isOn
                ? AppTheme.primaryGreen.withOpacity(0.15)
                : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // ─── Pump icon ─────────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isOn
                    ? AppTheme.primaryGreen.withOpacity(0.12)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(pump.icon, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(width: 16),

            // ─── Name & nutrient ────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pump.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pump.nutrient,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Status indicator dot + label
                  Row(
                    children: [
                      if (pump.isLoading)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primaryGreen,
                            ),
                          ),
                        )
                      else
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOn ? AppTheme.statusNormal : Colors.grey.shade400,
                            shape: BoxShape.circle,
                            boxShadow: isOn
                                ? [
                                    BoxShadow(
                                      color: AppTheme.statusNormal.withOpacity(0.5),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      const SizedBox(width: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          pump.isLoading
                              ? 'Switching...'
                              : (isOn ? 'Running' : 'Stopped'),
                          key: ValueKey(pump.isLoading
                              ? 'loading'
                              : (isOn ? 'on' : 'off')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: pump.isLoading
                                ? AppTheme.textLight
                                : activeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ─── Toggle switch ──────────────────────────────────────────────────
            pump.isLoading
                ? const SizedBox(
                    width: 51,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryGreen,
                          ),
                        ),
                      ),
                    ),
                  )
                : Switch(
                    value: isOn,
                    onChanged: pump.isLoading ? null : onToggle,
                  ),
          ],
        ),
      ),
    );
  }
}