// Main monitoring dashboard – shows live sensor cards + mini real-time chart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sensor_data.dart';

import '../services/alert_count_service.dart';
import '../services/mqtt_service.dart';
import '../services/nutrient_alert_service.dart';
import '../services/rule_based_pump_automation_service.dart';
import '../services/threshold_config_service.dart';
import '../theme/app_theme.dart';

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
  static const String _automationConfigCollection = 'automation_config';
  static const String _dssConfigDocument = 'dss';

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
  Map<String, dynamic> _latestSensorData = const {};
  final Map<String, bool> _buzzerMuted = {
    'nitrogen': false,
    'phosphorus': false,
    'potassium': false,
    'ph': false,
    'moisture': false,
    'temperature': false,
    'ec': false,
  };

  final MQTTService mqttService = MQTTService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AlertCountService _alertCountService = AlertCountService.instance;
  final NutrientAlertService _nutrientAlertService =
      NutrientAlertService.instance;
  final ThresholdConfigService _thresholdConfigService =
      ThresholdConfigService.instance;

  StreamSubscription? sensorSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _buzzerConfigSub;
  final Map<String, TextEditingController> _thresholdControllers = {
    'min_nitrogen': TextEditingController(text: '80'),
    'max_nitrogen': TextEditingController(text: '180'),
    'min_phosphorus': TextEditingController(text: '100'),
    'max_phosphorus': TextEditingController(text: '300'),
    'min_potassium': TextEditingController(text: '250'),
    'max_potassium': TextEditingController(text: '650'),
    'min_ph': TextEditingController(text: '4.5'),
    'max_ph': TextEditingController(text: '5.5'),
    'min_moisture': TextEditingController(text: '40'),
    'max_moisture': TextEditingController(text: '70'),
    'min_temperature': TextEditingController(text: '18'),
    'max_temperature': TextEditingController(text: '25'),
    'min_ec': TextEditingController(text: '1.2'),
    'max_ec': TextEditingController(text: '2.5'),
  };

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

      if (status) {
        _publishBuzzerMuteConfig();
      }
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
    _readings = _buildReadingsFromData(const {});
  }

  void _syncThresholdControllersFromStorage() {
    final thresholds = _thresholdConfigService.all();
    for (final entry in _thresholdControllers.entries) {
      final storedValue = thresholds[entry.key];
      if (storedValue != null) {
        entry.value.text = storedValue.toString();
      }
    }
  }

  List<SensorReading> _buildReadingsFromData(Map<String, dynamic> data) {
    return [
      SensorReading(
        value: _readSensorValue(data, "nitrogen"),
        label: "Nitrogen",
        unit: "mg/kg",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_nitrogen', 180, 250),
        minNormal: _thresholdValue('min_nitrogen', 80),
        maxNormal: _thresholdValue('max_nitrogen', 180),
        icon: "assets/icons/leaf.png",
        colorHex: 0xFF4CAF50,
      ),
      SensorReading(
        value: _readSensorValue(data, "phosphorus"),
        label: "Fosfor",
        unit: "mg/kg",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_phosphorus', 300, 400),
        minNormal: _thresholdValue('min_phosphorus', 100),
        maxNormal: _thresholdValue('max_phosphorus', 300),
        icon: "assets/icons/root.png",
        colorHex: 0xFF2196F3,
      ),
      SensorReading(
        value: _readSensorValue(data, "potassium"),
        label: "Kalium",
        unit: "mg/kg",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_potassium', 650, 800),
        minNormal: _thresholdValue('min_potassium', 250),
        maxNormal: _thresholdValue('max_potassium', 650),
        icon: "assets/icons/crop.png",
        colorHex: 0xFFFF9800,
      ),
      SensorReading(
        value: _readSensorValue(data, "ph"),
        label: "pH Level",
        unit: "pH",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_ph', 5.5, 14),
        minNormal: _thresholdValue('min_ph', 4.5),
        maxNormal: _thresholdValue('max_ph', 5.5),
        icon: "assets/icons/ph.png",
        colorHex: 0xFF9E9E9E,
      ),
      SensorReading(
        value: _readSensorValue(data, "moisture"),
        label: "Kelembapan",
        unit: "%",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_moisture', 70, 100),
        minNormal: _thresholdValue('min_moisture', 40),
        maxNormal: _thresholdValue('max_moisture', 70),
        icon: "assets/icons/water.png",
        colorHex: 0xFF2196F3,
      ),
      SensorReading(
        value: _readSensorValue(data, "temperature"),
        label: "Suhu",
        unit: "°C",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_temperature', 25, 40),
        minNormal: _thresholdValue('min_temperature', 18),
        maxNormal: _thresholdValue('max_temperature', 25),
        icon: "assets/icons/temp.png",
        colorHex: 0xFFF44336,
      ),
      SensorReading(
        value: _readSensorValue(data, "ec"),
        label: "Electrical Conductivity",
        unit: "mS/cm",
        minValue: 0,
        maxValue: _gaugeMaxValue('max_ec', 2.5, 4),
        minNormal: _thresholdValue('min_ec', 1.2),
        maxNormal: _thresholdValue('max_ec', 2.5),
        icon: "assets/icons/ec.png",
        colorHex: 0xFF7C4DFF,
      ),
    ];
  }

  double _gaugeMaxValue(
    String maxNormalKey,
    double originalMaxNormal,
    double originalMaxValue,
  ) {
    final maxNormal = _thresholdValue(maxNormalKey, originalMaxNormal);
    final originalHeadroom = originalMaxValue - originalMaxNormal;
    return maxNormal + originalHeadroom;
  }

  double get _npkChartMaxY {
    return [
      _gaugeMaxValue('max_nitrogen', 180, 250),
      _gaugeMaxValue('max_phosphorus', 300, 400),
      _gaugeMaxValue('max_potassium', 650, 800),
    ].reduce((a, b) => a > b ? a : b);
  }

  double get _npkChartInterval => _npkChartMaxY / 5;

  double _thresholdValue(String key, double fallback) {
    return double.tryParse(_thresholdControllers[key]?.text.trim() ?? '') ??
        _thresholdConfigService.value(key, fallback);
  }

  double _readSensorValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  String _sensorKeyForReading(SensorReading reading) {
    switch (reading.label) {
      case 'Nitrogen':
        return 'nitrogen';
      case 'Fosfor':
        return 'phosphorus';
      case 'Kalium':
        return 'potassium';
      case 'pH Level':
        return 'ph';
      case 'Kelembapan':
        return 'moisture';
      case 'Suhu':
        return 'temperature';
      case 'Electrical Conductivity':
        return 'ec';
      default:
        return reading.label.toLowerCase().replaceAll(' ', '_');
    }
  }

  void _listenBuzzerMuteConfig() {
    _buzzerConfigSub = _firestore
        .collection(_automationConfigCollection)
        .doc(_dssConfigDocument)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      final rawConfig = data?['buzzerMuted'] ?? data?['buzzer_muted'];
      if (rawConfig is! Map) return;

      if (!mounted) return;
      setState(() {
        for (final key in sensorKeys) {
          final value = rawConfig[key];
          if (value is bool) {
            _buzzerMuted[key] = value;
          } else if (value is num) {
            _buzzerMuted[key] = value != 0;
          }
        }
      });
      unawaited(
        _nutrientAlertService.syncBackgroundAlertConfig(
          mutedSensorKeys: _mutedSensorKeys,
        ),
      );
    }, onError: (Object error) {
      debugPrint('Buzzer mute config listener failed: $error');
    });
  }

  Future<bool> _saveBuzzerMuteConfigToBackend() async {
    try {
      await _firestore
          .collection(_automationConfigCollection)
          .doc(_dssConfigDocument)
          .set(
        {
          'buzzerMuted': Map<String, bool>.from(_buzzerMuted),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (error) {
      debugPrint('Buzzer mute config sync failed: $error');
      return false;
    }
  }

  void _publishBuzzerMuteConfig() {
    if (!mqttService.isConnected) return;

    final payload = {
      ..._thresholdConfigService.all(),
      'buzzer_muted': Map<String, bool>.from(_buzzerMuted),
    };
    mqttService.publish('nutrixense/config', jsonEncode(payload), retain: true);
  }

  Future<void> _toggleBuzzerMute(String sensorKey) async {
    final nextMuted = !(_buzzerMuted[sensorKey] ?? false);

    setState(() {
      _buzzerMuted[sensorKey] = nextMuted;
    });

    final backendSynced = await _saveBuzzerMuteConfigToBackend();

    if (mqttService.isConnected) {
      _publishBuzzerMuteConfig();
    }
    unawaited(
      _nutrientAlertService.syncBackgroundAlertConfig(
        mutedSensorKeys: _mutedSensorKeys,
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          backendSynced
              ? nextMuted
                  ? 'Peringatan ${_sensorLabel(sensorKey)} dinonaktifkan'
                  : 'Peringatan ${_sensorLabel(sensorKey)} diaktifkan'
              : 'Status peringatan berubah di aplikasi, tetapi gagal disinkronkan ke backend.',
        ),
        backgroundColor: backendSynced
            ? nextMuted
                ? Colors.grey.shade700
                : AppTheme.primaryGreen
            : AppTheme.statusLow,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  String _sensorLabel(String sensorKey) {
    switch (sensorKey) {
      case 'ph':
        return 'pH';
      case 'ec':
        return 'EC';
      case 'nitrogen':
        return 'Nitrogen';
      case 'phosphorus':
        return 'Fosfor';
      case 'potassium':
        return 'Kalium';
      case 'moisture':
        return 'Kelembapan';
      case 'temperature':
        return 'Suhu';
      default:
        return sensorKey[0].toUpperCase() + sensorKey.substring(1);
    }
  }

  Set<String> get _mutedSensorKeys {
    return _buzzerMuted.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
  }

  void updateSensorData(Map<String, dynamic> data) {
    if (!mounted) return;

    final nextReadings = _buildReadingsFromData(data);

    setState(() {
      _latestSensorData = Map<String, dynamic>.from(data);
      totalSensors = sensorKeys.where((key) => data.containsKey(key)).length;
      _readings = nextReadings;

      // update chart history
      nitrogenHistory.add(_readSensorValue(data, "nitrogen"));
      phosphorusHistory.add(_readSensorValue(data, "phosphorus"));
      potassiumHistory.add(_readSensorValue(data, "potassium"));
      chartTimes.add(DateTime.now());

      if (nitrogenHistory.length > 1800) nitrogenHistory.removeAt(0);
      if (phosphorusHistory.length > 1800) phosphorusHistory.removeAt(0);
      if (potassiumHistory.length > 1800) potassiumHistory.removeAt(0);
      if (chartTimes.length > 1800) chartTimes.removeAt(0);
    });

    _alertCountService.updateFromSensorReadings(nextReadings);
    _nutrientAlertService.handleReadings(
      nextReadings,
      mutedSensorKeys: _mutedSensorKeys,
    );
  }

  Future<void> _openThresholdConfigDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final screenSize = mediaQuery.size;
        final maxDialogHeight = screenSize.height * 0.9;
        final horizontalInset = screenSize.width < 360 ? 10.0 : 20.0;
        final verticalInset = screenSize.height < 640 ? 10.0 : 24.0;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: verticalInset,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: maxDialogHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: AppTheme.primaryGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Konfigurasi Ambang Batas Normal',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      screenSize.width < 360 ? 12 : 20,
                      4,
                      screenSize.width < 360 ? 12 : 20,
                      8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryGreen.withOpacity(0.14),
                            ),
                          ),
                          child: const Text(
                            'Atur rentang minimal dan maksimal normal. Nilai yang berada di luar batas ini akan menjadi peringatan.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _thresholdRangeField(
                          'Nitrogen',
                          minKey: 'min_nitrogen',
                          maxKey: 'max_nitrogen',
                          suffix: 'mg/kg',
                        ),
                        _thresholdRangeField(
                          'Fosfor',
                          minKey: 'min_phosphorus',
                          maxKey: 'max_phosphorus',
                          suffix: 'mg/kg',
                        ),
                        _thresholdRangeField(
                          'Kalium',
                          minKey: 'min_potassium',
                          maxKey: 'max_potassium',
                          suffix: 'mg/kg',
                        ),
                        _thresholdRangeField(
                          'pH',
                          minKey: 'min_ph',
                          maxKey: 'max_ph',
                          suffix: 'pH',
                        ),
                        _thresholdRangeField(
                          'Kelembapan',
                          minKey: 'min_moisture',
                          maxKey: 'max_moisture',
                          suffix: '%',
                        ),
                        _thresholdRangeField(
                          'Suhu',
                          minKey: 'min_temperature',
                          maxKey: 'max_temperature',
                          suffix: '°C',
                        ),
                        _thresholdRangeField(
                          'EC',
                          minKey: 'min_ec',
                          maxKey: 'max_ec',
                          suffix: 'mS/cm',
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final saved = await _publishThresholdConfig();
                          if (!context.mounted) return;
                          if (saved) Navigator.of(context).pop();
                        },
                        child: const Text('Save Config'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _thresholdRangeField(
    String label, {
    required String minKey,
    required String maxKey,
    required String suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 320;
            final fieldPair = LayoutBuilder(
              builder: (context, fieldConstraints) {
                final stackInputs = fieldConstraints.maxWidth < 170;
                final minField = _thresholdField('Min', minKey, suffix);
                final maxField = _thresholdField('Max', maxKey, suffix);

                if (stackInputs) {
                  return Column(
                    children: [
                      minField,
                      const SizedBox(height: 6),
                      maxField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: minField),
                    const SizedBox(width: 6),
                    Expanded(child: maxField),
                  ],
                );
              },
            );

            final labelContent = Row(
              mainAxisSize: stackFields ? MainAxisSize.min : MainAxisSize.max,
              children: [
                const Icon(
                  Icons.sensors_rounded,
                  size: 14,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelContent,
                  const SizedBox(height: 7),
                  fieldPair,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 88, child: labelContent),
                const SizedBox(width: 8),
                Expanded(child: fieldPair),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _thresholdField(String label, String key, String suffix) {
    return Padding(
      padding: EdgeInsets.zero,
      child: TextField(
        controller: _thresholdControllers[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          prefixText: '$label ',
          prefixStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.textLight,
          ),
          suffixText: suffix,
          filled: true,
          fillColor: AppTheme.bgPrimary,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppTheme.primaryGreen,
              width: 1.4,
            ),
          ),
          isDense: true,
        ),
      ),
    );
  }

  Future<bool> _publishThresholdConfig() async {
    final payload = <String, double>{};

    for (final entry in _thresholdControllers.entries) {
      final value = double.tryParse(entry.value.text.trim());
      if (value == null) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nilai ${_thresholdDisplayLabel(entry.key)} tidak valid.',
            ),
            backgroundColor: AppTheme.statusLow,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;
      }
      payload[entry.key] = value;
    }

    final thresholdPairs = {
      'Nitrogen': ('min_nitrogen', 'max_nitrogen'),
      'Fosfor': ('min_phosphorus', 'max_phosphorus'),
      'Kalium': ('min_potassium', 'max_potassium'),
      'pH': ('min_ph', 'max_ph'),
      'Kelembapan': ('min_moisture', 'max_moisture'),
      'Suhu': ('min_temperature', 'max_temperature'),
      'EC': ('min_ec', 'max_ec'),
    };

    for (final entry in thresholdPairs.entries) {
      final minValue = payload[entry.value.$1]!;
      final maxValue = payload[entry.value.$2]!;

      if (minValue > maxValue) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'nilai minimal ${entry.key} harus kurang dari atau sama dengan nilai maksimal.'),
            backgroundColor: AppTheme.statusLow,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;
      }
    }

    await _thresholdConfigService.update(payload);
    RuleBasedPumpAutomationService.instance.syncNativeThresholds();

    await mqttService.init();
    if (!mqttService.isConnected) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Ambang disimpan secara lokal. MQTT belum terhubung, jadi konfigurasi belum dikirim.',
          ),
          backgroundColor: AppTheme.statusLow,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      setState(() {
        _readings = _buildReadingsFromData(_latestSensorData);
      });
      return true;
    }

    final mqttPayload = {
      ...payload,
      'buzzer_muted': Map<String, bool>.from(_buzzerMuted),
    };
    mqttService.publish(
      'nutrixense/config',
      jsonEncode(mqttPayload),
      retain: true,
    );

    if (!mounted) return false;
    setState(() {
      _readings = _buildReadingsFromData(_latestSensorData);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ambang berhasil diperbarui'),
        backgroundColor: AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return true;
  }

  String _thresholdDisplayLabel(String key) {
    const labels = {
      'min_nitrogen': 'minimal Nitrogen',
      'max_nitrogen': 'maksimal Nitrogen',
      'min_phosphorus': 'minimal Fosfor',
      'max_phosphorus': 'maksimal Fosfor',
      'min_potassium': 'minimal Kalium',
      'max_potassium': 'maksimal Kalium',
      'min_ph': 'minimal pH',
      'max_ph': 'maksimal pH',
      'min_moisture': 'minimal Kelembapan',
      'max_moisture': 'maksimal Kelembapan',
      'min_temperature': 'minimal Suhu',
      'max_temperature': 'maksimal Suhu',
      'min_ec': 'minimal EC',
      'max_ec': 'maksimal EC',
    };

    return labels[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _syncThresholdControllersFromStorage();
    _listenBuzzerMuteConfig();
    initializeDefaultReadings();

    totalAlerts = _alertCountService.alertCount.value;
    _alertCountService.alertCount.addListener(_syncAlertCount);

    _nutrientAlertService.initialize();
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

  void _syncAlertCount() {
    if (!mounted) return;
    setState(() {
      totalAlerts = _alertCountService.alertCount.value;
    });
  }

  @override
  void dispose() {
    sensorSub?.cancel();
    _buzzerConfigSub?.cancel();
    connectivitySub.cancel();
    connectionTimer?.cancel();
    _alertCountService.alertCount.removeListener(_syncAlertCount);
    for (final controller in _thresholdControllers.values) {
      controller.dispose();
    }
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
                                  Expanded(
                                    child: Row(
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
                                        const Expanded(
                                          child: Text(
                                            'NutriXense',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // ─── MQTT Badge + WiFi Icon ───────────────────────
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Small MQTT Badge
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
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
                                              isMqttConnected
                                                  ? 'Terhubung'
                                                  : 'Menunggu',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.1,
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

                              // ─── Greeting + Config Button ────────────────
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Selamat Datang,',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Tooltip(
                                    message: 'Konfigurasi ambang',
                                    child: InkWell(
                                      onTap: _openThresholdConfigDialog,
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.18),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.25),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.tune_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // ─── STATS BOX (Rounded White Border) ─────────
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
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
                                    _statItem('7', 'Sensor'),
                                    _divider(),
                                    _statItem('$totalAlerts', 'Peringatan'),
                                    _divider(),
                                    _statItem('4', 'Pompa'),
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
                  const SectionHeader(title: 'Pembacaan Sensor'),
                  const SizedBox(height: 20),
                  _buildSensorReadingsLayout(),
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorReadingsLayout() {
    if (_readings.length < 7) {
      return Column(
        children: _readings.asMap().entries.map((entry) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: entry.key == _readings.length - 1 ? 0 : 12,
            ),
            child: _animatedSensorCard(entry.value, entry.key),
          );
        }).toList(),
      );
    }

    final leftColumn = [_readings[0], _readings[1], _readings[2]];
    final rightColumn = [_readings[3], _readings[4], _readings[5]];
    final ecReading = _readings[6];

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useTwoColumns = constraints.maxWidth >= 280;

            if (!useTwoColumns) {
              final compactReadings = [...leftColumn, ...rightColumn];
              return Column(
                children: compactReadings.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _animatedSensorCard(
                      entry.value,
                      entry.key,
                      compact: true,
                    ),
                  );
                }).toList(),
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSensorColumn(leftColumn, 0)),
                const SizedBox(width: 12),
                Expanded(child: _buildSensorColumn(rightColumn, 3)),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _animatedSensorCard(ecReading, 6),
      ],
    );
  }

  Widget _buildSensorColumn(List<SensorReading> readings, int startIndex) {
    return Column(
      children: readings.asMap().entries.map((entry) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: entry.key == readings.length - 1 ? 0 : 12,
          ),
          child: _animatedSensorCard(
            entry.value,
            startIndex + entry.key,
            compact: true,
          ),
        );
      }).toList(),
    );
  }

  Widget _animatedSensorCard(
    SensorReading reading,
    int index, {
    bool compact = false,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 80)),
      curve: Curves.easeOut,
      builder: (context, value, child) => Transform.scale(
        scale: 0.8 + 0.2 * value,
        child: Opacity(opacity: value, child: child),
      ),
      child: _buildSensorReadingCard(reading, compact: compact),
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
            'NPK levels - dalam beberapa menit terakhir',
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
                maxY: _npkChartMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _npkChartInterval,
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
                      interval: _npkChartInterval,
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
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                _legend('Nitrogen', AppTheme.primaryGreen),
                _legend('Fosfor', AppTheme.primaryBlue),
                _legend('Kalium', AppTheme.statusHigh),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorReadingCard(
    SensorReading reading, {
    bool compact = false,
  }) {
    final sensorColor = Color(reading.colorHex);
    final sensorKey = _sensorKeyForReading(reading);
    final isBuzzerMuted = _buzzerMuted[sensorKey] ?? false;
    final isEcCard = sensorKey == 'ec';

    // ─── Dynamic UI based on reading status ─────────────────────
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

    final horizontalPadding = compact ? 12.0 : 20.0;
    final verticalPadding = compact ? 12.0 : 16.0;
    final iconBoxSize = compact ? 34.0 : 40.0;
    final iconSize = compact ? 19.0 : 22.0;
    final headerGap = compact ? 8.0 : 12.0;
    final labelFontSize = compact ? 12.0 : 13.5;
    final valueFontSize = compact ? 24.0 : 30.0;
    final progressHeight = compact ? 5.0 : 6.0;
    final statusHorizontalPadding = compact ? 7.0 : 10.0;
    final statusVerticalPadding = compact ? 4.0 : 5.0;
    final statusBadge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: statusHorizontalPadding,
        vertical: statusVerticalPadding,
      ),
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
              fontSize: compact ? 9.5 : 10,
              fontWeight: FontWeight.w700,
              color: statusColor,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
    final muteButtonSize = compact ? 30.0 : 34.0;
    final buzzerMuteButton = Tooltip(
      message: isBuzzerMuted
          ? 'Aktifkan alert ${_sensorLabel(sensorKey)}'
          : 'Nonaktifkan alert ${_sensorLabel(sensorKey)}',
      child: Material(
        color: isBuzzerMuted
            ? Colors.grey.shade200
            : AppTheme.primaryGreen.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _toggleBuzzerMute(sensorKey),
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: muteButtonSize,
            height: muteButtonSize,
            child: Icon(
              isBuzzerMuted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              size: compact ? 16 : 18,
              color: isBuzzerMuted
                  ? AppTheme.textSecondary
                  : AppTheme.primaryGreen,
            ),
          ),
        ),
      ),
    );
    final ecStatusControls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        statusBadge,
        const SizedBox(height: 6),
        buzzerMuteButton,
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
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
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: sensorColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Image.asset(
                    reading.icon,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              SizedBox(width: headerGap),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reading.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      reading.unit,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.black54,
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(height: 5),
                      if (isEcCard)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ecStatusControls,
                        )
                      else
                        statusBadge,
                    ],
                  ],
                ),
              ),

              // STATUS BADGE (tetap konsisten)
              if (!compact)
                isEcCard ? ecStatusControls : statusBadge
              else if (!isEcCard)
                buzzerMuteButton,

              if (!compact && !isEcCard) ...[
                const SizedBox(width: 8),
                buzzerMuteButton,
              ],
            ],
          ),

          SizedBox(height: compact ? 12 : 14),

          // VALUE
          Text(
            '${reading.value}',
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w800,
              color: sensorColor,
              height: 1.0,
            ),
          ),

          SizedBox(height: compact ? 4 : 6),

          Text(
            reading.unit,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),

          SizedBox(height: compact ? 8 : 10),

          // PROGRESS
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: reading.normalizedValue,
              backgroundColor: sensorColor.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(sensorColor),
              minHeight: progressHeight,
            ),
          ),

          // ─── Min / Max label ────────────────────────────────────────
          SizedBox(height: compact ? 5 : 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Min ${reading.minNormal} ${reading.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textLight,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Max ${reading.maxNormal} ${reading.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textLight,
                  ),
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
