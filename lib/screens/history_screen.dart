// lib/screens/history_screen.dart
// Time-series chart screen – shows historical sensor data with filter tabs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sensor_data.dart';
import '../services/threshold_config_service.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _selectedFilter = 0; // 0=Today, 1=7 Days, 2=30 Days
  int _selectedSensor = 0; // 0=NPK, 1=pH, 2=Moisture, 3=Temp
  List<SensorDataPoint> _data = [];
  int _pageIndex = 0;
  int _totalRows = 0;
  static const int _pageSize = 100;

  List<SensorDataPoint> _pageData = [];
  final List<DocumentSnapshot> _pageCursors = [];
  final Set<String> _knownHistoryDocIds = {};
  final Set<String> _pageDocIds = {};
  StreamSubscription<QuerySnapshot>? _latestSubscription;
  bool _isLoadingHistory = true;
  Object? _historyError;
  final ThresholdConfigService _thresholdConfigService =
      ThresholdConfigService.instance;

  final List<String> _filters = ['Today', '7 Days', '30 Days'];
  final List<int> _filterDays = [1, 7, 30];

  int get _totalPages =>
      _totalRows == 0 ? 1 : ((_totalRows - 1) ~/ _pageSize) + 1;

  double get _chartMinY => 0;

  double get _chartMaxY {
    switch (_selectedSensor) {
      case 0:
        return _npkChartMaxY;
      case 1:
        return 14; // pH
      case 2:
        return 100; // Moisture
      case 3:
        return 50; // Temperature
      default:
        return 100;
    }
  }

  double get _chartHorizontalInterval {
    switch (_selectedSensor) {
      case 0:
        return _npkChartMaxY / 5;
      case 1:
        return 2;
      case 2:
        return 20;
      case 3:
        return 10;
      default:
        return 20;
    }
  }

  double? get _chartMinX => _selectedFilter == 0 ? 0 : null;

  double? get _chartMaxX {
    if (_selectedFilter != 0) return null;

    final now = DateTime.now();
    return now.hour + (now.minute / 60.0) + (now.second / 3600.0);
  }

  double get _npkChartMaxY {
    return [
      _gaugeMaxValue('max_nitrogen', 80, 150),
      _gaugeMaxValue('max_phosphorus', 60, 100),
      _gaugeMaxValue('max_potassium', 100, 150),
    ].reduce((a, b) => a > b ? a : b);
  }

  double _gaugeMaxValue(
    String maxNormalKey,
    double originalMaxNormal,
    double originalMaxValue,
  ) {
    final maxNormal = _thresholdConfigService.value(
      maxNormalKey,
      originalMaxNormal,
    );
    final originalHeadroom = originalMaxValue - originalMaxNormal;
    return maxNormal + originalHeadroom;
  }

  @override
  void initState() {
    super.initState();
    _thresholdConfigService.addListener(_syncThresholdConfig);
    _refreshHistory();
  }

  @override
  void dispose() {
    _thresholdConfigService.removeListener(_syncThresholdConfig);
    _latestSubscription?.cancel();
    super.dispose();
  }

  void _syncThresholdConfig() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshHistory() async {
    await _latestSubscription?.cancel();
    _latestSubscription = null;

    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
      _data = [];
      _pageData = [];
      _pageIndex = 0;
      _totalRows = 0;
      _pageCursors.clear();
      _knownHistoryDocIds.clear();
      _pageDocIds.clear();
    });

    try {
      await _loadInitialHistory();
      await _loadTotalRows();
      await _loadPage();
      _listenForLatestHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyError = e);
    } finally {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  Query _historyBaseQuery() {
    final startDate = _historyStartDate();

    return FirebaseFirestore.instance.collection('sensor_data').where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        );
  }

  DateTime _historyStartDate() {
    final now = DateTime.now();
    if (_selectedFilter == 0) {
      return DateTime(now.year, now.month, now.day);
    }

    return now.subtract(Duration(days: _filterDays[_selectedFilter]));
  }

  List<SensorDataPoint> _applySampling(List<SensorDataPoint> source) {
    if (source.isEmpty) return [];

    // TODAY → tampilkan semua data
    if (_selectedFilter == 0) {
      return source;
    }

    // 7 DAYS → ambil 1 data tiap 15 menit
    final Duration interval = _selectedFilter == 1
        ? const Duration(minutes: 15)
        : const Duration(hours: 1);

    final List<SensorDataPoint> sampled = [];

    DateTime? lastIncluded;

    for (final item in source) {
      if (lastIncluded == null ||
          item.time.difference(lastIncluded).abs() >= interval) {
        sampled.add(item);
        lastIncluded = item.time;
      }
    }

    return sampled;
  }

  Future<void> _loadInitialHistory() async {
    final query = _historyBaseQuery()
        .orderBy('timestamp', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .withConverter<SensorDataPoint>(
          fromFirestore: (doc, _) => SensorDataPoint.fromFirestore(doc),
          toFirestore: (_, __) => throw UnsupportedError(
            'History screen does not write sensor data.',
          ),
        );

    QuerySnapshot<SensorDataPoint>? snapshot;

    try {
      snapshot = await query.get(const GetOptions(source: Source.cache));
    } catch (_) {
      snapshot = null;
    }

    if (snapshot == null || snapshot.docs.isEmpty) {
      snapshot = await query.get(const GetOptions(source: Source.server));
    }

    _knownHistoryDocIds.addAll(snapshot.docs.map((doc) => doc.id));

    final points = snapshot.docs.map((doc) => doc.data()).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    // Apply interval sampling for chart
    final sampledPoints = _applySampling(points);

    if (!mounted) return;
    setState(() => _data = sampledPoints);
  }

  Future<void> _loadTotalRows() async {
    final snapshot = await _historyBaseQuery().count().get();

    if (!mounted) return;
    setState(() => _totalRows = snapshot.count ?? 0);
  }

  void _listenForLatestHistory() {
    final startAfter = _data.isNotEmpty ? _data.last.time : _historyStartDate();

    _latestSubscription = FirebaseFirestore.instance
        .collection('sensor_data')
        .where(
          'timestamp',
          isGreaterThan: Timestamp.fromDate(startAfter),
        )
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty || !mounted) return;

      final newDocs = snapshot.docs
          .where((doc) => !_knownHistoryDocIds.contains(doc.id))
          .toList();

      if (newDocs.isEmpty) return;

      final latestPoints =
          newDocs.map((doc) => SensorDataPoint.fromFirestore(doc)).toList();
      final latestDocIds = newDocs.map((doc) => doc.id).toList();

      setState(() {
        _knownHistoryDocIds.addAll(latestDocIds);

        final merged = [..._data, ...latestPoints]
          ..sort((a, b) => a.time.compareTo(b.time));
        // Apply interval sampling again
        _data = _applySampling(merged);

        _totalRows += latestPoints.length;
        if (_pageIndex == 0) {
          final newPagePoints = <SensorDataPoint>[];

          for (int i = 0; i < latestPoints.length; i++) {
            final docId = latestDocIds[i];
            if (_pageDocIds.add(docId)) {
              newPagePoints.add(latestPoints[i]);
            }
          }

          if (newPagePoints.isEmpty) return;

          _pageData = [..._pageData, ...newPagePoints]
            ..sort((a, b) => b.time.compareTo(a.time));
          if (_pageData.length > _pageSize) {
            _pageData = _pageData.take(_pageSize).toList();
          }
        }
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() => _historyError = e);
    });
  }

  Future<void> _loadPage() async {
    Query query = _historyBaseQuery()
        .orderBy('timestamp', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(_pageSize);

    // pagination
    if (_pageIndex > 0 && _pageCursors.length >= _pageIndex) {
      query = query.startAfterDocument(_pageCursors[_pageIndex - 1]);
    }

    final snapshot = await query.get();
    if (!mounted) return;

    setState(() {
      _pageDocIds
        ..clear()
        ..addAll(snapshot.docs.map((doc) => doc.id));
      _knownHistoryDocIds.addAll(snapshot.docs.map((doc) => doc.id));
      _pageData =
          snapshot.docs.map((d) => SensorDataPoint.fromFirestore(d)).toList();
      if (snapshot.docs.isNotEmpty) {
        if (_pageCursors.length <= _pageIndex) {
          _pageCursors.add(snapshot.docs.last);
        } else {
          _pageCursors[_pageIndex] = snapshot.docs.last;
        }
      }
    });
  }

  final List<Map<String, dynamic>> _sensors = [
    {'label': 'NPK', 'icon': Icons.eco_rounded},
    {'label': 'pH', 'icon': Icons.science_rounded},
    {'label': 'Moisture', 'icon': Icons.water_drop_rounded},
    {'label': 'Temp', 'icon': Icons.thermostat_rounded},
  ];

  // Build chart lines based on selected sensor
  List<LineChartBarData> get _chartLines {
    if (_data.isEmpty) return [];

    double xValueFromTime(DateTime time) {
      if (_selectedFilter == 0) {
        // Today → jam desimal (0–24)
        return time.hour + (time.minute / 60.0);
      }
      return _data.indexOf(_data.firstWhere((d) => d.time == time)).toDouble();
    }

    List<FlSpot> toSpots(List<double> vals, List<DateTime> times) {
      return List.generate(
        vals.length,
        (i) => FlSpot(xValueFromTime(times[i]), vals[i]),
      );
    }

    switch (_selectedSensor) {
      case 0: // NPK
        return [
          _bar(
              toSpots(_data.map((d) => d.nitrogen).toList(),
                  _data.map((d) => d.time).toList()),
              AppTheme.primaryGreen,
              'N'),
          _bar(
              toSpots(_data.map((d) => d.phosphorus).toList(),
                  _data.map((d) => d.time).toList()),
              AppTheme.primaryBlue,
              'P'),
          _bar(
              toSpots(_data.map((d) => d.potassium).toList(),
                  _data.map((d) => d.time).toList()),
              AppTheme.statusHigh,
              'K'),
        ];
      case 1: // pH
        return [
          _bar(
              toSpots(_data.map((d) => d.ph).toList(),
                  _data.map((d) => d.time).toList()),
              const Color(0xFF7B1FA2),
              'pH'),
        ];
      case 2: // Moisture
        return [
          _bar(
              toSpots(_data.map((d) => d.moisture).toList(),
                  _data.map((d) => d.time).toList()),
              AppTheme.lightBlue,
              'Moisture'),
        ];
      case 3: // Temperature
        return [
          _bar(
              toSpots(_data.map((d) => d.temperature).toList(),
                  _data.map((d) => d.time).toList()),
              AppTheme.statusLow,
              'Temp'),
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
      _StatItem(
          'Avg', '${avg.toStringAsFixed(1)} $unit', AppTheme.primaryGreen),
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
                        onTap: () {
                          if (_selectedFilter == i) return;
                          setState(() => _selectedFilter = i);
                          _refreshHistory();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: EdgeInsets.only(
                              right: i < _filters.length - 1 ? 8 : 0),
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
            sliver: _isLoadingHistory
                ? const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _historyError != null
                    ? SliverFillRemaining(
                        child: Center(
                          child: Text('Error: $_historyError'),
                        ),
                      )
                    : _data.isEmpty
                        ? const SliverFillRemaining(
                            child: Center(
                              child: Text(
                                'No history data',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildListDelegate([
                              // ─── Sensor type selector ────────────────────────────────────
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List.generate(
                                    _sensors.length,
                                    (i) => GestureDetector(
                                      onTap: () =>
                                          setState(() => _selectedSensor = i),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        margin:
                                            const EdgeInsets.only(right: 10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: _selectedSensor == i
                                              ? AppTheme.primaryGreen
                                                  .withOpacity(0.12)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(20),
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
                                                right:
                                                    s != _stats.last ? 10 : 0),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: s.color.withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
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
                                          minX: _chartMinX,
                                          maxX: _chartMaxX,
                                          minY: _chartMinY,
                                          maxY: _chartMaxY,
                                          gridData: FlGridData(
                                            show: true,
                                            drawVerticalLine: false,
                                            horizontalInterval:
                                                _chartHorizontalInterval,
                                            getDrawingHorizontalLine: (_) =>
                                                FlLine(
                                              color:
                                                  Colors.grey.withOpacity(0.1),
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
                                                sideTitles: SideTitles(
                                                    showTitles: false)),
                                            topTitles: const AxisTitles(
                                                sideTitles: SideTitles(
                                                    showTitles: false)),
                                            bottomTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                reservedSize: 24,
                                                interval: _selectedFilter == 0
                                                    ? 3
                                                    : (_data.length / 4)
                                                        .ceilToDouble(),
                                                getTitlesWidget: (v, _) {
                                                  if (_data.isEmpty) {
                                                    return const SizedBox();
                                                  }

                                                  if (_selectedFilter == 0) {
                                                    // TODAY → tampilkan jam
                                                    final hour = v.toInt();
                                                    if (hour < 0 || hour > 24) {
                                                      return const SizedBox();
                                                    }

                                                    return Text(
                                                      '${hour.toString().padLeft(2, '0')}:00',
                                                      style: const TextStyle(
                                                          fontSize: 9,
                                                          color: AppTheme
                                                              .textLight),
                                                    );
                                                  }

                                                  // 7 & 30 days → tetap tanggal
                                                  final idx = v.toInt().clamp(
                                                      0, _data.length - 1);
                                                  return Text(
                                                    DateFormat('d/M').format(
                                                        _data[idx].time),
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color:
                                                            AppTheme.textLight),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          borderData: FlBorderData(show: false),
                                          lineTouchData: LineTouchData(
                                            touchTooltipData:
                                                LineTouchTooltipData(
                                              getTooltipColor: (_) =>
                                                  AppTheme.bgDark,
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _legend('Nitrogen',
                                              AppTheme.primaryGreen),
                                          const SizedBox(width: 16),
                                          _legend('Phosphorus',
                                              AppTheme.primaryBlue),
                                          const SizedBox(width: 16),
                                          _legend(
                                              'Potassium', AppTheme.statusHigh),
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
    final recent = [..._pageData]..sort((a, b) => b.time.compareTo(a.time));

    final displayed = recent.take(_pageSize).toList();

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
                          textAlign:
                              h == 'Time' ? TextAlign.left : TextAlign.center,
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Rows
          ...displayed.asMap().entries.map((entry) {
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
                      DateFormat('dd/MM HH:mm').format(d.time),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _pageIndex > 0
                    ? () {
                        setState(() {
                          _pageIndex--;
                        });
                        _loadPage();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_pageIndex + 1} / $_totalPages'),
              IconButton(
                onPressed: _pageIndex < _totalPages - 1
                    ? () {
                        setState(() {
                          _pageIndex++;
                        });
                        _loadPage();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
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
