// Main monitoring dashboard – shows live sensor cards + mini real-time chart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/sensor_data.dart';

import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';

import '../widgets/sensor_card.dart';
import '../widgets/section_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late List<SensorReading> _readings;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late StreamSubscription connectivitySub;

  final sensorKeys = [
    "nitrogen",
    "phosphorus",
    "potassium",
    "ph",
    "moisture",
    "temperature",
    "ec"
  ];

  int totalSensors = 0;
  int totalAlerts = 0;
  int totalPumps = 4;

  bool isInternetConnected = true;
  bool isMqttConnected = false;
  bool get isFullyConnected {
    return isInternetConnected && isMqttConnected;
  }

  DateTime? lastDataReceived;
  Timer? connectionTimer;

  final MQTTService mqttService = MQTTService();

  StreamSubscription? sensorSub;

  // chart history
  List<double> nitrogenHistory = [];
  List<double> phosphorusHistory = [];
  List<double> potassiumHistory = [];
  List<DateTime> chartTimes = [];

  void initMQTT() async {
    await mqttService.init();

    mqttService.onConnectionChanged = (status) {
      if (!mounted) return;

      setState(() {
        isMqttConnected = status;
      });
    };

    mqttService.subscribe("nutrixense/sensor");

    sensorSub = mqttService.sensorStream.listen((data) {
      lastDataReceived = DateTime.now();
      setState(() {
        isMqttConnected = true;
      });
      updateSensorData(data);
    });
  }

  void initConnectivity() {
    connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasInternet = results.any(
        (r) => r != ConnectivityResult.none,
      );

      setState(() {
        isInternetConnected = hasInternet;
      });

      if (!hasInternet) {
        setState(() {
          isMqttConnected = false;
        });
      }
    });
  }

  void startConnectionMonitor() {
    connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        // If data is stale for more than 3 seconds, consider MQTT disconnected
        if (lastDataReceived != null) {
          final diff = DateTime.now().difference(lastDataReceived!);
          if (diff.inSeconds >= 3) {
            isMqttConnected = false;
          }
        }
      });
    });
  }

  void initializeDefaultReadings() {
    _readings = [
      SensorReading(
        value: 0,
        label: "Nitrogen",
        unit: "mg/kg",
        minValue: 0,
        maxValue: 150,
        minNormal: 40,
        maxNormal: 80,
        icon: "assets/icons/leaf.png",
        colorHex: 0xFF4CAF50,
      ),
      SensorReading(
        value: 0,
        label: "Phosphorus",
        unit: "mg/kg",
        minValue: 0,
        maxValue: 100,
        minNormal: 20,
        maxNormal: 60,
        icon: "assets/icons/root.png",
        colorHex: 0xFF2196F3,
      ),
      SensorReading(
        value: 0,
        label: "Potassium",
        unit: "mg/kg",
        minValue: 0,
        maxValue: 150,
        minNormal: 40,
        maxNormal: 100,
        icon: "assets/icons/crop.png",
        colorHex: 0xFFFF9800,
      ),
      SensorReading(
        value: 0,
        label: "pH Level",
        unit: "pH",
        minValue: 0,
        maxValue: 14,
        minNormal: 5.8,
        maxNormal: 7.2,
        icon: "assets/icons/ph.png",
        colorHex: 0xFF9E9E9E,
      ),
      SensorReading(
        value: 0,
        label: "Soil Moisture",
        unit: "%",
        minValue: 0,
        maxValue: 100,
        minNormal: 40,
        maxNormal: 80,
        icon: "assets/icons/water.png",
        colorHex: 0xFF2196F3,
      ),
      SensorReading(
        value: 0,
        label: "Temperature",
        unit: "°C",
        minValue: 0,
        maxValue: 50,
        minNormal: 18,
        maxNormal: 35,
        icon: "assets/icons/temp.png",
        colorHex: 0xFFF44336,
      ),
      SensorReading(
        value: 0,
        label: "Electrical Conductivity",
        unit: "mS/cm",
        minValue: 0,
        maxValue: 5,
        minNormal: 1.0,
        maxNormal: 3.0,
        icon: "assets/icons/ec.png",
        colorHex: 0xFF7C4DFF,
      ),
    ];
  }

  void updateSensorData(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() {
      totalSensors = sensorKeys.where((key) => data.containsKey(key)).length;
      // update cards
      _readings = [
        SensorReading(
            value: (data["nitrogen"] ?? 0).toDouble(),
            label: "Nitrogen",
            unit: "mg/kg",
            minValue: 0,
            maxValue: 150,
            minNormal: 20,
            maxNormal: 80,
            icon: "assets/icons/leaf.png",
            colorHex: 0xFF4CAF50),
        SensorReading(
            value: (data["phosphorus"] ?? 0).toDouble(),
            label: "Phosporus",
            unit: "mg/kg",
            minValue: 0,
            maxValue: 100,
            minNormal: 15,
            maxNormal: 60,
            icon: "assets/icons/root.png",
            colorHex: 0xFF2196F3),
        SensorReading(
            value: (data["potassium"] ?? 0).toDouble(),
            label: "Potassium",
            unit: "mg/kg",
            minValue: 0,
            maxValue: 150,
            minNormal: 20,
            maxNormal: 100,
            icon: "assets/icons/crop.png",
            colorHex: 0xFFFF9800),
        SensorReading(
            value: (data["ph"] ?? 0).toDouble(),
            label: "pH Level",
            unit: "pH",
            minValue: 0,
            maxValue: 14,
            minNormal: 6.0,
            maxNormal: 7.5,
            icon: "assets/icons/ph.png",
            colorHex: 0xFF9E9E9E),
        SensorReading(
            value: (data["moisture"] ?? 0).toDouble(),
            label: "Soil Moisture",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            minNormal: 40,
            maxNormal: 80,
            icon: "assets/icons/water.png",
            colorHex: 0xFF2196F3),
        SensorReading(
            value: (data["temperature"] ?? 0).toDouble(),
            label: "Temperature",
            unit: "°C",
            minValue: 0,
            maxValue: 50,
            minNormal: 15,
            maxNormal: 30,
            icon: "assets/icons/temp.png",
            colorHex: 0xFFF44336),
        SensorReading(
            value: (data["ec"] ?? 0).toDouble(),
            label: "Electrical Conductivity",
            unit: "mS/cm",
            minValue: 0,
            maxValue: 5,
            minNormal: 1.0,
            maxNormal: 3.0,
            icon: "assets/icons/ec.png",
            colorHex: 0xFF7C4DFF),
      ];

      // update chart history
      nitrogenHistory.add((data["nitrogen"] ?? 0).toDouble());
      phosphorusHistory.add((data["phosphorus"] ?? 0).toDouble());
      potassiumHistory.add((data["potassium"] ?? 0).toDouble());
      chartTimes.add(DateTime.now());

      if (nitrogenHistory.length > 1800) nitrogenHistory.removeAt(0);
      if (phosphorusHistory.length > 1800) phosphorusHistory.removeAt(0);
      if (potassiumHistory.length > 1800) potassiumHistory.removeAt(0);
      if (chartTimes.length > 1800) chartTimes.removeAt(0);
    });
  }

  @override
  void initState() {
    super.initState();
    initializeDefaultReadings();

    initConnectivity();
    initMQTT();
    startConnectionMonitor();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    sensorSub?.cancel();
    connectivitySub.cancel();
    connectionTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ─── Gradient App Bar ────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 220,
              pinned: false,
              backgroundColor: AppTheme.bgPrimary,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: AppTheme.headerGradient,
                  ),
                  child: Stack(
                    children: [
                      // ─── Watermark background logo (center, very transparent) ──
                      Positioned.fill(
                        child: Align(
                          alignment:
                              const Alignment(0, 1), // 0.3 = agak ke bawah
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

                      // ─── Foreground content ──────────────────────────────
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ─── Top row: Logo + App Name | WiFi Icon ────
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Logo dari assets + App Name
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
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

                                  // ─── MQTT Badge + WiFi Icon ───────────────────────
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Small MQTT Badge
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMqttConnected
                                              ? Colors.green
                                              : Colors.orange,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isMqttConnected
                                                  ? Icons.check_circle
                                                  : Icons.access_time_rounded,
                                              color: Colors.white,
                                              size: 10,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isMqttConnected ? "LIVE" : "WAIT",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(width: 8),

                                      // WiFi Icon
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        transitionBuilder: (child, animation) =>
                                            ScaleTransition(
                                          scale: animation,
                                          child: child,
                                        ),
                                        child: Icon(
                                          isFullyConnected
                                              ? Icons.wifi
                                              : Icons.wifi_off,
                                          key: ValueKey(isFullyConnected),
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  )
                                ],
                              ),

                              const SizedBox(height: 16),

                              // ─── Greeting ─────────────────────────────────
                              Text(
                                'Good Morning,',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ─── STATS BOX (Rounded White Border) ─────────
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _statItem('7', 'Sensors'),
                                    _divider(),
                                    _statItem('4', 'Alerts'),
                                    _divider(),
                                    _statItem('4', 'Pumps'),
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

            // ─── Panel putih dengan rounded corners kiri-kanan atas ──────────
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
                  // ─── Real-time chart ──────────────────────────────────────
                  _buildRealTimeChart(),
                  const SizedBox(height: 40),

                  // ─── Sensor grid ──────────────────────────────────────────
                  const SectionHeader(title: 'Sensor Readings'),
                  const SizedBox(height: 20),
                  GridView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: _readings.length > 6 ? 6 : _readings.length,
                    itemBuilder: (context, index) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 400 + (index * 80)),
                        curve: Curves.easeOut,
                        builder: (context, value, child) => Transform.scale(
                          scale: 0.8 + 0.2 * value,
                          child: Opacity(opacity: value, child: child),
                        ),
                        child: SensorCard(reading: _readings[index]),
                      );
                    },
                  ),

                  // ─── EC Card (full-width) ──────────────────────────────────
                  if (_readings.length > 6) ...[
                    const SizedBox(height: 12),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOut,
                      builder: (context, value, child) => Transform.scale(
                        scale: 0.8 + 0.2 * value,
                        child: Opacity(opacity: value, child: child),
                      ),
                      child: _buildECCard(_readings[6]),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Vertical divider antar stat item ────────────────────────────────────────
  Widget _divider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.white.withOpacity(0.4),
    );
  }

  // ─── Stat item for bordered box ─────────────────────────────────────────────
  Widget _statItem(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ─── Real-time trend chart (NPK) ─────────────────────────────────────────────
  Widget _buildRealTimeChart() {
    String formatChartTime(DateTime time) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    List<FlSpot> toSpots(List<double> vals) {
      return List.generate(
        vals.length,
        (i) => FlSpot(i.toDouble(), vals[i]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),

        // Border tipis modern
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),

        // Shadow lebih realistis
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Real-Time Trends'),
          const SizedBox(height: 6),
          Text(
            'NPK levels over the last few minutes',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 150,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 30,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.withOpacity(0.12),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 30,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: chartTimes.length <= 4
                          ? 1
                          : (chartTimes.length / 4).ceilToDouble(),
                      getTitlesWidget: (v, _) {
                        final index = v.toInt();
                        if (index < 0 || index >= chartTimes.length) {
                          return const SizedBox();
                        }

                        return Text(
                          formatChartTime(chartTimes[index]),
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.textLight,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.bgDark,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) => touchedSpots
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(1)} mg/kg',
                              const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  _bar(toSpots(nitrogenHistory), AppTheme.primaryGreen),
                  _bar(toSpots(phosphorusHistory), AppTheme.primaryBlue),
                  _bar(toSpots(potassiumHistory), AppTheme.statusHigh),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend('Nitrogen', AppTheme.primaryGreen),
              const SizedBox(width: 16),
              _legend('Phosphorus', AppTheme.primaryBlue),
              const SizedBox(width: 16),
              _legend('Potassium', AppTheme.statusHigh),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildECCard(SensorReading reading) {
    final sensorColor = Color(reading.colorHex);

    // ─── Dynamic UI based on status (SAMA seperti SensorCard) ───
    Color borderColor;
    Color statusColor;
    IconData statusIcon;
    Color backgroundTint;

    switch (reading.status) {
      case 'Low':
        borderColor = AppTheme.statusLow;
        statusColor = AppTheme.statusLow;
        statusIcon = Icons.arrow_downward_rounded;
        backgroundTint = AppTheme.statusLow.withOpacity(0.005);
        break;

      case 'High':
        borderColor = AppTheme.statusHigh;
        statusColor = AppTheme.statusHigh;
        statusIcon = Icons.arrow_upward_rounded;
        backgroundTint = AppTheme.statusHigh.withOpacity(0.005);
        break;

      default:
        borderColor = AppTheme.statusNormal;
        statusColor = AppTheme.statusNormal;
        statusIcon = Icons.check_circle_rounded;
        backgroundTint = AppTheme.statusNormal.withOpacity(0.005);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: backgroundTint,

        borderRadius: BorderRadius.circular(20),

        // ─── BORDER mengikuti status ───
        border: Border.all(
          color: borderColor.withOpacity(0.25),
          width: 1.2,
        ),

        // ─── shadow dibuat lebih soft (tidak “glow berlebihan”) ───
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: sensorColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
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

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    Text(
                      reading.unit,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              // STATUS BADGE (tetap konsisten)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 11, color: statusColor),
                    const SizedBox(width: 3),
                    Text(
                      reading.status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // VALUE
          Text(
            '${reading.value}',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: sensorColor,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            reading.unit,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 10),

          // PROGRESS
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: reading.normalizedValue,
              backgroundColor: sensorColor.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(sensorColor),
              minHeight: 6,
            ),
          ),

          // ─── Min / Max label ────────────────────────────────────────
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Min ${reading.minNormal} ${reading.unit}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textLight,
                ),
              ),
              Text(
                'Max ${reading.maxNormal} ${reading.unit}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.4,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.18), color.withOpacity(0)],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
