// lib/theme/app_theme.dart
// Defines the global color palette, typography, and Material 3 theme for NutriXense

import 'package:flutter/material.dart';

class AppTheme {
  // ─── Brand Colors ────────────────────────────────────────────────────────────
  static const Color primaryGreen = Color(0xFF2E7D52);
  static const Color lightGreen   = Color(0xFF4CAF7D);
  static const Color accentGreen  = Color(0xFFB2DFDB);
  static const Color primaryBlue  = Color(0xFF1565C0);
  static const Color lightBlue    = Color(0xFF42A5F5);
  static const Color accentBlue   = Color(0xFFBBDEFB);

  // ─── Status Colors ────────────────────────────────────────────────────────────
  static const Color statusLow    = Color(0xFFE53935); // red
  static const Color statusNormal = Color(0xFF43A047); // green
  static const Color statusHigh   = Color(0xFFFF8F00); // amber

  // ─── Backgrounds ──────────────────────────────────────────────────────────────
  static const Color bgPrimary    = Color(0xFFF0F7F4);
  static const Color bgCard       = Color(0xFFFFFFFF);
  static const Color bgDark       = Color(0xFF1B2E25);

  // ─── Text ─────────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A2E20);
  static const Color textSecondary = Color(0xFF5A7265);
  static const Color textLight     = Color(0xFF9DB5A5);

  // ─── Gradient ─────────────────────────────────────────────────────────────────
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B5E3B), Color(0xFF1565C0)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E7D52), Color(0xFF1976D2)],
  );

  // ─── Material 3 Theme ────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          brightness: Brightness.light,
          primary: primaryGreen,
          secondary: primaryBlue,
          surface: bgCard,
        ),
        scaffoldBackgroundColor: bgPrimary,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          foregroundColor: textPrimary,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: bgCard,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: bgCard,
          indicatorColor: accentGreen,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: primaryGreen,
              );
            }
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: textSecondary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: primaryGreen, size: 22);
            }
            return const IconThemeData(color: textSecondary, size: 22);
          }),
          elevation: 8,
          shadowColor: Colors.black26,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return primaryGreen;
            return Colors.grey.shade300;
          }),
        ),
      );
}