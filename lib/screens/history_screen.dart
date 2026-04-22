// lib/screens/history_screen.dart
// Time-series chart screen – shows historical sensor data with filter tabs

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/dummy_data.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  int _selectedFilter = 0; // 0=Today, 1=7 Days, 2=30 Days
  int _selectedSensor = 0; // 0=NPK, 1=pH, 2=Moisture, 3=Temp
  late List<SensorDataPoint> _data;

  final List<String> _filters = ['Today', '7 Days', '30 Days'];
  final List<int> _filterDays = [1, 7, 30];

  final List<Map<String, dynamic>> _sensors = [
    {'label': 'NPK', 'icon': Icons.eco_rounded},
    {'label': 'pH', 'icon': Icons.science_rounded},
    {'label': 'Moisture', 'icon': Icons.water_drop_rounded},
    {'label': 'Temp', 'icon': Icons.thermostat_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _data = DummyData.getHistoryData(days: _filterDays[_selectedFilter]);
  }

  // Build chart lines based on selected sensor
  List<LineChartBarData> get _chartLines {
    if (_data.isEmpty) return [];

    List<FlSpot> toSpots(List<double> vals) {
      return List.generate(
        vals.length,
        (i) => FlSpot(i.toDouble(), vals[i]),
      );
    }

    switch (_selectedSensor) {
      case 0: // NPK
        return [
          _bar(toSpots(_data.map((d) => d.nitrogen).toList()),
              AppTheme.primaryGreen, 'N'),
          _bar(toSpots(_data.map((d) => d.phosphorus).toList()),
              AppTheme.primaryBlue, 'P'),
          _bar(toSpots(_data.map((d) => d.potassium).toList()),
              AppTheme.statusHigh, 'K'),
        ];
      case 1: // pH
        return [
          _bar(toSpots(_data.map((d) => d.ph).toList()),
              const Color(0xFF7B1FA2), 'pH'),
        ];
      case 2: // Moisture
        return [
          _bar(toSpots(_data.map((d) => d.moisture).toList()),
              AppTheme.lightBlue, 'Moisture'),
        ];
      case 3: // Temperature
        return [
          _bar(toSpots(_data.map((d) => d.temperature).toList()),
              AppTheme.statusLow, 'Temp'),
        ];
      default:
        return [];
    }
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color, String label) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.15), color.withOpacity(0)],
        ),
      ),
    );
  }

  // Summary stats for selected sensor
  List<_StatItem> get _stats {
    if (_data.isEmpty) return [];

    List<double> vals;
    String unit;
    switch (_selectedSensor) {
      case 0:
        vals = _data.map((d) => d.nitrogen).toList();
        unit = 'mg/kg';
        break;
      case 1:
        vals = _data.map((d) => d.ph).toList();
        unit = 'pH';
        break;
      case 2:
        vals = _data.map((d) => d.moisture).toList();
        unit = '%';
        break;
      default:
        vals = _data.map((d) => d.temperature).toList();
        unit = '°C';
    }

    final avg = vals.reduce((a, b) => a + b) / vals.length;
    final min = vals.reduce((a, b) => a < b ? a : b);
    final max = vals.reduce((a, b) => a > b ? a : b);

    return [
      _StatItem('Avg', '${avg.toStringAsFixed(1)} $unit', AppTheme.primaryGreen),
      _StatItem('Min', '${min.toStringAsFixed(1)} $unit', AppTheme.primaryBlue),
      _StatItem('Max', '${max.toStringAsFixed(1)} $unit', AppTheme.statusHigh),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── App bar ────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bgCard,
            elevation: 0,
            title: const Text(
              'History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: List.generate(
                    _filters.length,
                    (i) => Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedFilter = i;
                          _loadData();
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: EdgeInsets.only(right: i < _filters.length - 1 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedFilter == i
                                ? AppTheme.primaryGreen
                                : AppTheme.bgPrimary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _filters[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _selectedFilter == i
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── Sensor type selector ────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(
                      _sensors.length,
                      (i) => GestureDetector(
                        onTap: () => setState(() => _selectedSensor = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedSensor == i
                                ? AppTheme.primaryGreen.withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _selectedSensor == i
                                  ? AppTheme.primaryGreen
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _sensors[i]['icon'] as IconData,
                                size: 15,
                                color: _selectedSensor == i
                                    ? AppTheme.primaryGreen
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _sensors[i]['label'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedSensor == i
                                      ? AppTheme.primaryGreen
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ─── Stats row ───────────────────────────────────────────────
                Row(
                  children: _stats
                      .map((s) => Expanded(
                            child: Container(
                              margin: EdgeInsets.only(
                                  right: s != _stats.last ? 10 : 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: s.color.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.label,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textLight,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.value,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: s.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),

                // ─── Main chart ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 220,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 20,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: Colors.grey.withOpacity(0.1),
                                strokeWidth: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 36,
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
                                  interval: (_data.length / 4).ceil().toDouble(),
                                  getTitlesWidget: (v, _) {
                                    final idx = v.toInt().clamp(0, _data.length - 1);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        DateFormat('d/M').format(_data[idx].time),
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: AppTheme.textLight,
                                        ),
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
                              ),
                            ),
                            lineBarsData: _chartLines,
                          ),
                        ),
                      ),

                      // Legend
                      if (_selectedSensor == 0) ...[
                        const SizedBox(height: 12),
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─── Data table ──────────────────────────────────────────────
                _buildDataTable(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
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

  Widget _buildDataTable() {
    // Show last 8 data points
    final recent = _data.reversed.take(8).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: const Text(
              'Recent Readings',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          // Header
          Container(
            color: AppTheme.bgPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ['Time', 'N', 'P', 'K', 'pH']
                  .map((h) => Expanded(
                        child: Text(
                          h,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textLight,
                          ),
                          textAlign: h == 'Time' ? TextAlign.left : TextAlign.center,
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Rows
          ...recent.asMap().entries.map((entry) {
            final d = entry.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.08),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('HH:mm').format(d.time),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ...[d.nitrogen, d.phosphorus, d.potassium, d.ph]
                      .map((v) => Expanded(
                            child: Text(
                              v.toStringAsFixed(1),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final Color color;
  const _StatItem(this.label, this.value, this.color);
}