// lib/screens/control_screen.dart
// Pump controller page – toggle pumps A/B/C with loading animations and status display

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dummy_data.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';
import '../widgets/pump_card.dart';
import '../services/mqtt_service.dart';
import '../services/rule_based_pump_automation_service.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  static const String _scheduleStorageKey = 'nutrixense_watering_schedules';

  late List<PumpController> _pumps;
  final MQTTService mqttService = MQTTService();
  final RuleBasedPumpAutomationService _ruleBasedPumpAutomationService =
      RuleBasedPumpAutomationService.instance;
  final List<_WateringSchedule> _wateringSchedules = [];
  TimeOfDay _draftScheduleTime = TimeOfDay.now();
  final Set<int> _draftSchedulePumpIndexes = {3};
  int _draftScheduleDurationSeconds = 5;
  bool _draftScheduleRepeats = true;
  late bool _isRuleBasedAutomationEnabled;
  StreamSubscription<Map<String, dynamic>>? _controlSub;

  @override
  void initState() {
    super.initState();
    _pumps = DummyData.getPumps();
    _isRuleBasedAutomationEnabled = _ruleBasedPumpAutomationService.isRunning;
    _ruleBasedPumpAutomationService.activeRelays.addListener(_syncDssRelays);
    _restoreDssSwitchState();
    _initControlMqtt();
    _loadSchedules();
  }

  @override
  void dispose() {
    for (final schedule in _wateringSchedules) {
      schedule.timer?.cancel();
    }
    _controlSub?.cancel();
    _ruleBasedPumpAutomationService.activeRelays.removeListener(_syncDssRelays);
    super.dispose();
  }

  Future<void> _initControlMqtt() async {
    await mqttService.init();
    mqttService.subscribe('nutrixense/control');
    _controlSub = mqttService.sensorStream.listen(_syncPumpStatesFromMqtt);
  }

  void _syncPumpStatesFromMqtt(Map<String, dynamic> data) {
    if (!mounted) return;

    var changed = false;
    for (var i = 0; i < _pumps.length; i++) {
      final rawState = data['relay${i + 1}'];
      if (rawState == null) continue;

      final relayState = rawState is num
          ? rawState.toInt()
          : int.tryParse(rawState.toString());
      if (relayState == null) continue;

      _pumps[i].isOn = relayState == 0;
      _pumps[i].isLoading = false;
      changed = true;
    }

    if (changed) setState(() {});
  }

  Future<void> _restoreDssSwitchState() async {
    final enabled =
        await _ruleBasedPumpAutomationService.loadEnabledPreference();
    if (!mounted) return;

    setState(() => _isRuleBasedAutomationEnabled = enabled);
  }

  void _syncDssRelays() {
    if (!mounted) return;

    final activeRelays = _ruleBasedPumpAutomationService.activeRelays.value;
    setState(() {
      for (var i = 0; i < _pumps.length; i++) {
        _pumps[i].isOn = activeRelays.contains(i + 1);
        _pumps[i].isLoading = false;
      }
    });
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

  Future<void> _pickScheduleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _draftScheduleTime,
    );

    if (!mounted || picked == null) return;

    setState(() => _draftScheduleTime = picked);
  }

  void _addSchedule() {
    if (_draftSchedulePumpIndexes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Choose at least one pump for the schedule.'),
          backgroundColor: AppTheme.statusLow,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final schedule = _WateringSchedule(
      id: DateTime.now().microsecondsSinceEpoch,
      time: _draftScheduleTime,
      pumpIndexes: Set<int>.from(_draftSchedulePumpIndexes),
      durationSeconds: _draftScheduleDurationSeconds,
      repeatsDaily: _draftScheduleRepeats,
    );

    setState(() => _wateringSchedules.add(schedule));
    _saveSchedules();
    _scheduleNextRun(schedule, showSnackBar: true);
  }

  void _deleteSchedule(_WateringSchedule schedule) {
    schedule.timer?.cancel();
    setState(() => _wateringSchedules.remove(schedule));
    _saveSchedules();
  }

  void _toggleSchedule(_WateringSchedule schedule, bool enabled) {
    setState(() => schedule.enabled = enabled);

    if (enabled) {
      _scheduleNextRun(schedule, showSnackBar: true);
    } else {
      schedule.timer?.cancel();
      setState(() => schedule.nextRun = null);
      _saveSchedules();
    }
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchedules = prefs.getString(_scheduleStorageKey);
    if (rawSchedules == null) {
      _syncNativeSchedules();
      return;
    }

    final decoded = jsonDecode(rawSchedules);
    if (decoded is! List) return;

    final restoredSchedules = decoded
        .whereType<Map<String, dynamic>>()
        .map(_WateringSchedule.fromJson)
        .whereType<_WateringSchedule>()
        .toList();

    if (!mounted || restoredSchedules.isEmpty) return;

    setState(() {
      _wateringSchedules
        ..clear()
        ..addAll(restoredSchedules);
    });

    for (final schedule in restoredSchedules) {
      if (schedule.enabled) {
        _scheduleNextRun(schedule);
      }
    }

    _syncNativeSchedules();
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final schedules = _wateringSchedules
        .map((schedule) => schedule.toJson())
        .toList(growable: false);
    final schedulesJson = jsonEncode(schedules);
    await prefs.setString(_scheduleStorageKey, schedulesJson);
    _ruleBasedPumpAutomationService.syncNativeSchedules(schedulesJson);
  }

  void _syncNativeSchedules() {
    final schedulesJson = jsonEncode(
      _wateringSchedules
          .map((schedule) => schedule.toJson())
          .toList(growable: false),
    );
    _ruleBasedPumpAutomationService.syncNativeSchedules(schedulesJson);
  }

  void _scheduleNextRun(
    _WateringSchedule schedule, {
    bool showSnackBar = false,
  }) {
    schedule.timer?.cancel();

    final now = DateTime.now();
    var nextRun = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.time.hour,
      schedule.time.minute,
    );

    if (!nextRun.isAfter(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    setState(() {
      schedule.enabled = true;
      schedule.nextRun = nextRun;
    });
    _saveSchedules();

    if (showSnackBar) {
      _showScheduleSnackBar(schedule);
    }
  }

  void _showScheduleSnackBar(_WateringSchedule schedule) {
    if (!mounted || schedule.nextRun == null) return;

    final timeText = TimeOfDay.fromDateTime(schedule.nextRun!).format(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Automatic watering scheduled at $timeText'),
        backgroundColor: AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
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
            Expanded(
              child: Text(
                '${pump.name} (${pump.nutrient}) ${pump.isOn ? 'started' : 'stopped'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            pump.isOn ? AppTheme.primaryGreen : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 0, milliseconds: 500),
      ),
    );
  }

  int get _activePumps => _pumps.where((p) => p.isOn).length;

  Future<void> _toggleRuleBasedAutomation(bool enabled) async {
    if (enabled) {
      await _ruleBasedPumpAutomationService.start();
    } else {
      await _ruleBasedPumpAutomationService.stop();
    }

    if (!mounted) return;
    setState(() => _isRuleBasedAutomationEnabled = enabled);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Decision Support automation enabled.'
              : 'Decision Support automation disabled.',
        ),
        backgroundColor: enabled ? AppTheme.primaryGreen : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildDecisionSupportSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.rule_rounded,
            color: _isRuleBasedAutomationEnabled
                ? const Color(0xFF69F0AE)
                : Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            _isRuleBasedAutomationEnabled ? 'DSS ON' : 'DSS OFF',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          Transform.scale(
            scale: 0.72,
            child: Switch(
              value: _isRuleBasedAutomationEnabled,
              onChanged: _toggleRuleBasedAutomation,
              activeColor: const Color(0xFF69F0AE),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDssInfoButton() {
    return PopupMenuButton<void>(
      tooltip: 'DSS info',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 18),
      itemBuilder: (context) => const [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            width: 220,
            child: Text(
              'DSS membantu menyalakan pompa secara otomatis berdasarkan kondisi nutrisi, kelembapan, dan suhu tanaman. Aktifkan DSS jika ingin sistem membantu perawatan tanaman.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.18),
          border: Border.all(
            color: Colors.white.withOpacity(0.7),
            width: 1,
          ),
        ),
        child: const Text(
          'i',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }

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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Logo + App Name
                                Expanded(
                                  child: Row(
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

                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                                          color: Colors.white.withOpacity(0.25),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.auto_awesome,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'DSS Powered',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _buildDssInfoButton(),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // ─── Title ────────────────────────────────────
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Pump Control',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildDecisionSupportSwitch(),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // ─── Subtitle ─────────────────────────────────
                            Text(
                              'Manage your nutrient & irrigation pumps',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // ─── Status Box ───────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '$_activePumps of ${_pumps.length} pumps active',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 13,
                                      ),
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

                // ─── Emergency Stop ──────────────────────────────────────
                _buildEmergencyStop(),

                const SizedBox(height: 14),

                // ─── Automatic Watering Schedule ────────────────────────
                _buildScheduleCard(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.12),
        ),
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: AppTheme.primaryGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic Watering Schedules',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Set time, pump selection, and watering duration.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primaryGreen.withOpacity(0.12),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 330;
                final timeButton = OutlinedButton.icon(
                  onPressed: _pickScheduleTime,
                  icon: const Icon(Icons.access_time_rounded, size: 18),
                  label: Text(
                    _draftScheduleTime.format(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryGreen,
                    side: BorderSide(
                      color: AppTheme.primaryGreen.withOpacity(0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                final addButton = FilledButton.icon(
                  onPressed: _addSchedule,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Add Schedule',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );

                if (narrow) {
                  return Column(
                    children: [
                      SizedBox(width: double.infinity, child: timeButton),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: addButton),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: timeButton),
                    const SizedBox(width: 10),
                    Expanded(child: addButton),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pumps',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _pumps.asMap().entries.map((entry) {
              final index = entry.key;
              final pump = entry.value;
              final selected = _draftSchedulePumpIndexes.contains(index);

              return FilterChip(
                selected: selected,
                label: Text(pump.name),
                avatar: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color:
                      selected ? AppTheme.primaryGreen : AppTheme.textSecondary,
                ),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _draftSchedulePumpIndexes.add(index);
                    } else {
                      _draftSchedulePumpIndexes.remove(index);
                    }
                  });
                },
                selectedColor: AppTheme.primaryGreen.withOpacity(0.12),
                checkmarkColor: AppTheme.primaryGreen,
                side: BorderSide(
                  color:
                      selected ? AppTheme.primaryGreen : Colors.grey.shade300,
                ),
                labelStyle: TextStyle(
                  color:
                      selected ? AppTheme.primaryGreen : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Duration',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$_draftScheduleDurationSeconds sec',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: _draftScheduleDurationSeconds.toDouble(),
            min: 5,
            max: 300,
            divisions: 59,
            label: '$_draftScheduleDurationSeconds sec',
            activeColor: AppTheme.primaryGreen,
            onChanged: (value) {
              setState(() => _draftScheduleDurationSeconds = value.round());
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _draftScheduleRepeats,
            onChanged: (value) {
              setState(() => _draftScheduleRepeats = value);
            },
            activeColor: AppTheme.primaryGreen,
            title: const Text(
              'Repeat daily',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (_wateringSchedules.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgPrimary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: 18,
                    color: AppTheme.textLight,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No automatic watering schedule yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._wateringSchedules.map(_buildScheduleListTile),
        ],
      ),
    );
  }

  Widget _buildScheduleListTile(_WateringSchedule schedule) {
    final nextRunText = schedule.nextRun == null
        ? 'Paused'
        : TimeOfDay.fromDateTime(schedule.nextRun!).format(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: schedule.enabled
              ? AppTheme.primaryGreen.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.time.format(context),
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_pumpNames(schedule.pumpIndexes)} • ${schedule.durationSeconds}s • ${schedule.repeatsDaily ? 'Daily' : 'Once'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: schedule.enabled,
                onChanged: schedule.isRunning
                    ? null
                    : (value) => _toggleSchedule(schedule, value),
                activeColor: AppTheme.primaryGreen,
              ),
              IconButton(
                tooltip: 'Delete schedule',
                onPressed:
                    schedule.isRunning ? null : () => _deleteSchedule(schedule),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.statusLow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                schedule.isRunning
                    ? Icons.water_drop_rounded
                    : Icons.schedule_rounded,
                size: 15,
                color: schedule.isRunning
                    ? AppTheme.primaryBlue
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  schedule.isRunning ? 'Running now' : 'Next run: $nextRunText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: schedule.isRunning
                        ? AppTheme.primaryBlue
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _pumpNames(Set<int> indexes) {
    final sortedIndexes = indexes.toList()..sort();
    return sortedIndexes.map((index) => _pumps[index].name).join(', ');
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
          child: const Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              Icon(
                Icons.stop_circle_outlined,
                color: AppTheme.statusLow,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Emergency Stop All Pumps',
                textAlign: TextAlign.center,
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

class _WateringSchedule {
  final int id;
  final TimeOfDay time;
  final Set<int> pumpIndexes;
  final int durationSeconds;
  final bool repeatsDaily;
  bool enabled = true;
  bool isRunning = false;
  DateTime? nextRun;
  Timer? timer;

  _WateringSchedule({
    required this.id,
    required this.time,
    required this.pumpIndexes,
    required this.durationSeconds,
    required this.repeatsDaily,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hour': time.hour,
      'minute': time.minute,
      'pumpIndexes': pumpIndexes.toList()..sort(),
      'durationSeconds': durationSeconds,
      'repeatsDaily': repeatsDaily,
      'enabled': enabled,
    };
  }

  static _WateringSchedule? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final hour = json['hour'];
    final minute = json['minute'];
    final durationSeconds = json['durationSeconds'];
    final repeatsDaily = json['repeatsDaily'];
    final enabled = json['enabled'];
    final pumpIndexes = json['pumpIndexes'];

    if (id is! int ||
        hour is! int ||
        minute is! int ||
        durationSeconds is! int ||
        repeatsDaily is! bool ||
        enabled is! bool ||
        pumpIndexes is! List ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    final parsedPumpIndexes = pumpIndexes.whereType<int>().toSet();
    if (parsedPumpIndexes.isEmpty) return null;

    return _WateringSchedule(
      id: id,
      time: TimeOfDay(hour: hour, minute: minute),
      pumpIndexes: parsedPumpIndexes,
      durationSeconds: durationSeconds,
      repeatsDaily: repeatsDaily,
      enabled: enabled,
    );
  }
}
