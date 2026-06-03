import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

import 'theme/app_theme.dart';

import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/control_screen.dart';
import 'services/rule_based_pump_automation_service.dart';
import 'services/threshold_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  await ThresholdConfigService.instance.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'NutriXense',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: FutureBuilder(
          future: Future.delayed(Duration(seconds: 3)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return MainNavigation(); // halaman utama
            }
            return SplashScreen();
          },
        ));
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
  ];

  @override
  void initState() {
    super.initState();
    _ruleBasedPumpAutomationService.start();
  }

  @override
  void dispose() {
    _ruleBasedPumpAutomationService.stop();
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
