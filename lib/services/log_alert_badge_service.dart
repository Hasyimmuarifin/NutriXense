import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogAlertBadgeService {
  LogAlertBadgeService._();

  static final LogAlertBadgeService instance = LogAlertBadgeService._();
  static const String _alertLastSeenStorageKey =
      'nutrixense_threshold_alert_logs_last_seen_ms';
  static const String _pumpLastSeenStorageKey =
      'nutrixense_pump_activity_logs_last_seen_ms';

  final ValueNotifier<int> unreadPumpCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadAlertCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadLogCount = ValueNotifier<int>(0);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pumpSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestPumpDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestAlertDocs = [];
  int _pumpLastSeenMillis = 0;
  int _alertLastSeenMillis = 0;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final storedPumpLastSeen = prefs.getInt(_pumpLastSeenStorageKey);
    final storedAlertLastSeen = prefs.getInt(_alertLastSeenStorageKey);

    if (storedPumpLastSeen == null) {
      _pumpLastSeenMillis = nowMillis;
      await prefs.setInt(_pumpLastSeenStorageKey, _pumpLastSeenMillis);
    } else {
      _pumpLastSeenMillis = storedPumpLastSeen;
    }

    if (storedAlertLastSeen == null) {
      _alertLastSeenMillis = nowMillis;
      await prefs.setInt(_alertLastSeenStorageKey, _alertLastSeenMillis);
    } else {
      _alertLastSeenMillis = storedAlertLastSeen;
    }

    _pumpSubscription = _firestore
        .collection('pump_activity_logs')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      _latestPumpDocs = snapshot.docs;
      _recalculateUnreadCounts();
    }, onError: (Object error) {
      debugPrint('Pump log badge listener failed: $error');
    });

    _alertSubscription = _firestore
        .collection('threshold_alert_logs')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      _latestAlertDocs = snapshot.docs;
      _recalculateUnreadCounts();
    }, onError: (Object error) {
      debugPrint('Threshold alert badge listener failed: $error');
    });
  }

  Future<void> markPumpSeen() async {
    final newestMillis = _latestPumpDocs
        .map((doc) => _readDate(doc.data()['createdAt']))
        .whereType<DateTime>()
        .map((date) => date.millisecondsSinceEpoch)
        .fold<int>(_pumpLastSeenMillis, (current, next) {
      return next > current ? next : current;
    });

    _pumpLastSeenMillis = newestMillis;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pumpLastSeenStorageKey, _pumpLastSeenMillis);
    _recalculateUnreadCounts();
  }

  Future<void> markAlertsSeen() async {
    final newestMillis = _latestAlertDocs
        .map((doc) => _readDate(doc.data()['createdAt']))
        .whereType<DateTime>()
        .map((date) => date.millisecondsSinceEpoch)
        .fold<int>(_alertLastSeenMillis, (current, next) {
      return next > current ? next : current;
    });

    _alertLastSeenMillis = newestMillis;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_alertLastSeenStorageKey, _alertLastSeenMillis);
    _recalculateUnreadCounts();
  }

  Future<void> markAllSeen() async {
    await Future.wait([
      markPumpSeen(),
      markAlertsSeen(),
    ]);
  }

  void dispose() {
    _pumpSubscription?.cancel();
    _alertSubscription?.cancel();
    _pumpSubscription = null;
    _alertSubscription = null;
    _initialized = false;
  }

  void _recalculateUnreadCounts() {
    final pumpCount = _latestPumpDocs.where((doc) {
      final createdAt = _readDate(doc.data()['createdAt']);
      return createdAt != null &&
          createdAt.millisecondsSinceEpoch > _pumpLastSeenMillis;
    }).length;

    var alertCount = 0;

    for (final doc in _latestAlertDocs) {
      final createdAt = _readDate(doc.data()['createdAt']);
      if (createdAt == null ||
          createdAt.millisecondsSinceEpoch <= _alertLastSeenMillis) {
        continue;
      }

      alertCount += _alertCountForLog(doc.data());
    }

    unreadPumpCount.value = pumpCount;
    unreadAlertCount.value = alertCount;
    unreadLogCount.value = pumpCount + alertCount;
  }

  int _alertCountForLog(Map<String, dynamic> data) {
    final alerts = data['alerts'];
    if (alerts is List && alerts.isNotEmpty) return alerts.length;
    return 1;
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
