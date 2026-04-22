import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> 
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    )..repeat(reverse: true); // bolak-balik (denyut)

    _animation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // LOGO DENGAN ANIMASI DENYUT
          Center(
            child: ScaleTransition(
              scale: _animation,
              child: Image.asset(
                'assets/images/nutrixense.png',
                width: 140,
              ),
            ),
          ),

          // TEXT DI BAGIAN BAWAH
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 30),
              child: Text(
                "Integrated Plant Nutrition Monitoring and Controlling Application",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'AROneSans', // pastikan sudah didaftarkan di pubspec.yaml
                  color: Color(0xFF64C7D5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}