// lib/screens/control_screen.dart
// Pump controller page – toggle pumps A/B/C with loading animations and status display

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/dummy_data.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';
import '../widgets/pump_card.dart';
import '../services/mqtt_service.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late List<PumpController> _pumps;
  final MQTTService mqttService = MQTTService();
  final List<_WateringSchedule> _wateringSchedules = [];
  TimeOfDay _draftScheduleTime = TimeOfDay.now();
  final Set<int> _draftSchedulePumpIndexes = {3};
  int _draftScheduleDurationSeconds = 5;
  bool _draftScheduleRepeats = true;

  @override
  void initState() {
    super.initState();
    _pumps = DummyData.getPumps();
    mqttService.init();
  }

  @override
  void dispose() {
    for (final schedule in _wateringSchedules) {
      schedule.timer?.cancel();
    }
    super.dispose();
  }

  Future<void> _wateringPump() async {
    const pumpDIndex = 3;

    if (_pumps[pumpDIndex].isOn || _pumps[pumpDIndex].isLoading) {
      return;
    }

    await _runPumpsForDuration(
      pumpIndexes: const [pumpDIndex],
      duration: const Duration(seconds: 5),
      startedMessage: 'Water irrigation started',
      completedMessage: 'Water irrigation completed',
    );
  }

  Future<void> _runPumpsForDuration({
    required List<int> pumpIndexes,
    required Duration duration,
    String? startedMessage,
    String? completedMessage,
  }) async {
    try {
      final validPumpIndexes = pumpIndexes
          .where((index) => index >= 0 && index < _pumps.length)
          .toList();

      if (validPumpIndexes.isEmpty) return;

      for (final index in validPumpIndexes) {
        if (!_pumps[index].isOn) {
          await _togglePump(index, true);
        }
      }

      if (startedMessage != null) {
        _showWaterSnackBar(true, message: startedMessage);
      }

      await Future.delayed(duration);

      for (final index in validPumpIndexes) {
        if (_pumps[index].isOn) {
          await _togglePump(index, false);
        }
      }

      if (completedMessage != null) {
        _showWaterSnackBar(false, message: completedMessage);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pump run failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showWaterSnackBar(bool started, {String? message}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              started ? Icons.water_drop_rounded : Icons.water_damage_outlined,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              message ??
                  (started
                      ? 'Water irrigation started'
                      : 'Water irrigation completed'),
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
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
    _scheduleNextRun(schedule, showSnackBar: true);
  }

  void _deleteSchedule(_WateringSchedule schedule) {
    schedule.timer?.cancel();
    setState(() => _wateringSchedules.remove(schedule));
  }

  void _toggleSchedule(_WateringSchedule schedule, bool enabled) {
    setState(() => schedule.enabled = enabled);

    if (enabled) {
      _scheduleNextRun(schedule, showSnackBar: true);
    } else {
      schedule.timer?.cancel();
      setState(() => schedule.nextRun = null);
    }
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

    final delay = nextRun.difference(now);

    setState(() {
      schedule.enabled = true;
      schedule.nextRun = nextRun;
    });

    schedule.timer = Timer(delay, () async {
      if (!mounted ||
          !schedule.enabled ||
          !_wateringSchedules.contains(schedule)) {
        return;
      }

      setState(() => schedule.isRunning = true);

      await _runPumpsForDuration(
        pumpIndexes: schedule.pumpIndexes.toList()..sort(),
        duration: Duration(seconds: schedule.durationSeconds),
        startedMessage: 'Scheduled watering started',
        completedMessage: 'Scheduled watering completed',
      );

      if (!mounted) return;

      setState(() => schedule.isRunning = false);

      if (schedule.repeatsDaily && schedule.enabled) {
        _scheduleNextRun(schedule);
      } else {
        setState(() {
          schedule.enabled = false;
          schedule.nextRun = null;
        });
      }
    });

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
            Text(
              '${pump.name} (${pump.nutrient}) ${pump.isOn ? 'started' : 'stopped'}',
              style: const TextStyle(fontWeight: FontWeight.w500),
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
                                Row(
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
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.auto_awesome,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'AI Powered',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ─── Title ────────────────────────────────────
                            const Text(
                              'Pump Control',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),

                            const SizedBox(height: 8),

                            // ─── Subtitle ─────────────────────────────────
                            Row(
                              children: [
                                Text(
                                  'Manage your nutrient & irrigation pumps',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ─── Status Box ───────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
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
                                  Text(
                                    '$_activePumps of ${_pumps.length} pumps active',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13,
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

                // ─── Water Irrigation Button ─────────────────────────────
                _buildWateringButton(),

                const SizedBox(height: 14),

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

  Widget _buildWateringButton() {
    return GestureDetector(
      onTap: _wateringPump,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryBlue,
              AppTheme.primaryBlue.withOpacity(0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.water_drop_rounded,
              color: Colors.white,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Start Water Irrigation',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
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
                child: Text(
                  'Automatic Watering Schedules',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickScheduleTime,
                  icon: const Icon(Icons.access_time_rounded, size: 18),
                  label: Text(_draftScheduleTime.format(context)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryGreen,
                    side: BorderSide(
                      color: AppTheme.primaryGreen.withOpacity(0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _addSchedule,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Schedule'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
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
              child: const Text(
                'No automatic watering schedule yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
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
              Text(
                schedule.isRunning ? 'Running now' : 'Next run: $nextRunText',
                style: TextStyle(
                  fontSize: 12,
                  color: schedule.isRunning
                      ? AppTheme.primaryBlue
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.stop_circle_outlined,
                color: AppTheme.statusLow,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Emergency Stop All Pumps',
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
  });
}
