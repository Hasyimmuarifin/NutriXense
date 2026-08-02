// lib/screens/history_screen.dart
// Time-series chart screen – shows historical sensor data with filter tabs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sensor_data.dart';
import '../services/offline_data_cache_service.dart';
import '../services/threshold_config_service.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistoryExportFormat { pdf, csv, excel }

class _HistoryScreenState extends State<HistoryScreen> {
  static const MethodChannel _downloadsChannel =
      MethodChannel('com.example.nutrixense/alerts');

  static const int _customFilterIndex = 3;

  int _selectedFilter = 0; // 0=Hari ini, 1=7 Hari, 2=30 Hari, 3=Filter
  int _selectedSensor = 0; // 0=NPK, 1=pH, 2=Moisture, 3=Temp, 4=EC
  List<SensorDataPoint> _data = [];
  List<SensorDataPoint> _rangeData = [];
  int _pageIndex = 0;
  int _totalRows = 0;
  static const int _pageSize = 100;
  static const int _pdfMaxSampleRows = 720;
  static const int _pdfMaxPages = 120;

  List<SensorDataPoint> _pageData = [];
  final Set<String> _knownHistoryDocIds = {};
  final Set<String> _pageDocIds = {};
  StreamSubscription<QuerySnapshot>? _latestSubscription;
  bool _isLoadingHistory = true;
  bool _isExportingHistory = false;
  bool _isDeletingHistory = false;
  Object? _historyError;
  DateTime? _latestHistorySyncTime;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  final OfflineDataCacheService _offlineCache =
      OfflineDataCacheService.instance;
  final ThresholdConfigService _thresholdConfigService =
      ThresholdConfigService.instance;

  final List<String> _filters = ['Hari ini', '7 Hari', '30 Hari', 'Filter'];
  final List<int> _filterDays = [1, 7, 30];

  bool get _isCustomFilter => _selectedFilter == _customFilterIndex;

  String get _selectedRangeLabel {
    if (_isCustomFilter && _customStartDate != null && _customEndDate != null) {
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      return '${formatter.format(_customStartDate!)} - '
          '${formatter.format(_customEndDate!)}';
    }

    return _filters[_selectedFilter];
  }

  String get _selectedRangeFileToken {
    if (_isCustomFilter && _customStartDate != null && _customEndDate != null) {
      final formatter = DateFormat('yyyyMMdd_HHmm');
      return 'filter_${formatter.format(_customStartDate!)}_'
          '${formatter.format(_customEndDate!)}';
    }

    return _selectedRangeLabel
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }

  int get _totalPages {
    final pages = _totalRows == 0 ? 1 : ((_totalRows - 1) ~/ _pageSize) + 1;
    return pages > 15 ? 15 : pages;
  }

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
      case 4:
        return _ecChartMaxY;
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
      case 4:
        return _ecChartMaxY / 5;
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
    final thresholdMax = [
      _gaugeMaxValue('max_nitrogen', 200, 250),
      _gaugeMaxValue('max_phosphorus', 50, 100),
      _gaugeMaxValue('max_potassium', 200, 250),
    ].reduce((a, b) => a > b ? a : b);

    double dataMax = 0;
    for (final d in _data) {
      if (d.nitrogen > dataMax) dataMax = d.nitrogen;
      if (d.phosphorus > dataMax) dataMax = d.phosphorus;
      if (d.potassium > dataMax) dataMax = d.potassium;
    }

    if (dataMax > 0 && (dataMax * 1.15) > thresholdMax) {
      return (dataMax * 1.15).ceilToDouble();
    }
    return thresholdMax;
  }

  double get _ecChartMaxY {
    final thresholdMax = _gaugeMaxValue('max_ec', 1.8, 4);

    double dataMax = 0;
    for (final d in _data) {
      if (d.ec > dataMax) dataMax = d.ec;
    }

    if (dataMax > 0 && (dataMax * 1.15) > thresholdMax) {
      return double.parse((dataMax * 1.15).toStringAsFixed(1));
    }
    return thresholdMax;
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
      _rangeData = [];
      _pageData = [];
      _pageIndex = 0;
      _totalRows = 0;
      _latestHistorySyncTime = null;
      _knownHistoryDocIds.clear();
      _pageDocIds.clear();
    });

    try {
      await _loadInitialHistory();
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
    final endDate = _historyEndDate();

    var query = FirebaseFirestore.instance.collection('sensor_data').where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        );

    if (endDate != null) {
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }

    return query;
  }

  DateTime _historyStartDate() {
    final now = DateTime.now();
    if (_isCustomFilter && _customStartDate != null) {
      return _customStartDate!;
    }

    if (_isCustomFilter) {
      return now.subtract(const Duration(days: 1));
    }

    if (_selectedFilter == 0) {
      return DateTime(now.year, now.month, now.day);
    }

    return now.subtract(Duration(days: _filterDays[_selectedFilter]));
  }

  DateTime? _historyEndDate() {
    if (_isCustomFilter) return _customEndDate;
    return null;
  }

  bool _isInHistoryRange(DateTime time) {
    final startDate = _historyStartDate();
    final endDate = _historyEndDate();

    if (time.isBefore(startDate)) return false;
    if (endDate != null && time.isAfter(endDate)) return false;
    return true;
  }

  List<SensorDataPoint> _applySampling(List<SensorDataPoint> source) {
    if (source.isEmpty) return [];
    final maxNodes = _chartNodeLimitForRange();
    final meaningfulSource = source
        .where((item) => _chartPriorityScore(item) > 0)
        .toList(growable: false);
    final chartSource = meaningfulSource.isEmpty ? source : meaningfulSource;

    if (chartSource.length <= maxNodes) return chartSource;
    if (maxNodes <= 1) return [source.first];

    final sampled = <SensorDataPoint>[];

    for (var index = 0; index < maxNodes; index++) {
      final start = (index * chartSource.length / maxNodes).floor();
      final end = (((index + 1) * chartSource.length / maxNodes).ceil())
          .clamp(start + 1, chartSource.length);
      final bucket = chartSource.sublist(start, end);

      sampled.add(
        bucket.reduce((best, item) {
          final bestScore = _chartPriorityScore(best);
          final itemScore = _chartPriorityScore(item);
          if (itemScore > bestScore) return item;
          if (itemScore == bestScore && item.time.isAfter(best.time)) {
            return item;
          }
          return best;
        }),
      );
    }

    return sampled..sort((a, b) => a.time.compareTo(b.time));
  }

  double _chartPriorityScore(SensorDataPoint item) {
    return switch (_selectedSensor) {
      0 => [
          item.nitrogen,
          item.phosphorus,
          item.potassium,
        ].reduce((a, b) => a > b ? a : b),
      1 => item.ph,
      2 => item.moisture,
      3 => item.temperature,
      4 => item.ec,
      _ => 0,
    };
  }

  int _chartNodeLimitForRange() {
    final startDate = _historyStartDate();
    final endDate = _historyEndDate() ?? DateTime.now();
    final duration = endDate.isAfter(startDate)
        ? endDate.difference(startDate)
        : const Duration(hours: 1);

    if (duration <= const Duration(hours: 1)) return 120;
    if (duration <= const Duration(hours: 6)) return 180;
    if (duration <= const Duration(days: 1)) return 240;
    if (duration <= const Duration(days: 7)) return 288;
    if (duration <= const Duration(days: 30)) return 360;
    return 420;
  }

  Future<void> _loadInitialHistory() async {
    var cached = await _offlineCache.loadSensorHistory();
    _applyCachedHistory(cached);

    final rangeHasCache = _historyEntriesInRange(cached).isNotEmpty;
    final earliestCachedTime = _earliestHistoryTime(cached);
    final latestCachedTime = _latestHistoryTime(cached);
    final backfilled = rangeHasCache && earliestCachedTime != null
        ? await _fetchHistoryBackfill(
            from: _historyStartDate(),
            until: earliestCachedTime,
          )
        : const <CachedSensorDataPoint>[];
    final synced = await _fetchHistoryUpdates(
      fetchFrom: rangeHasCache ? latestCachedTime : _historyStartDate(),
      includeBoundary: !rangeHasCache,
    );

    final fetched = [...backfilled, ...synced];
    if (fetched.isNotEmpty) {
      cached = await _offlineCache.mergeSensorHistory(fetched);
      _applyCachedHistory(cached);
    }
  }

  void _listenForLatestHistory() {
    final startAfter = _latestHistorySyncTime ?? _historyStartDate();
    final endDate = _historyEndDate();

    var query = FirebaseFirestore.instance.collection('sensor_data').where(
          'timestamp',
          isGreaterThan: Timestamp.fromDate(startAfter),
        );

    if (endDate != null) {
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }

    _latestSubscription = query
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      unawaited(_handleLatestHistorySnapshot(snapshot));
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() => _historyError = e);
    });
  }

  Future<void> _handleLatestHistorySnapshot(QuerySnapshot snapshot) async {
    if (snapshot.docs.isEmpty || !mounted) return;

    final newDocs =
        snapshot.docs.where((doc) => !_knownHistoryDocIds.contains(doc.id));
    final newEntries =
        newDocs.map(CachedSensorDataPoint.fromFirestore).toList();

    if (newEntries.isEmpty) return;

    final cached = await _offlineCache.mergeSensorHistory(newEntries);
    if (!mounted) return;

    _applyCachedHistory(cached);
  }

  Future<void> _loadPage() async {
    final cached = await _offlineCache.loadSensorHistory();
    if (!mounted) return;

    _applyCachedHistory(cached, keepPageIndex: true);
  }

  List<CachedSensorDataPoint> _historyEntriesInRange(
    List<CachedSensorDataPoint> entries,
  ) {
    return entries.where((entry) => _isInHistoryRange(entry.data.time)).toList()
      ..sort((a, b) => a.data.time.compareTo(b.data.time));
  }

  DateTime? _latestHistoryTime(List<CachedSensorDataPoint> entries) {
    final rangeEntries = _historyEntriesInRange(entries);
    if (rangeEntries.isEmpty) return null;

    return rangeEntries.last.data.time;
  }

  DateTime? _earliestHistoryTime(List<CachedSensorDataPoint> entries) {
    final rangeEntries = _historyEntriesInRange(entries);
    if (rangeEntries.isEmpty) return null;

    return rangeEntries.first.data.time;
  }

  Future<List<CachedSensorDataPoint>> _fetchHistoryBackfill({
    required DateTime from,
    required DateTime until,
  }) async {
    if (!until.isAfter(from)) return const [];

    try {
      var query = FirebaseFirestore.instance
          .collection('sensor_data')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from),
          )
          .where(
            'timestamp',
            isLessThan: Timestamp.fromDate(until),
          );
      final endDate = _historyEndDate();
      if (endDate != null) {
        query = query.where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(endDate),
        );
      }

      final snapshot = await query
          .orderBy('timestamp', descending: false)
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .where((doc) => !_knownHistoryDocIds.contains(doc.id))
          .map(CachedSensorDataPoint.fromFirestore)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<CachedSensorDataPoint>> _fetchHistoryUpdates({
    required DateTime? fetchFrom,
    required bool includeBoundary,
  }) async {
    final boundary = fetchFrom ?? _historyStartDate();
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('sensor_data');

    query = includeBoundary
        ? query.where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(boundary),
          )
        : query.where(
            'timestamp',
            isGreaterThan: Timestamp.fromDate(boundary),
          );
    final endDate = _historyEndDate();
    if (endDate != null) {
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }

    try {
      final snapshot = await query
          .orderBy('timestamp', descending: false)
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .where((doc) => !_knownHistoryDocIds.contains(doc.id))
          .map(CachedSensorDataPoint.fromFirestore)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void _applyCachedHistory(
    List<CachedSensorDataPoint> cached, {
    bool keepPageIndex = false,
  }) {
    if (!mounted) return;

    final rangeEntries = _historyEntriesInRange(cached);
    final nextTotalRows = rangeEntries.length;
    final nextTotalPages =
        nextTotalRows == 0 ? 1 : ((nextTotalRows - 1) ~/ _pageSize) + 1;
    final nextPageIndex =
        keepPageIndex ? _pageIndex.clamp(0, nextTotalPages - 1).toInt() : 0;
    final pageEntries = [...rangeEntries]
      ..sort((a, b) => b.data.time.compareTo(a.data.time));
    final pageSlice = pageEntries
        .skip(nextPageIndex * _pageSize)
        .take(_pageSize)
        .toList(growable: false);
    final nextRangeData =
        rangeEntries.map((entry) => entry.data).toList(growable: false);

    setState(() {
      _knownHistoryDocIds
        ..clear()
        ..addAll(cached.map((entry) => entry.id));
      _pageDocIds
        ..clear()
        ..addAll(pageSlice.map((entry) => entry.id));
      _pageIndex = nextPageIndex;
      _totalRows = nextTotalRows;
      _latestHistorySyncTime =
          rangeEntries.isEmpty ? null : rangeEntries.last.data.time;
      _rangeData = nextRangeData;
      _data = _applySampling(nextRangeData);
      _pageData = pageSlice.map((entry) => entry.data).toList(growable: false);
    });
  }

  Future<List<SensorDataPoint>> _loadExportData() async {
    return _historyEntriesInRange(await _offlineCache.loadSensorHistory())
        .map((entry) => entry.data)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<void> _confirmDeleteCurrentHistoryRange() async {
    if (_isDeletingHistory) return;

    final rangeLabel = _selectedRangeLabel;
    final confirmed = await _showDeleteConfirmation(
      title: 'Hapus histori $rangeLabel?',
      message:
          'Semua data historis sensor pada $rangeLabel akan dihapus permanen. Aksi ini tidak bisa dibatalkan.',
      confirmLabel: 'Hapus Histori',
    );

    if (!confirmed || !mounted) return;

    setState(() => _isDeletingHistory = true);

    try {
      await _latestSubscription?.cancel();
      _latestSubscription = null;

      final deletedCount = await _deleteHistoryRange();
      if (!mounted) return;

      await _refreshHistory();
      if (!mounted) return;

      _showHistorySnackBar(
        deletedCount == 0
            ? 'Tidak ada histori $rangeLabel yang perlu dihapus.'
            : '$deletedCount histori $rangeLabel berhasil dihapus.',
        backgroundColor: AppTheme.primaryGreen,
      );
    } catch (e) {
      if (!mounted) return;
      _showHistorySnackBar(
        'Gagal menghapus histori: $e',
        backgroundColor: AppTheme.statusHigh,
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingHistory = false);
      }
    }
  }

  Future<int> _deleteHistoryRange() async {
    var deletedCount = 0;
    while (true) {
      final snapshot = await _historyBaseQuery()
          .orderBy('timestamp', descending: false)
          .limit(500)
          .get();

      if (snapshot.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      deletedCount += snapshot.docs.length;
      if (snapshot.docs.length < 500) break;
    }

    await _offlineCache.removeSensorHistoryWhere(
      (item) => _isInHistoryRange(item.data.time),
    );

    return deletedCount;
  }

  Future<void> _exportHistory(_HistoryExportFormat format) async {
    if (_isExportingHistory) return;

    setState(() => _isExportingHistory = true);
    try {
      final exportData = await _loadExportData();
      if (exportData.isEmpty) {
        _showHistorySnackBar('Tidak ada data historis untuk diekspor.');
        return;
      }

      final savedPath = await _writeExportFile(format, exportData);
      if (!mounted) return;

      _showHistorySnackBar(
        'Data Historis Tersimpan: $savedPath',
      );
    } catch (e) {
      if (!mounted) return;
      _showHistorySnackBar(
        'Gagal mengekspor data historis: $e',
        backgroundColor: AppTheme.statusHigh,
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingHistory = false);
      }
    }
  }

  Future<String> _writeExportFile(
    _HistoryExportFormat format,
    List<SensorDataPoint> exportData,
  ) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final range = _selectedRangeFileToken;
    final extension = switch (format) {
      _HistoryExportFormat.pdf => 'pdf',
      _HistoryExportFormat.csv => 'csv',
      _HistoryExportFormat.excel => 'xlsx',
    };
    final fileName = 'nutrixense_history_${range}_$timestamp.$extension';
    final Uint8List bytes;
    switch (format) {
      case _HistoryExportFormat.pdf:
        bytes = await _buildPdfBytes(exportData);
        break;
      case _HistoryExportFormat.csv:
        bytes = Uint8List.fromList(utf8.encode(_buildCsv(exportData)));
        break;
      case _HistoryExportFormat.excel:
        bytes = Uint8List.fromList(_buildXlsx(exportData));
        break;
    }

    if (Platform.isAndroid) {
      final savedPath =
          await _downloadsChannel.invokeMethod<String>('saveFileToDownloads', {
        'fileName': fileName,
        'mimeType': _mimeType(format),
        'bytes': bytes,
      });

      if (savedPath != null && savedPath.isNotEmpty) {
        return savedPath;
      }
    }

    final directory = await _exportDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String _mimeType(_HistoryExportFormat format) {
    return switch (format) {
      _HistoryExportFormat.pdf => 'application/pdf',
      _HistoryExportFormat.csv => 'text/csv',
      _HistoryExportFormat.excel =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
  }

  Future<Directory> _exportDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;

    final external = await getExternalStorageDirectory();
    if (external != null) return external;

    return getApplicationDocumentsDirectory();
  }

  String _buildCsv(List<SensorDataPoint> exportData) {
    final buffer = StringBuffer();
    buffer.writeln(_historyTableHeaders.map(_csvCell).join(','));

    for (final item in exportData) {
      buffer.writeln(_exportRow(item).map(_csvCell).join(','));
    }

    return buffer.toString();
  }

  List<int> _buildXlsx(List<SensorDataPoint> exportData) {
    final archive = Archive();

    void addTextFile(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addTextFile(
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''',
    );
    addTextFile(
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''',
    );
    addTextFile(
      'xl/_rels/workbook.xml.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''',
    );
    addTextFile(
      'xl/workbook.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="History" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''',
    );
    addTextFile(
      'xl/styles.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>''',
    );

    final rows = StringBuffer()
      ..writeln('<row r="1">${_xlsxHeaderCells(_historyTableHeaders)}</row>');

    for (var rowIndex = 0; rowIndex < exportData.length; rowIndex++) {
      final rowNumber = rowIndex + 2;
      final row = _exportRow(exportData[rowIndex]);
      rows.writeln(
        '<row r="$rowNumber">'
        '${_xlsxStringCell('A', rowNumber, row[0])}'
        '${_xlsxNumberCell('B', rowNumber, row[1])}'
        '${_xlsxNumberCell('C', rowNumber, row[2])}'
        '${_xlsxNumberCell('D', rowNumber, row[3])}'
        '${_xlsxNumberCell('E', rowNumber, row[4])}'
        '${_xlsxNumberCell('F', rowNumber, row[5])}'
        '${_xlsxNumberCell('G', rowNumber, row[6])}'
        '${_xlsxNumberCell('H', rowNumber, row[7])}'
        '</row>',
      );
    }

    addTextFile(
      'xl/worksheets/sheet1.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>
    <col min="1" max="1" width="18" customWidth="1"/>
    <col min="2" max="8" width="16" customWidth="1"/>
  </cols>
  <sheetData>
    $rows
  </sheetData>
</worksheet>''',
    );

    return ZipEncoder().encode(archive);
  }

  String _xlsxHeaderCells(List<String> headers) {
    const columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
    return List.generate(
      headers.length,
      (index) => _xlsxStringCell(columns[index], 1, headers[index], style: 1),
    ).join();
  }

  String _xlsxStringCell(
    String column,
    int row,
    String value, {
    int style = 0,
  }) {
    return '<c r="$column$row" t="inlineStr" s="$style"><is><t>${_xmlEscape(value)}</t></is></c>';
  }

  String _xlsxNumberCell(String column, int row, String value) {
    return '<c r="$column$row"><v>$value</v></c>';
  }

  Future<Uint8List> _buildPdfBytes(List<SensorDataPoint> exportData) async {
    final document = pw.Document(
      title: 'NutriXense Historical Sensor Data',
      author: 'NutriXense',
    );
    final chartData = _samplePdfData(exportData);
    final tableData = _samplePdfData(exportData);
    final isSampledPdf = tableData.length < exportData.length;
    final logoData = await rootBundle
        .load('assets/images/New_NutriXense Letter Logo v1.png');
    final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        maxPages: _pdfMaxPages,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          _buildPdfReportHeader(logoImage),
          pw.SizedBox(height: 18),
          pw.Text(
            'Grafik Tren Per Indikator',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            isSampledPdf
                ? 'PDF menampilkan sampel ${chartData.length} dari ${exportData.length} data agar laporan tetap ringan. Data lengkap tersedia melalui ekspor CSV atau XLSX.'
                : 'Setiap indikator ditampilkan pada grafik terpisah dengan skala nilainya masing-masing.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 8),
          ..._buildPdfTrendCharts(chartData),
          pw.SizedBox(height: 20),
          pw.Text(
            'Tabel Data Historis',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (isSampledPdf) ...[
            _buildPdfSampleNotice(exportData.length, tableData.length),
            pw.SizedBox(height: 8),
          ],
          pw.TableHelper.fromTextArray(
            headers: _historyTableHeaders,
            data: tableData.map(_exportRow).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor(0.14, 0.48, 0.35)),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            cellAlignments: const {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
          ),
        ],
      ),
    );

    return document.save();
  }

  List<SensorDataPoint> _samplePdfData(List<SensorDataPoint> source) {
    if (source.length <= _pdfMaxSampleRows) return source;
    if (_pdfMaxSampleRows <= 1) return [source.first];

    final sampled = <SensorDataPoint>[];
    var lastIndex = -1;
    final lastSourceIndex = source.length - 1;
    final lastSampleIndex = _pdfMaxSampleRows - 1;

    for (var index = 0; index < _pdfMaxSampleRows; index++) {
      final sourceIndex = ((index * lastSourceIndex) / lastSampleIndex).round();
      if (sourceIndex == lastIndex) continue;
      sampled.add(source[sourceIndex]);
      lastIndex = sourceIndex;
    }

    if (sampled.last != source.last) {
      sampled[sampled.length - 1] = source.last;
    }

    return sampled;
  }

  pw.Widget _buildPdfSampleNotice(int totalRows, int sampledRows) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green200, width: 0.6),
      ),
      child: pw.Text(
        'Catatan: PDF ini menampilkan $sampledRows sampel representatif dari $totalRows baris data historis. Untuk arsip lengkap tanpa sampling, gunakan ekspor CSV atau XLSX.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.green900),
      ),
    );
  }

  pw.Widget _buildPdfReportHeader(pw.MemoryImage logoImage) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Image(logoImage, width: 145, fit: pw.BoxFit.contain),
        pw.SizedBox(width: 18),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Historical Sensor Data',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Filter: $_selectedRangeLabel',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Text(
              'Dibuat: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    );
  }

  List<pw.Widget> _buildPdfTrendCharts(List<SensorDataPoint> chartData) {
    final series = _pdfTrendSeries(chartData);
    if (chartData.isEmpty || series.isEmpty) {
      return [
        pw.Container(
          height: 120,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
          ),
          child: pw.Text(
            'Tidak ada data grafik.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      ];
    }

    return series.map(_buildPdfTrendChart).toList();
  }

  pw.Widget _buildPdfTrendChart(
    _PdfTrendSeries series,
  ) {
    return pw.Container(
      height: 185,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                width: 18,
                height: 4,
                color: _pdfWidgetColor(series.color),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                series.label,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.SizedBox(
            height: 136,
            child: pw.SvgImage(svg: _buildTrendSvg(series)),
          ),
        ],
      ),
    );
  }

  List<_PdfTrendSeries> _pdfTrendSeries(List<SensorDataPoint> chartData) {
    return [
      _PdfTrendSeries(
        'Estimasi Nitrogen (mg/kg)',
        AppTheme.primaryGreen,
        chartData.map((item) => item.nitrogen).toList(),
      ),
      _PdfTrendSeries(
        'Estimasi Fosfor (mg/kg)',
        AppTheme.primaryBlue,
        chartData.map((item) => item.phosphorus).toList(),
      ),
      _PdfTrendSeries(
        'Estimasi Kalium (mg/kg)',
        AppTheme.statusHigh,
        chartData.map((item) => item.potassium).toList(),
      ),
      _PdfTrendSeries(
        'pH',
        const Color(0xFF7B1FA2),
        chartData.map((item) => item.ph).toList(),
      ),
      _PdfTrendSeries(
        'Kelembapan (%)',
        AppTheme.lightBlue,
        chartData.map((item) => item.moisture).toList(),
      ),
      _PdfTrendSeries(
        'Suhu (C)',
        AppTheme.statusLow,
        chartData.map((item) => item.temperature).toList(),
      ),
      _PdfTrendSeries(
        'EC (mS/cm)',
        AppTheme.statusNormal,
        chartData.map((item) => item.ec).toList(),
      ),
    ];
  }

  List<String> get _historyTableHeaders => const [
        'Waktu',
        'Estimasi Nitrogen (mg/kg)',
        'Estimasi Fosfor (mg/kg)',
        'Estimasi Kalium (mg/kg)',
        'pH',
        'Kelembapan (%)',
        'Suhu (C)',
        'EC (mS/cm)',
      ];

  String _buildTrendSvg(_PdfTrendSeries series) {
    const width = 760.0;
    const height = 240.0;
    const plotX = 52.0;
    const plotY = 14.0;
    const plotWidth = 682.0;
    const plotHeight = 176.0;
    final maxY =
        series.values.fold(0.0, (max, value) => value > max ? value : max);
    final chartMaxY = maxY <= 0 ? 1.0 : maxY * 1.08;
    final grid = StringBuffer();

    for (var i = 0; i <= 4; i++) {
      final y = plotY + (plotHeight * i / 4);
      final labelValue = chartMaxY * (1 - i / 4);
      grid
        ..writeln(
            '<line x1="$plotX" y1="$y" x2="${plotX + plotWidth}" y2="$y" stroke="#E5E7EB" stroke-width="1"/>')
        ..writeln(
            '<text x="4" y="${y + 3}" font-size="11" fill="#64748B">${_chartAxisLabel(labelValue)}</text>');
    }

    return '''
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">
  <rect x="0" y="0" width="$width" height="$height" fill="#FFFFFF"/>
  $grid
  <line x1="$plotX" y1="${plotY + plotHeight}" x2="${plotX + plotWidth}" y2="${plotY + plotHeight}" stroke="#94A3B8" stroke-width="1.2"/>
  <line x1="$plotX" y1="$plotY" x2="$plotX" y2="${plotY + plotHeight}" stroke="#94A3B8" stroke-width="1.2"/>
  ${_svgSeriesPolyline(series, chartMaxY, plotX, plotY, plotWidth, plotHeight)}
</svg>''';
  }

  String _svgSeriesPolyline(
    _PdfTrendSeries series,
    double maxY,
    double plotX,
    double plotY,
    double plotWidth,
    double plotHeight,
  ) {
    final values = series.values;
    if (values.isEmpty) return '';
    final safeMax = maxY <= 0 ? 1.0 : maxY;
    final color = _svgColor(series.color);

    if (values.length == 1) {
      final y = plotY + plotHeight - ((values.first / safeMax) * plotHeight);
      return '<circle cx="$plotX" cy="$y" r="4" fill="$color"/>';
    }

    final points = List.generate(values.length, (index) {
      final x = plotX + (plotWidth * index / (values.length - 1));
      final y = plotY + plotHeight - ((values[index] / safeMax) * plotHeight);
      return '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
    }).join(' ');

    return '<polyline points="$points" fill="none" stroke="$color" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>';
  }

  String _chartAxisLabel(double value) {
    if (value >= 100) return value.toStringAsFixed(0);
    if (value >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  List<String> _exportRow(SensorDataPoint item) {
    return [
      DateFormat('dd-MM-yyyy HH:mm').format(item.time),
      item.nitrogen.toStringAsFixed(1),
      item.phosphorus.toStringAsFixed(1),
      item.potassium.toStringAsFixed(1),
      item.ph.toStringAsFixed(1),
      item.moisture.toStringAsFixed(1),
      item.temperature.toStringAsFixed(1),
      item.ec.toStringAsFixed(2),
    ];
  }

  String _csvCell(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  String _xmlEscape(String value) {
    return const HtmlEscape().convert(value);
  }

  String _svgColor(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  PdfColor _pdfWidgetColor(Color color) {
    return PdfColor(color.red / 255, color.green / 255, color.blue / 255);
  }

  Future<bool> _showDeleteConfirmation({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusHigh,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _showHistorySnackBar(
    String message, {
    Color backgroundColor = AppTheme.primaryGreen,
  }) {
    if (!mounted) return;

    showAppTextSnackBar(
      context,
      message,
      backgroundColor,
    );
  }

  Future<void> _handleFilterTap(int index) async {
    if (index == _customFilterIndex) {
      await _showCustomFilterDialog();
      return;
    }

    if (_selectedFilter == index) return;
    setState(() => _selectedFilter = index);
    await _refreshHistory();
  }

  Future<void> _showCustomFilterDialog() async {
    final now = DateTime.now();
    final initialEnd = _customEndDate ?? now;
    final initialStart =
        _customStartDate ?? initialEnd.subtract(const Duration(days: 1));

    final result = await showDialog<_HistoryDateRange>(
      context: context,
      builder: (dialogContext) {
        var start = DateTime(
          initialStart.year,
          initialStart.month,
          initialStart.day,
          initialStart.hour,
          initialStart.minute,
        );
        var end = DateTime(
          initialEnd.year,
          initialEnd.month,
          initialEnd.day,
          initialEnd.hour,
          initialEnd.minute,
        );

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDate({
              required bool isStart,
            }) async {
              final current = isStart ? start : end;
              final picked = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(2020),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (picked == null) return;

              setDialogState(() {
                final next = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  current.hour,
                  current.minute,
                );
                if (isStart) {
                  start = next;
                } else {
                  end = next;
                }
              });
            }

            Future<void> pickTime({
              required bool isStart,
            }) async {
              final current = isStart ? start : end;
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(current),
              );
              if (picked == null) return;

              setDialogState(() {
                final next = DateTime(
                  current.year,
                  current.month,
                  current.day,
                  picked.hour,
                  picked.minute,
                );
                if (isStart) {
                  start = next;
                } else {
                  end = next;
                }
              });
            }

            Widget dateTimeRow({
              required String label,
              required DateTime value,
              required VoidCallback onDateTap,
              required VoidCallback onTimeTap,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDialogDateTimeButton(
                          icon: Icons.calendar_month_rounded,
                          label: DateFormat('dd/MM/yyyy').format(value),
                          onTap: onDateTap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 112,
                        child: _buildDialogDateTimeButton(
                          icon: Icons.schedule_rounded,
                          label: DateFormat('HH:mm').format(value),
                          onTap: onTimeTap,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: const Row(
                children: [
                  Icon(
                    Icons.filter_alt_rounded,
                    color: AppTheme.primaryGreen,
                  ),
                  SizedBox(width: 8),
                  Text('Filter Timestamp'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dateTimeRow(
                      label: 'Mulai',
                      value: start,
                      onDateTap: () => pickDate(isStart: true),
                      onTimeTap: () => pickTime(isStart: true),
                    ),
                    const SizedBox(height: 14),
                    dateTimeRow(
                      label: 'Sampai',
                      value: end,
                      onDateTap: () => pickDate(isStart: false),
                      onTimeTap: () => pickTime(isStart: false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () {
                    final normalizedStart = DateTime(
                      start.year,
                      start.month,
                      start.day,
                      start.hour,
                      start.minute,
                    );
                    final normalizedEnd = DateTime(
                      end.year,
                      end.month,
                      end.day,
                      end.hour,
                      end.minute,
                      59,
                      999,
                    );

                    Navigator.of(dialogContext).pop(
                      _HistoryDateRange(normalizedStart, normalizedEnd),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Terapkan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    if (!result.end.isAfter(result.start)) {
      _showHistorySnackBar(
        'Rentang filter tidak valid. Waktu akhir harus setelah waktu mulai.',
        backgroundColor: AppTheme.statusHigh,
      );
      return;
    }

    setState(() {
      _selectedFilter = _customFilterIndex;
      _customStartDate = result.start;
      _customEndDate = result.end;
    });
    await _refreshHistory();
  }

  Widget _buildDialogDateTimeButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.bgPrimary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> _sensors = [
    {'label': 'Est. NPK', 'icon': Icons.eco_rounded},
    {'label': 'pH', 'icon': Icons.science_rounded},
    {'label': 'Kelembapan', 'icon': Icons.water_drop_rounded},
    {'label': 'Suhu', 'icon': Icons.thermostat_rounded},
    {'label': 'EC', 'icon': Icons.bolt_rounded},
  ];

  // Build chart lines based on selected sensor
  List<LineChartBarData> get _chartLines {
    if (_data.isEmpty) return [];

    double xValueAtIndex(int index) {
      if (_selectedFilter == 0) {
        // Today → jam desimal (0–24)
        final time = _data[index].time;
        return time.hour + (time.minute / 60.0);
      }
      return index.toDouble();
    }

    List<FlSpot> toSpots(List<double> vals) {
      return List.generate(
        vals.length,
        (i) => FlSpot(xValueAtIndex(i), vals[i]),
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
      case 4: // EC
        return [
          _bar(toSpots(_data.map((d) => d.ec).toList()), AppTheme.statusNormal,
              'EC'),
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

    if (_selectedSensor == 0) {
      double avgOf(Iterable<double> values) =>
          values.reduce((a, b) => a + b) / values.length;
      double minOf(Iterable<double> values) =>
          values.reduce((a, b) => a < b ? a : b);
      double maxOf(Iterable<double> values) =>
          values.reduce((a, b) => a > b ? a : b);

      String npkValue({
        required double nitrogen,
        required double phosphorus,
        required double potassium,
      }) {
        return 'N ${nitrogen.toStringAsFixed(1)} mg/kg\n'
            'P ${phosphorus.toStringAsFixed(1)} mg/kg\n'
            'K ${potassium.toStringAsFixed(1)} mg/kg';
      }

      return [
        _StatItem(
          'Rata-rata',
          npkValue(
            nitrogen: avgOf(_data.map((d) => d.nitrogen)),
            phosphorus: avgOf(_data.map((d) => d.phosphorus)),
            potassium: avgOf(_data.map((d) => d.potassium)),
          ),
          AppTheme.primaryGreen,
        ),
        _StatItem(
          'Minimal',
          npkValue(
            nitrogen: minOf(_data.map((d) => d.nitrogen)),
            phosphorus: minOf(_data.map((d) => d.phosphorus)),
            potassium: minOf(_data.map((d) => d.potassium)),
          ),
          AppTheme.primaryBlue,
        ),
        _StatItem(
          'Maksimal',
          npkValue(
            nitrogen: maxOf(_data.map((d) => d.nitrogen)),
            phosphorus: maxOf(_data.map((d) => d.phosphorus)),
            potassium: maxOf(_data.map((d) => d.potassium)),
          ),
          AppTheme.statusHigh,
        ),
      ];
    }

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
      case 3:
        vals = _data.map((d) => d.temperature).toList();
        unit = '°C';
        break;
      default:
        vals = _data.map((d) => d.ec).toList();
        unit = 'mS/cm';
    }

    final avg = vals.reduce((a, b) => a + b) / vals.length;
    final min = vals.reduce((a, b) => a < b ? a : b);
    final max = vals.reduce((a, b) => a > b ? a : b);

    return [
      _StatItem('Rata-rata', '${avg.toStringAsFixed(1)} $unit',
          AppTheme.primaryGreen),
      _StatItem('Min', '${min.toStringAsFixed(1)} $unit', AppTheme.primaryBlue),
      _StatItem('Max', '${max.toStringAsFixed(1)} $unit', AppTheme.statusHigh),
    ];
  }

  Widget _buildExportMenu() {
    if (_isExportingHistory) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return PopupMenuButton<_HistoryExportFormat>(
      tooltip: 'Download data historis',
      icon: const Icon(
        Icons.download_rounded,
        color: AppTheme.primaryGreen,
      ),
      onSelected: _exportHistory,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _HistoryExportFormat.pdf,
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, size: 18),
              SizedBox(width: 10),
              Text('PDF'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _HistoryExportFormat.csv,
          child: Row(
            children: [
              Icon(Icons.table_chart_rounded, size: 18),
              SizedBox(width: 10),
              Text('CSV'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _HistoryExportFormat.excel,
          child: Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 18),
              SizedBox(width: 10),
              Text('Excel (.xlsx)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteHistoryButton() {
    if (_isDeletingHistory) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Hapus histori $_selectedRangeLabel',
      onPressed: _isLoadingHistory ? null : _confirmDeleteCurrentHistoryRange,
      icon: const Icon(
        Icons.delete_sweep_outlined,
        color: AppTheme.statusHigh,
      ),
    );
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
            actions: [
              _buildDeleteHistoryButton(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildExportMenu(),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: List.generate(
                    _filters.length,
                    (i) => Expanded(
                      child: GestureDetector(
                        onTap: () => _handleFilterTap(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: EdgeInsets.only(
                              right: i < _filters.length - 1 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedFilter == i
                                ? AppTheme.primaryGreen
                                : AppTheme.bgPrimary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (i == _customFilterIndex) ...[
                                  Icon(
                                    Icons.filter_alt_rounded,
                                    size: 15,
                                    color: _selectedFilter == i
                                        ? Colors.white
                                        : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
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
                              ],
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
                                'Tidak ada data riwayat tersedia',
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
                                      onTap: () => setState(() {
                                        _selectedSensor = i;
                                        _data = _applySampling(_rangeData);
                                      }),
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
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 330;
                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: _stats
                                        .map(
                                          (s) => SizedBox(
                                            width: narrow ||
                                                    _selectedSensor == 0
                                                ? constraints.maxWidth
                                                : (constraints.maxWidth - 20) /
                                                    3,
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color:
                                                    s.color.withOpacity(0.08),
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
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    s.value,
                                                    maxLines:
                                                        _selectedSensor == 0
                                                            ? 3
                                                            : 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize:
                                                          _selectedSensor == 0
                                                              ? 12
                                                              : 14,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: s.color,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  );
                                },
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
                                       child: ClipRect(
                                         child: LineChart(
                                           LineChartData(
                                             clipData: const FlClipData.all(),
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
                                                  _formatYAxisLabel(v),
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
                                                    : _chartXAxisInterval,
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

                                                  final idx = v.toInt().clamp(
                                                      0, _data.length - 1);
                                                  return Text(
                                                    _formatChartXAxisLabel(
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
                                   ),

                                    // Legend
                                    if (_selectedSensor == 0) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        runSpacing: 8,
                                        children: [
                                          _legend('Est. Nitrogen',
                                              AppTheme.primaryGreen),
                                          const SizedBox(width: 16),
                                          _legend('Est. Fosfor',
                                              AppTheme.primaryBlue),
                                          const SizedBox(width: 16),
                                          _legend('Est. Kalium',
                                              AppTheme.statusHigh),
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

  double get _chartXAxisInterval {
    if (_data.length <= 4) return 1;
    return (_data.length / 4).ceilToDouble();
  }

  String _formatChartXAxisLabel(DateTime time) {
    final startDate = _historyStartDate();
    final endDate = _historyEndDate() ?? DateTime.now();
    final duration = endDate.isAfter(startDate)
        ? endDate.difference(startDate)
        : const Duration(hours: 1);

    if (duration <= const Duration(days: 1)) {
      return DateFormat('HH:mm').format(time);
    }
    if (duration <= const Duration(days: 31)) {
      return DateFormat('d/M').format(time);
    }
    return DateFormat('d/M/yy').format(time);
  }

  String _formatYAxisLabel(double value) {
    if (_selectedSensor == 4) return value.toStringAsFixed(1);
    return value.toInt().toString();
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
    const headers = ['Time', 'N', 'P', 'K', 'pH', 'Kelembapan', 'Suhu', 'EC'];
    const columnWidths = [76.0, 44.0, 44.0, 44.0, 44.0, 70.0, 46.0, 44.0];
    const tableHorizontalPadding = 12.0;
    final tableWidth = columnWidths.fold<double>(
      tableHorizontalPadding * 2,
      (total, width) => total + width,
    );

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
          LayoutBuilder(
            builder: (context, constraints) {
              Widget tableCell(
                String text, {
                required double width,
                required TextStyle style,
                TextAlign textAlign = TextAlign.center,
              }) {
                return SizedBox(
                  width: width,
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: textAlign,
                    style: style,
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      Container(
                        color: AppTheme.bgPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: tableHorizontalPadding,
                          vertical: 8,
                        ),
                        child: Row(
                          children: List.generate(headers.length, (index) {
                            return tableCell(
                              headers[index],
                              width: columnWidths[index],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textLight,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      ...displayed.map((d) {
                        final values = [
                          d.nitrogen,
                          d.phosphorus,
                          d.potassium,
                          d.ph,
                          d.moisture,
                          d.temperature,
                          d.ec,
                        ];

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: tableHorizontalPadding,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.withOpacity(0.08),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: List.generate(headers.length, (index) {
                              final texts = [
                                DateFormat('dd/MM HH:mm').format(d.time),
                                ...values
                                    .map((value) => value.toStringAsFixed(1)),
                              ];
                              final isTime = index == 0;

                              return tableCell(
                                texts[index],
                                width: columnWidths[index],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isTime
                                      ? AppTheme.textSecondary
                                      : AppTheme.textPrimary,
                                  fontWeight: isTime
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
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
              Flexible(
                child: Text(
                  'Page ${_pageIndex + 1} / $_totalPages',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

class _HistoryDateRange {
  const _HistoryDateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class _PdfTrendSeries {
  final String label;
  final Color color;
  final List<double> values;

  const _PdfTrendSeries(this.label, this.color, this.values);
}
