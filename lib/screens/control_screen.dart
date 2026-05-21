// lib/screens/control_screen.dart
// Pump controller page – toggle pumps A/B/C with loading animations and status display

import 'package:flutter/material.dart';
import '../models/dummy_data.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';
import '../widgets/pump_card.dart';
import '../services/mqtt_service.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late List<PumpController> _pumps;
  final MQTTService mqttService = MQTTService();

  @override
  void initState() {
    super.initState();
    _pumps = DummyData.getPumps();
    mqttService.init();
  }

  Future<void> _wateringPump() async {
    try {
      // Relay 4 = Pompa Air
      const waterRelay = 4;

      // ON pompa air
      mqttService.publishRelay(waterRelay, false);

      _showWaterSnackBar(true);

      // Durasi penyiraman
      await Future.delayed(const Duration(seconds: 5));

      // OFF pompa air
      mqttService.publishRelay(waterRelay, true);

      _showWaterSnackBar(false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Water irrigation failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showWaterSnackBar(bool started) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              started
                  ? Icons.water_drop_rounded
                  : Icons.water_damage_outlined,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              started
                  ? 'Water irrigation started'
                  : 'Water irrigation completed',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Toggle pump with simulated network delay
  Future<void> _togglePump(int index, bool value) async {
    setState(() {
      _pumps[index].isLoading = true;
    });

    // Relay 1-4
    final relayNumber = index + 1;
    // Publish MQTT Command
    mqttService.setRelay(relayNumber, value);
    // Small delay for animation
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _pumps[index].isLoading = false;
        _pumps[index].isOn = value;
      });
      _showSnackBar(_pumps[index]);
    }
  }

  void _showSnackBar(PumpController pump) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              pump.isOn ? Icons.play_circle_rounded : Icons.stop_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '${pump.name} (${pump.nutrient}) ${pump.isOn ? 'started' : 'stopped'}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: pump.isOn ? AppTheme.primaryGreen : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 0, milliseconds: 500),
      ),
    );
  }

  int get _activePumps => _pumps.where((p) => p.isOn).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Gradient App Bar ────────────────────────────────────────────
          SliverAppBar(
            pinned: false,
            expandedHeight: 220,
            backgroundColor: AppTheme.bgPrimary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                ),
                child: Stack(
                  children: [
                    // ─── Watermark background logo ─────────────────────────
                    Positioned.fill(
                      child: Align(
                        alignment: const Alignment(0, 1),
                        child: Opacity(
                          opacity: 0.06,
                          child: Image.asset(
                            'assets/images/w_nutrixense_cropped.png',
                            width: 280,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),

                    // ─── Foreground Content ────────────────────────────────
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ─── Top Row ──────────────────────────────────
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              crossAxisAlignment:
                                  CrossAxisAlignment.center,
                              children: [
                                // Logo + App Name
                                Row(
                                  children: [
                                    Image.asset(
                                      'assets/images/w_nutrixense.png',
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'NutriXense',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),

                                // AI Powered Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color:
                                          Colors.white.withOpacity(0.25),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.auto_awesome,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'AI Powered',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ─── Title ────────────────────────────────────
                            const Text(
                              'Pump Control',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),

                            const SizedBox(height: 8),

                            // ─── Subtitle ─────────────────────────────────
                            Row(
                              children: [
                                Text(
                                  'Manage your nutrient & irrigation pumps',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ─── Status Box ───────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$_activePumps of ${_pumps.length} pumps active',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13,
                                    ),
                                  ),

                                SizedBox(width: 8),

                                if (_activePumps > 0)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF69F0AE),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
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

          // ─── Rounded White Panel ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: const SizedBox(height: 20),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── Pump cards ───────────────────────────────────────────
                ..._pumps.asMap().entries.map((entry) {
                  final i = entry.key;
                  final pump = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PumpCard(
                      pump: pump,
                      onToggle: (value) => _togglePump(i, value),
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // ─── Water Irrigation Button ─────────────────────────────
                _buildWateringButton(),

                const SizedBox(height: 14),

                // ─── Emergency Stop ──────────────────────────────────────
                _buildEmergencyStop(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWateringButton() {
    return GestureDetector(
      onTap: _wateringPump,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryBlue,
              AppTheme.primaryBlue.withOpacity(0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.water_drop_rounded,
              color: Colors.white,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Start Water Irrigation',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyStop() {
    final anyOn = _pumps.any((p) => p.isOn);
    return GestureDetector(
      onTap: anyOn
          ? () async {
              for (int i = 0; i < _pumps.length; i++) {
                if (_pumps[i].isOn) {
                  await _togglePump(i, false);
                }
              }
            }
          : null,
      child: AnimatedOpacity(
        opacity: anyOn ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.statusLow.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.statusLow.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.stop_circle_outlined,
                color: AppTheme.statusLow,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Emergency Stop All Pumps',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.statusLow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}