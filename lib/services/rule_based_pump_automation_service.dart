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
    Duration checkInterval = const Duration(minutes: 1),
  }) {
    return RuleBasedPumpAutomationService._(
      firestore: firestore,
      checkInterval: checkInterval,
    );
  }

  RuleBasedPumpAutomationService._({
    FirebaseFirestore? firestore,
    this.checkInterval = const Duration(minutes: 1),
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

  final ValueNotifier<Set<int>> activeRelays = ValueNotifier(<int>{});

  bool get isRunning => false;

  Future<bool> loadEnabledPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledStorageKey) ?? false;
  }

  Future<void> setEnabledPreference(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledStorageKey, enabled);
  }

  Future<void> start({bool persist = true}) async {
    if (persist) {
      await setEnabledPreference(true);
    }
    await syncBackendDssConfig(enabled: true);
    await _backgroundChannel.invokeMethod<void>('startBackgroundMonitor', {
      'thresholdsJson': jsonEncode(_thresholdConfigService.all()),
    }).catchError((_) {});
  }

  Future<void> stop({bool persist = true}) async {
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
      'automationMode': 'fuzzy_logic',
      'fuzzyLogic': {
        'minPulseSeconds': 5,
        'mediumPulseSeconds': 12,
        'maxPulseSeconds': 30,
        'checkIntervalSeconds': checkInterval.inSeconds,
        'description':
            'Durasi pompa dihitung dari rasio kekurangan nutrisi terhadap ambang minimum menggunakan membership tipis, sedang, dan parah.',
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
