import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sensor_data.dart';

class OfflineDataCacheService {
  OfflineDataCacheService._();

  static final OfflineDataCacheService instance = OfflineDataCacheService._();

  static const int _maxHistoryEntries = 20000;
  static const int _maxLogEntries = 1000;

  Future<List<CachedSensorDataPoint>> loadSensorHistory() async {
    final items = await _readList('sensor_history.json');
    return items
        .whereType<Map>()
        .map((item) => CachedSensorDataPoint.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .whereType<CachedSensorDataPoint>()
        .toList()
      ..sort((a, b) => a.data.time.compareTo(b.data.time));
  }

  Future<List<CachedSensorDataPoint>> mergeSensorHistory(
    Iterable<CachedSensorDataPoint> incoming,
  ) async {
    final byId = {
      for (final item in await loadSensorHistory()) item.id: item,
    };

    for (final item in incoming) {
      byId[item.id] = item;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => a.data.time.compareTo(b.data.time));
    final trimmed = merged.length > _maxHistoryEntries
        ? merged.sublist(merged.length - _maxHistoryEntries)
        : merged;

    await _writeList(
      'sensor_history.json',
      trimmed.map((item) => item.toJson()).toList(growable: false),
    );

    return trimmed;
  }

  Future<List<CachedSensorDataPoint>> removeSensorHistoryWhere(
    bool Function(CachedSensorDataPoint item) test,
  ) async {
    final retained = (await loadSensorHistory())
        .where((item) => !test(item))
        .toList(growable: false);

    await _writeList(
      'sensor_history.json',
      retained.map((item) => item.toJson()).toList(growable: false),
    );

    return retained;
  }

  Future<List<CachedLogEntry>> loadLogs(String collectionPath) async {
    final items = await _readList(_logFileName(collectionPath));
    return items
        .whereType<Map>()
        .map((item) => CachedLogEntry.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .whereType<CachedLogEntry>()
        .toList()
      ..sort((a, b) => _compareDateDesc(a.createdAt, b.createdAt));
  }

  Future<List<CachedLogEntry>> mergeLogs(
    String collectionPath,
    Iterable<CachedLogEntry> incoming,
  ) async {
    final byId = {
      for (final item in await loadLogs(collectionPath)) item.id: item,
    };

    for (final item in incoming) {
      byId[item.id] = item;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => _compareDateDesc(a.createdAt, b.createdAt));
    final trimmed = merged.length > _maxLogEntries
        ? merged.take(_maxLogEntries).toList(growable: false)
        : merged;

    await _writeList(
      _logFileName(collectionPath),
      trimmed.map((item) => item.toJson()).toList(growable: false),
    );

    return trimmed;
  }

  Future<List<CachedLogEntry>> removeLog(
    String collectionPath,
    String id,
  ) async {
    final retained = (await loadLogs(collectionPath))
        .where((item) => item.id != id)
        .toList(growable: false);

    await _writeList(
      _logFileName(collectionPath),
      retained.map((item) => item.toJson()).toList(growable: false),
    );

    return retained;
  }

  Future<void> clearLogs(String collectionPath) async {
    await _writeList(_logFileName(collectionPath), const []);
  }

  Future<List<dynamic>> _readList(String fileName) async {
    final file = await _file(fileName);
    if (!await file.exists()) return const [];

    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is List) return decoded;
    } catch (_) {
      return const [];
    }

    return const [];
  }

  Future<void> _writeList(String fileName, List<Object?> items) async {
    final file = await _file(fileName);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(items), flush: true);
  }

  Future<File> _file(String fileName) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}offline_cache'
        '${Platform.pathSeparator}$fileName');
  }

  String _logFileName(String collectionPath) {
    return '${collectionPath.replaceAll(RegExp(r'[^a-zA-Z0-9_\\-]'), '_')}.json';
  }

  static int _compareDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}

class CachedSensorDataPoint {
  const CachedSensorDataPoint({
    required this.id,
    required this.data,
  });

  final String id;
  final SensorDataPoint data;

  factory CachedSensorDataPoint.fromFirestore(DocumentSnapshot doc) {
    return CachedSensorDataPoint(
      id: doc.id,
      data: SensorDataPoint.fromFirestore(doc),
    );
  }

  static CachedSensorDataPoint? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final data = json['data'];
    if (id is! String || data is! Map) return null;

    return CachedSensorDataPoint(
      id: id,
      data: SensorDataPoint.fromMap(Map<String, dynamic>.from(data)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'data': data.toJson(),
    };
  }
}

class CachedLogEntry {
  const CachedLogEntry({
    required this.id,
    required this.data,
    required this.createdAt,
  });

  final String id;
  final Map<String, dynamic> data;
  final DateTime? createdAt;

  factory CachedLogEntry.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return CachedLogEntry.fromDocumentSnapshot(doc);
  }

  factory CachedLogEntry.fromDocumentSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = _normalizeJsonMap(doc.data() ?? const {});
    return CachedLogEntry(
      id: doc.id,
      data: data,
      createdAt: _readDate(data['createdAt']),
    );
  }

  static CachedLogEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final data = json['data'];
    if (id is! String || data is! Map) return null;

    final normalizedData = Map<String, dynamic>.from(data);
    return CachedLogEntry(
      id: id,
      data: normalizedData,
      createdAt: _readDate(normalizedData['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'data': data,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

Map<String, dynamic> _normalizeJsonMap(Map<String, dynamic> source) {
  return source.map((key, value) => MapEntry(key, _normalizeJsonValue(value)));
}

Object? _normalizeJsonValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  if (value is Iterable) {
    return value.map(_normalizeJsonValue).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), _normalizeJsonValue(item)),
    );
  }

  return value.toString();
}

DateTime? _readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}
