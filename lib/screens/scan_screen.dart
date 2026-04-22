// lib/screens/scan_screen.dart
// AI plant scan page – simulates camera capture and shows dummy AI analysis result

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with TickerProviderStateMixin {
  bool _scanning = false;
  bool _scanned = false;
  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  late Animation<double> _pulseAnim;
  late Animation<double> _scanLineAnim;

  // Dummy AI scan result
  final Map<String, dynamic> _scanResult = {
    'status': 'Moderate Stress',
    'isHealthy': false,
    'confidence': '87%',
    'plantType': 'Tomato (Solanum lycopersicum)',
    'issues': [
      {'label': 'Nitrogen Deficiency', 'severity': 'High', 'color': 0xFFE53935},
      {'label': 'Slight Acidic Soil', 'severity': 'Medium', 'color': 0xFFFF8F00},
      {'label': 'Potassium Excess', 'severity': 'Low', 'color': 0xFFFDD835},
    ],
    'recommendations': [
      'Apply nitrogen-rich fertilizer within 24 hours',
      'Add lime to raise soil pH to 6.0–7.5 range',
      'Reduce potassium dosage until levels normalize',
      'Increase irrigation to flush excess potassium',
    ],
    'overallScore': 62,
  };

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scanLineAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scanned = false;
    });

    // Simulate scanning animation
    _scanLineController.reset();
    _scanLineController.forward();

    await Future.delayed(const Duration(milliseconds: 2200));

    if (mounted) {
      setState(() {
        _scanning = false;
        _scanned = true;
      });
    }
  }

  void _reset() {
    setState(() {
      _scanned = false;
      _scanning = false;
    });
    _scanLineController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: _scanned ? _buildResult() : _buildCameraView(),
      ),
    );
  }

  // ─── Camera View ─────────────────────────────────────────────────────────────
  Widget _buildCameraView() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Plant Scan',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Point camera at plant leaves',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 14, color: AppTheme.primaryGreen),
                    const SizedBox(width: 5),
                    const Text(
                      'AI Powered',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ─── Camera viewfinder simulation ──────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Stack(
                children: [
                  // Dark placeholder for camera
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2A1E),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          // Simulated plant image (gradient placeholder)
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF1A3A24),
                                  Color(0xFF0D2016),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '🌿',
                                    style: TextStyle(fontSize: 80),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Plant preview area',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Corner brackets
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ScannerBracketPainter(
                                color: AppTheme.lightGreen,
                              ),
                            ),
                          ),

                          // Scan line animation
                          if (_scanning)
                            AnimatedBuilder(
                              animation: _scanLineAnim,
                              builder: (context, _) {
                                return Positioned(
                                  top: _scanLineAnim.value *
                                      (MediaQuery.of(context).size.height * 0.45),
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          AppTheme.lightGreen.withOpacity(0.8),
                                          AppTheme.lightGreen,
                                          AppTheme.lightGreen.withOpacity(0.8),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                          // Scanning status overlay
                          if (_scanning)
                            Positioned(
                              bottom: 20,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Analyzing plant...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
        const SizedBox(height: 32),

        // ─── Scan button ────────────────────────────────────────────────────
        if (!_scanning) ...[
          GestureDetector(
            onTap: _startScan,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.lightGreen, AppTheme.primaryBlue],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.document_scanner_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tap to scan',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ] else
          const SizedBox(height: 88),

        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Scan Result View ─────────────────────────────────────────────────────────
  Widget _buildResult() {
    final result = _scanResult;
    final isHealthy = result['isHealthy'] as bool;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Result header ────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Scan Results',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Rescan'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── Health status card ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isHealthy
                    ? [const Color(0xFF1B5E3B), const Color(0xFF2E7D52)]
                    : [const Color(0xFF7B1A1A), const Color(0xFFB71C1C)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                // Health score circle
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${result['overallScore']}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      const Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white60,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result['status'] as String,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result['plantType'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.75),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.analytics_rounded,
                              size: 13, color: Colors.white60),
                          const SizedBox(width: 4),
                          Text(
                            'Confidence: ${result['confidence']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
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
          const SizedBox(height: 16),

          // ─── Issues detected ──────────────────────────────────────────────
          const Text(
            'Issues Detected',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...(result['issues'] as List<Map<String, dynamic>>).map((issue) {
            final color = Color(issue['color'] as int);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      issue['label'] as String,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      issue['severity'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),

          // ─── Recommendations ──────────────────────────────────────────────
          const Text(
            'Recommended Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children:
                  (result['recommendations'] as List<String>)
                      .asMap()
                      .entries
                      .map((e) => Padding(
                            padding: EdgeInsets.only(
                                bottom: e.key <
                                        (result['recommendations'] as List)
                                                .length -
                                            1
                                    ? 12
                                    : 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${e.key + 1}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Custom painter for scanner corner brackets ───────────────────────────────
class _ScannerBracketPainter extends CustomPainter {
  final Color color;
  _ScannerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const margin = 20.0;

    // Top-left
    canvas.drawLine(
        Offset(margin, margin + len), Offset(margin, margin), paint);
    canvas.drawLine(
        Offset(margin, margin), Offset(margin + len, margin), paint);

    // Top-right
    canvas.drawLine(Offset(size.width - margin - len, margin),
        Offset(size.width - margin, margin), paint);
    canvas.drawLine(Offset(size.width - margin, margin),
        Offset(size.width - margin, margin + len), paint);

    // Bottom-left
    canvas.drawLine(Offset(margin, size.height - margin - len),
        Offset(margin, size.height - margin), paint);
    canvas.drawLine(Offset(margin, size.height - margin),
        Offset(margin + len, size.height - margin), paint);

    // Bottom-right
    canvas.drawLine(
        Offset(size.width - margin - len, size.height - margin),
        Offset(size.width - margin, size.height - margin),
        paint);
    canvas.drawLine(
        Offset(size.width - margin, size.height - margin - len),
        Offset(size.width - margin, size.height - margin),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}