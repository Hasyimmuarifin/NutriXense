import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/control_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      )
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  // Keep screens alive when switching tabs using IndexedStack
  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    ScanScreen(),
    InsightsScreen(),
    ControlScreen(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.home_rounded),
      label: 'Home'
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      label: 'History'
    ),
    NavigationDestination(
      icon: Icon(Icons.document_scanner_outlined),
      selectedIcon: Icon(Icons.document_scanner_rounded),
      label: 'Scan'
    ),
    NavigationDestination(
      icon: Icon(Icons.lightbulb_outlined),
      selectedIcon: Icon(Icons.lightbulb_rounded),
      label: 'Insights'
    ),
    NavigationDestination(
      icon: Icon(Icons.toggle_off_outlined),
      selectedIcon: Icon(Icons.toggle_on_rounded),
      label: 'Control'
    ),
  ];

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
        destinations: _destinations.asMap().entries.map((entry) {
          final i = entry.key;
          final dest = entry.value;

          // Highlight the center Scan button differently
          if (i == 2) {
            return NavigationDestination(
              icon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppTheme.cardGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.document_scanner_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              selectedIcon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppTheme.cardGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withOpacity(0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.document_scanner_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              label: 'Scan',
            );
          }

          return dest;
        }).toList(),
      ),
    );
  }
}
