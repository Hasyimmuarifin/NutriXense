import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'threshold_config_service.dart';

class RuleBasedPumpAutomationService {
  static final RuleBasedPumpAutomationService instance =
      RuleBasedPumpAutomationService._();

  factory RuleBasedPumpAutomationService({
    FirebaseFirestore? firestore,
    Duration checkInterval = const Duration(minutes: 10),
  }) {
    return RuleBasedPumpAutomationService._(
      firestore: firestore,
      checkInterval: checkInterval,
    );
  }

  RuleBasedPumpAutomationService._({
    FirebaseFirestore? firestore,
    this.checkInterval = const Duration(minutes: 10),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final ThresholdConfigService _thresholdConfigService =
      ThresholdConfigService.instance;
  final Duration checkInterval;
  static const MethodChannel _backgroundChannel =
      MethodChannel('com.example.nutrixense/alerts');
  static const String _enabledStorageKey = 'nutrixense_dss_enabled';
  static const String _automationConfigCollection = 'automation_config';
  static const String _dssConfigDocument = 'dss';
  static const String _wateringSchedulesCollection = 'watering_schedules';
  static const String _dssFallbackDocument = '_dss_config';
  static const int _minPulseSeconds = 1;
  static const int _mediumPulseSeconds = 2;
  static const int _maxPulseSeconds = 3;
  static const Map<String, double> _defaultRecipeRelayRatios = {
    '1': 1,
    '2': 1,
    '3': 1,
  };

  final ValueNotifier<Set<int>> activeRelays = ValueNotifier(<int>{});

  bool _running = false;
  bool get isRunning => _running;

  Future<bool> loadEnabledPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _running = prefs.getBool(_enabledStorageKey) ?? false;
    return _running;
  }

  Future<void> setEnabledPreference(bool enabled) async {
    _running = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledStorageKey, enabled);
  }

  Future<void> start({bool persist = true}) async {
    _running = true;
    if (persist) {
      await setEnabledPreference(true);
    }
    await syncBackendDssConfig(enabled: true);
    await _backgroundChannel.invokeMethod<void>('startBackgroundMonitor', {
      'thresholdsJson': jsonEncode(_thresholdConfigService.all()),
    }).catchError((_) {});
  }

  Future<void> stop({bool persist = true}) async {
    _running = false;
    if (persist) {
      await setEnabledPreference(false);
    }
    _stopNativeBackgroundMonitor();
    stopInAppChecks();
  }

  void stopInAppChecks() {
    activeRelays.value = <int>{};
  }

  void syncNativeThresholds() {
    unawaited(syncBackendDssConfig());
    unawaited(
      _backgroundChannel.invokeMethod<void>('syncBackgroundThresholds', {
        'thresholdsJson': jsonEncode(_thresholdConfigService.all()),
      }).catchError((_) {}),
    );
  }

  void syncNativeSchedules(String schedulesJson) {
    unawaited(
      _backgroundChannel.invokeMethod<void>('syncBackgroundSchedules', {
        'schedulesJson': schedulesJson,
      }).catchError((_) {}),
    );
  }

  Future<bool> syncBackendDssConfig({bool? enabled}) async {
    final payload = {
      if (enabled != null) 'enabled': enabled,
      'thresholds': _thresholdConfigService.all(),
      'minPulseMs': _minPulseSeconds * 1000,
      'mediumPulseMs': _mediumPulseSeconds * 1000,
      'maxPulseMs': _maxPulseSeconds * 1000,
      'cooldownMs': FieldValue.delete(),
      'automationMode': 'ec_recipe_dosing',
      'sensorInterpretation': {
        'npk': 'estimated_trend',
        'primaryNutrientControl': 'electrical_conductivity',
        'description':
            'Nilai N/P/K dari sensor RS485 diperlakukan sebagai estimasi/tren berbasis EC. Kontrol otomatis pompa N/P/K memakai resep larutan saat EC rendah, bukan pembacaan unsur N/P/K terpisah.',
      },
      'recipeDosing': {
        'trigger': 'ec_low',
        'relayRatios': _defaultRecipeRelayRatios,
        'relayLabels': {
          '1': 'Pompa A - Larutan Nitrogen (N)',
          '2': 'Pompa B - Larutan Fosfor (P)',
          '3': 'Pompa C - Larutan Kalium (K)',
        },
      },
      'fuzzyLogic': {
        'minPulseSeconds': _minPulseSeconds,
        'mediumPulseSeconds': _mediumPulseSeconds,
        'maxPulseSeconds': _maxPulseSeconds,
        'cooldownSeconds': FieldValue.delete(),
        'checkIntervalSeconds': checkInterval.inSeconds,
        'description':
            'Durasi pompa otomatis mengikuti fuzzy: Minimum 1 detik, Sedang 2 detik, Maksimum 3 detik. Setiap pompa dinyalakan secara bergantian (sequential) untuk mencegah lonjakan arus listrik.',
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final primarySynced = await _safeSetDssConfig(
      _automationConfigCollection,
      _dssConfigDocument,
      payload,
    );
    final fallbackSynced = await _safeSetDssConfig(
      _wateringSchedulesCollection,
      _dssFallbackDocument,
      payload,
    );

    return primarySynced || fallbackSynced;
  }

  Future<bool> _safeSetDssConfig(
    String collection,
    String document,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _firestore
          .collection(collection)
          .doc(document)
          .set(payload, SetOptions(merge: true));
      return true;
    } catch (error) {
      debugPrint('DSS backend sync failed for $collection/$document: $error');
      return false;
    }
  }

  void _stopNativeBackgroundMonitor() {
    unawaited(
      _backgroundChannel
          .invokeMethod<void>('stopBackgroundMonitor')
          .catchError((_) {}),
    );
  }
}
