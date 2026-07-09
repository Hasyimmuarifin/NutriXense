import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';

import 'theme/app_theme.dart';

import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/control_screen.dart';
import 'screens/logs_screen.dart';
import 'services/fcm_notification_service.dart';
import 'services/log_alert_badge_service.dart';
import 'services/nutrient_alert_service.dart';
import 'services/rule_based_pump_automation_service.dart';
import 'services/threshold_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<void> _startupFuture;

  @override
  void initState() {
    super.initState();
    _startupFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Future.wait([
      _bootstrapServices(),
      Future<void>.delayed(const Duration(seconds: 3)),
    ]);
  }

  Future<void> _bootstrapServices() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 20));

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    await ThresholdConfigService.instance
        .load()
        .timeout(const Duration(seconds: 5));

    unawaited(
      LogAlertBadgeService.instance
          .initialize()
          .timeout(const Duration(seconds: 8))
          .catchError((error) {
        debugPrint('Log alert badge startup skipped: $error');
      }),
    );

    unawaited(
      NutrientAlertService.instance
          .initialize()
          .timeout(const Duration(seconds: 8))
          .catchError((error) {
        debugPrint('Alert service startup skipped: $error');
      }),
    );

    await FcmNotificationService.instance
        .initialize()
        .timeout(const Duration(seconds: 15))
        .catchError((error) {
      debugPrint('FCM service startup skipped: $error');
    });
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriXense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: FutureBuilder<void>(
        future: _startupFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return const MainNavigation();
          }

          if (snapshot.hasError) {
            return _StartupErrorScreen(
              onRetry: () {
                setState(() {
                  _startupFuture = _initializeApp();
                });
              },
            );
          }

          return const SplashScreen();
        },
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/nutrixense.png', width: 110),
                const SizedBox(height: 20),
                const Text(
                  'Aplikasi belum siap dibuka',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Periksa koneksi internet lalu coba lagi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Coba Lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  final RuleBasedPumpAutomationService _ruleBasedPumpAutomationService =
      RuleBasedPumpAutomationService.instance;

  // Keep screens alive when switching tabs using IndexedStack
  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    InsightsScreen(),
    ControlScreen(),
    LogsScreen(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
    NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined), label: 'History'),
    NavigationDestination(
        icon: Icon(Icons.lightbulb_outlined),
        selectedIcon: Icon(Icons.lightbulb_rounded),
        label: 'Insights'),
    NavigationDestination(
        icon: Icon(Icons.toggle_off_outlined),
        selectedIcon: Icon(Icons.toggle_on_rounded),
        label: 'Control'),
    NavigationDestination(
        icon: _LogAlertBadgeIcon(icon: Icons.receipt_long_outlined),
        selectedIcon: _LogAlertBadgeIcon(icon: Icons.receipt_long_rounded),
        label: 'Logs'),
  ];

  @override
  void initState() {
    super.initState();
    _restoreRuleBasedAutomation();
  }

  Future<void> _restoreRuleBasedAutomation() async {
    final enabled =
        await _ruleBasedPumpAutomationService.loadEnabledPreference();
    if (enabled) {
      await _ruleBasedPumpAutomationService.start(persist: false);
    }
  }

  @override
  void dispose() {
    _ruleBasedPumpAutomationService.stopInAppChecks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps all screens in memory, preserving scroll state
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      // ─── Bottom Navigation Bar ────────────────────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // Add haptic feedback for a tactile feel
          HapticFeedback.lightImpact();
          setState(() => _currentIndex = index);
        },
        animationDuration: const Duration(milliseconds: 400),
        destinations: _destinations,
      ),
    );
  }
}

class _LogAlertBadgeIcon extends StatelessWidget {
  const _LogAlertBadgeIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LogAlertBadgeService.instance.unreadLogCount,
      builder: (context, unreadLogCount, _) {
        if (unreadLogCount <= 0) return Icon(icon);

        return Badge.count(
          count: unreadLogCount,
          backgroundColor: AppTheme.statusLow,
          textColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
          child: Icon(icon),
        );
      },
    );
  }
}
