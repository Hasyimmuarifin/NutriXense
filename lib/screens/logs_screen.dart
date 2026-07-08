// lib/screens/logs_screen.dart
// Activity logs screen for backend pump actions and threshold notifications.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/log_alert_badge_service.dart';
import '../services/offline_data_cache_service.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_helper.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const String _pumpLogsCollection = 'pump_activity_logs';
  static const String _thresholdLogsCollection = 'threshold_alert_logs';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final OfflineDataCacheService _offlineCache =
      OfflineDataCacheService.instance;

  int _selectedLogType = 0;
  bool _isDeletingLogs = false;
  bool _isLoadingLogs = true;
  Object? _logsError;
  List<CachedLogEntry> _pumpLogEntries = const [];
  List<CachedLogEntry> _thresholdLogEntries = const [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pumpLogSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _thresholdLogSubscription;
  final LogAlertBadgeService _badgeService = LogAlertBadgeService.instance;

  @override
  void initState() {
    super.initState();
    _loadLogsFromCacheAndSync();
  }

  @override
  void dispose() {
    _pumpLogSubscription?.cancel();
    _thresholdLogSubscription?.cancel();
    super.dispose();
  }

  void _selectLogType(int index) {
    if (_selectedLogType != index) {
      setState(() => _selectedLogType = index);
    }

    if (index == 0) {
      unawaited(_badgeService.markPumpSeen());
    } else if (index == 1) {
      unawaited(_badgeService.markAlertsSeen());
    }
  }

  Future<void> _loadLogsFromCacheAndSync() async {
    await _pumpLogSubscription?.cancel();
    await _thresholdLogSubscription?.cancel();
    _pumpLogSubscription = null;
    _thresholdLogSubscription = null;

    setState(() {
      _isLoadingLogs = true;
      _logsError = null;
    });

    try {
      final pumpCache = await _offlineCache.loadLogs(_pumpLogsCollection);
      final thresholdCache =
          await _offlineCache.loadLogs(_thresholdLogsCollection);

      if (!mounted) return;
      setState(() {
        _pumpLogEntries = pumpCache;
        _thresholdLogEntries = thresholdCache;
      });

      await Future.wait([
        _syncLogUpdates(_pumpLogsCollection),
        _syncLogUpdates(_thresholdLogsCollection),
      ]);

      _listenForLatestLogs(_pumpLogsCollection);
      _listenForLatestLogs(_thresholdLogsCollection);
    } catch (error) {
      if (!mounted) return;
      setState(() => _logsError = error);
    } finally {
      if (mounted) {
        setState(() => _isLoadingLogs = false);
      }
    }
  }

  Future<void> _syncLogUpdates(String collectionPath) async {
    final cachedEntries = _entriesFor(collectionPath);
    final latestCachedTime = _latestLogTime(cachedEntries);
    if (collectionPath == _pumpLogsCollection) {
      await _refreshRunningPumpLogs(cachedEntries);
    }

    Query<Map<String, dynamic>> query =
        _firestore.collection(collectionPath).orderBy(
              'createdAt',
              descending: latestCachedTime == null,
            );

    if (latestCachedTime != null) {
      query = _firestore
          .collection(collectionPath)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(latestCachedTime))
          .orderBy('createdAt', descending: false);
    }

    try {
      final snapshot = await query.get(const GetOptions(source: Source.server));
      if (snapshot.docs.isEmpty) return;

      final merged = await _offlineCache.mergeLogs(
        collectionPath,
        snapshot.docs.map(CachedLogEntry.fromFirestore),
      );

      if (!mounted) return;
      _applyLogEntries(collectionPath, merged);
    } catch (_) {
      // Cache remains the source of truth when Firestore is offline/unavailable.
    }
  }

  void _listenForLatestLogs(String collectionPath) {
    final entries = _entriesFor(collectionPath);
    final runningSince = collectionPath == _pumpLogsCollection
        ? _earliestRunningPumpLogTime(entries)
        : null;
    final startAfter =
        (runningSince ?? _latestLogTime(entries) ?? DateTime.now())
            .subtract(const Duration(minutes: 5));

    final subscription = _firestore
        .collection(collectionPath)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(startAfter))
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snapshot) {
      unawaited(_handleLatestLogSnapshot(collectionPath, snapshot));
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() => _logsError = error);
    });

    if (collectionPath == _pumpLogsCollection) {
      _pumpLogSubscription = subscription;
    } else {
      _thresholdLogSubscription = subscription;
    }
  }

  Future<void> _handleLatestLogSnapshot(
    String collectionPath,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.docs.isEmpty || !mounted) return;

    final merged = await _offlineCache.mergeLogs(
      collectionPath,
      snapshot.docs.map(CachedLogEntry.fromFirestore),
    );
    if (!mounted) return;
    _applyLogEntries(collectionPath, merged);
  }

  Future<void> _refreshRunningPumpLogs(List<CachedLogEntry> entries) async {
    final runningEntries = entries.where(_isRunningPumpLog).toList();
    if (runningEntries.isEmpty) return;

    final refreshedEntries = <CachedLogEntry>[];

    for (final entry in runningEntries) {
      try {
        final snapshot = await _firestore
            .collection(_pumpLogsCollection)
            .doc(entry.id)
            .get(const GetOptions(source: Source.server));
        if (snapshot.exists) {
          refreshedEntries.add(CachedLogEntry.fromDocumentSnapshot(snapshot));
        }
      } catch (_) {
        // Keep the cached running log if Firestore is unavailable.
      }
    }

    if (refreshedEntries.isEmpty) return;

    final merged = await _offlineCache.mergeLogs(
      _pumpLogsCollection,
      refreshedEntries,
    );
    if (!mounted) return;
    _applyLogEntries(_pumpLogsCollection, merged);
  }

  List<CachedLogEntry> _entriesFor(String collectionPath) {
    return collectionPath == _pumpLogsCollection
        ? _pumpLogEntries
        : _thresholdLogEntries;
  }

  void _applyLogEntries(String collectionPath, List<CachedLogEntry> entries) {
    setState(() {
      if (collectionPath == _pumpLogsCollection) {
        _pumpLogEntries = entries;
      } else {
        _thresholdLogEntries = entries;
      }
    });
  }

  DateTime? _latestLogTime(List<CachedLogEntry> entries) {
    DateTime? latest;
    for (final entry in entries) {
      final createdAt = entry.createdAt;
      if (createdAt == null) continue;
      if (latest == null || createdAt.isAfter(latest)) {
        latest = createdAt;
      }
    }

    return latest;
  }

  DateTime? _earliestRunningPumpLogTime(List<CachedLogEntry> entries) {
    DateTime? earliest;
    for (final entry in entries.where(_isRunningPumpLog)) {
      final createdAt = entry.createdAt;
      if (createdAt == null) continue;
      if (earliest == null || createdAt.isBefore(earliest)) {
        earliest = createdAt;
      }
    }

    return earliest;
  }

  bool _isRunningPumpLog(CachedLogEntry entry) {
    final action = entry.data['action']?.toString().trim().toLowerCase();
    final metadata = entry.data['metadata'];
    final metadataState = metadata is Map
        ? metadata['state']?.toString().trim().toLowerCase()
        : null;
    return action == 'running' || metadataState == 'running';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.bgCard,
            elevation: 0,
            title: Row(
              children: [
                const Text(
                  'Logs',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _buildSegmentButton(
                      index: 0,
                      label: 'Pompa',
                      icon: Icons.water_drop_outlined,
                    ),
                    const SizedBox(width: 8),
                    _buildSegmentButton(
                      index: 1,
                      label: 'Peringatan',
                      icon: Icons.notifications_active_outlined,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSummaryCards(),
                const SizedBox(height: 18),
                _buildLogsHeader(),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _selectedLogType == 0
                      ? _buildPumpLogs()
                      : _buildThresholdLogs(),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsHeader() {
    final isPumpTab = _selectedLogType == 0;

    return Row(
      children: [
        Expanded(
          child: Text(
            isPumpTab ? 'Aktivitas Pompa' : 'Peringatan Ambang Batas',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF37909D),
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: _isDeletingLogs ? null : _confirmDeleteCurrentLogType,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.statusHigh,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: _isDeletingLogs
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_sweep_outlined, size: 18),
          label: Text(
            _isDeletingLogs ? 'Menghapus' : 'Hapus Semua',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedLogType == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _selectLogType(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryGreen : AppTheme.bgPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
              if (index == 1) ...[
                const SizedBox(width: 7),
                _UnreadBadge(
                  valueListenable: _badgeService.unreadAlertCount,
                ),
              ] else if (index == 0) ...[
                const SizedBox(width: 7),
                _UnreadBadge(
                  valueListenable: _badgeService.unreadPumpCount,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildCountCard(
            title: 'Aktivitas Pompa',
            collectionPath: _pumpLogsCollection,
            icon: Icons.opacity_rounded,
            color: AppTheme.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCountCard(
            title: 'Peringatan',
            collectionPath: _thresholdLogsCollection,
            icon: Icons.warning_amber_rounded,
            color: AppTheme.statusHigh,
          ),
        ),
      ],
    );
  }

  Widget _buildCountCard({
    required String title,
    required String collectionPath,
    required IconData icon,
    required Color color,
  }) {
    final value = _isLoadingLogs && _entriesFor(collectionPath).isEmpty
        ? '-'
        : '${_entriesFor(collectionPath).length}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.14)),
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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              color: color,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$title tersimpan',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPumpLogs() {
    if (_isLoadingLogs && _pumpLogEntries.isEmpty) {
      return const _LogLoadingState();
    }

    if (_logsError != null && _pumpLogEntries.isEmpty) {
      return _LogMessageState(
        icon: Icons.error_outline_rounded,
        title: 'Gagal memuat log pompa',
        message: 'Data offline tidak tersedia. $_logsError',
      );
    }

    final logs = _pumpLogEntries
        .map((entry) => _PumpActivityLog.fromCache(
              id: entry.id,
              data: entry.data,
              firestore: _firestore,
              collectionPath: _pumpLogsCollection,
            ))
        .toList(growable: false);

    if (logs.isEmpty) {
      return const _LogMessageState(
        icon: Icons.inbox_outlined,
        title: 'Belum ada aktivitas pompa',
        message: 'Aktivitas Pompa akan tampil di sini.',
      );
    }

    return Column(
      key: const ValueKey('pump_logs'),
      children: logs
          .map((log) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPumpLogCard(log),
              ))
          .toList(),
    );
  }

  Widget _buildThresholdLogs() {
    if (_isLoadingLogs && _thresholdLogEntries.isEmpty) {
      return const _LogLoadingState();
    }

    if (_logsError != null && _thresholdLogEntries.isEmpty) {
      return _LogMessageState(
        icon: Icons.error_outline_rounded,
        title: 'Gagal memuat log peringatan',
        message: 'Data offline tidak tersedia. $_logsError',
      );
    }

    final logs = _thresholdLogEntries
        .map((entry) => _ThresholdAlertLog.fromCache(
              id: entry.id,
              data: entry.data,
              firestore: _firestore,
              collectionPath: _thresholdLogsCollection,
            ))
        .toList(growable: false);

    if (logs.isEmpty) {
      return const _LogMessageState(
        icon: Icons.notifications_none_rounded,
        title: 'Belum ada peringatan ambang batas',
        message: 'Notifikasi ketika sensor melewati batas akan tampil di sini.',
      );
    }

    return Column(
      key: const ValueKey('threshold_logs'),
      children: logs
          .map((log) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildThresholdLogCard(log),
              ))
          .toList(),
    );
  }

  Widget _buildPumpLogCard(_PumpActivityLog log) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(AppTheme.primaryBlue),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(
            icon: Icons.water_drop_rounded,
            iconColor: AppTheme.primaryBlue,
            title: log.reason,
            subtitle: _formatDateTime(log.time),
            badge: log.badgeText,
            badgeColor: AppTheme.primaryBlue,
            onDelete: () => _confirmDeleteSingleLog(
              collectionPath: _pumpLogsCollection,
              reference: log.reference,
              successMessage: 'Log aktivitas pompa berhasil dihapus.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: log.pumpLabels
                .map((label) => _buildInfoChip(label, AppTheme.primaryGreen))
                .toList(),
          ),
          if (log.sourceLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMetadataRow(
              icon: Icons.route_rounded,
              label: 'Sumber',
              value: log.sourceLabel,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThresholdLogCard(_ThresholdAlertLog log) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(AppTheme.statusHigh),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(
            icon: Icons.warning_amber_rounded,
            iconColor: AppTheme.statusHigh,
            title: log.title,
            subtitle: _formatDateTime(log.time),
            badge: '${log.alerts.length} peringatan',
            badgeColor: AppTheme.statusHigh,
            onDelete: () => _confirmDeleteSingleLog(
              collectionPath: _thresholdLogsCollection,
              reference: log.reference,
              successMessage: 'Log peringatan berhasil dihapus.',
            ),
          ),
          const SizedBox(height: 12),
          if (log.alerts.isEmpty)
            Text(
              log.body,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...log.alerts.map(_buildAlertTile),
        ],
      ),
    );
  }

  Widget _buildCardHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    VoidCallback? onDelete,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildInfoChip(badge, badgeColor),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onDelete,
          tooltip: 'Hapus log',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.delete_outline_rounded,
            size: 19,
            color: AppTheme.statusHigh,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertTile(_ThresholdAlert alert) {
    final color =
        alert.status == 'Low' ? AppTheme.statusLow : AppTheme.statusHigh;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(
            alert.status == 'Low'
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${alert.label}: ${alert.valueText} ${alert.unit} (${alert.status})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Batas ${alert.thresholdText}',
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textLight),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(Color color) {
    return BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(0.14)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Waktu belum tersedia';
    return _dateFormat.format(dateTime);
  }

  Future<void> _confirmDeleteSingleLog({
    required String collectionPath,
    required DocumentReference<Map<String, dynamic>> reference,
    required String successMessage,
  }) async {
    try {
      await reference.delete();
      final entries =
          await _offlineCache.removeLog(collectionPath, reference.id);
      if (!mounted) return;
      _applyLogEntries(collectionPath, entries);
      _showSnackBar(successMessage, AppTheme.primaryGreen);
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(
        'Gagal menghapus log: $error',
        AppTheme.statusHigh,
      );
    }
  }

  Future<void> _confirmDeleteCurrentLogType() async {
    final isPumpTab = _selectedLogType == 0;
    final collectionPath =
        isPumpTab ? _pumpLogsCollection : _thresholdLogsCollection;
    final label = isPumpTab ? 'Aktivitas Pompa' : 'Peringatan';

    final confirmed = await _showDeleteConfirmation(
      title: 'Hapus semua log $label?',
      message:
          'Semua Log $label akan dihapus secara permanen. Aksi ini tidak bisa dibatalkan.',
      confirmLabel: 'Hapus Semua',
    );

    if (!confirmed) return;

    setState(() => _isDeletingLogs = true);

    try {
      final deletedCount = await _deleteCollection(collectionPath);
      await _offlineCache.clearLogs(collectionPath);
      if (!mounted) return;
      _applyLogEntries(collectionPath, const []);
      _showSnackBar(
        deletedCount == 0
            ? 'Tidak ada log $label yang perlu dihapus.'
            : '$deletedCount log $label berhasil dihapus.',
        AppTheme.primaryGreen,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(
        'Gagal menghapus semua log: $error',
        AppTheme.statusHigh,
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingLogs = false);
      }
    }
  }

  Future<int> _deleteCollection(String collectionPath) async {
    var deletedCount = 0;

    while (true) {
      final snapshot =
          await _firestore.collection(collectionPath).limit(500).get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      deletedCount += snapshot.docs.length;
      if (snapshot.docs.length < 500) break;
    }

    return deletedCount;
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

  void _showSnackBar(
    String message,
    Color backgroundColor,
  ) {
    showAppTextSnackBar(
      context,
      message,
      backgroundColor,
    );
  }
}

class _LogLoadingState extends StatelessWidget {
  const _LogLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _LogMessageState extends StatelessWidget {
  const _LogMessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.textLight, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.valueListenable});

  final ValueListenable<int> valueListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: valueListenable,
      builder: (context, alertCount, _) {
        if (alertCount <= 0) return const SizedBox.shrink();
        return _BadgeBubble(count: alertCount);
      },
    );
  }
}

class _BadgeBubble extends StatelessWidget {
  const _BadgeBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.statusLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _PumpActivityLog {
  const _PumpActivityLog({
    required this.reference,
    required this.reason,
    required this.pumpLabels,
    required this.durationSeconds,
    required this.time,
    required this.sourceLabel,
    required this.action,
  });

  final DocumentReference<Map<String, dynamic>> reference;
  final String reason;
  final List<String> pumpLabels;
  final int durationSeconds;
  final DateTime? time;
  final String sourceLabel;
  final String action;

  String get badgeText {
    if (action == 'running') return 'Berjalan';
    if (action == 'completed') return '$durationSeconds detik';
    if (action == 'on') return 'ON';
    if (action == 'off') return 'OFF';
    return '$durationSeconds detik';
  }

  factory _PumpActivityLog.fromCache({
    required String id,
    required Map<String, dynamic> data,
    required FirebaseFirestore firestore,
    required String collectionPath,
  }) {
    return _PumpActivityLog._fromData(
      firestore.collection(collectionPath).doc(id),
      data,
    );
  }

  factory _PumpActivityLog._fromData(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> data,
  ) {
    final metadata = _readMap(data['metadata']);
    final labels = _readStringList(data['pumpLabels']);
    final relays = _readIntList(data['relays']);
    final pumpLabels = labels.isNotEmpty
        ? labels
        : relays.map((relay) => 'Relay $relay').toList(growable: false);
    final durationMs = _readInt(data['durationMs']);
    final action =
        _readString(data['action'], fallback: _readString(metadata['state']))
            .toLowerCase();

    return _PumpActivityLog(
      reference: reference,
      reason: _readString(data['reason'], fallback: 'Aktivitas Pompa'),
      pumpLabels: pumpLabels.isEmpty ? ['Pompa tidak diketahui'] : pumpLabels,
      durationSeconds: durationMs <= 0 ? 0 : (durationMs / 1000).round(),
      time: _readDate(data['createdAt']) ??
          _readDate(data['finishedAt']) ??
          _readDate(data['startedAt']),
      sourceLabel: _sourceLabel(_readString(metadata['source'])),
      action: action,
    );
  }

  static String _sourceLabel(String value) {
    switch (value) {
      case 'manual_control':
        return 'Kontrol Manual';
      case 'ai_automation':
        return 'Rekomendasi AI';
      case 'dss_worker':
        return 'Pompa Otomatis';
      case 'schedule_worker':
        return 'Penjadwalan Pompa';
      default:
        return value;
    }
  }
}

class _ThresholdAlertLog {
  const _ThresholdAlertLog({
    required this.reference,
    required this.title,
    required this.body,
    required this.alerts,
    required this.time,
    this.sensorReadingId,
  });

  final DocumentReference<Map<String, dynamic>> reference;
  final String title;
  final String body;
  final List<_ThresholdAlert> alerts;
  final DateTime? time;
  final String? sensorReadingId;

  factory _ThresholdAlertLog.fromCache({
    required String id,
    required Map<String, dynamic> data,
    required FirebaseFirestore firestore,
    required String collectionPath,
  }) {
    return _ThresholdAlertLog._fromData(
      firestore.collection(collectionPath).doc(id),
      data,
    );
  }

  factory _ThresholdAlertLog._fromData(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> data,
  ) {
    final rawAlerts = data['alerts'];

    return _ThresholdAlertLog(
      reference: reference,
      title: _readString(data['title'], fallback: 'Peringatan Nutrisi Tanaman'),
      body: _readString(data['body']),
      alerts: rawAlerts is List
          ? rawAlerts
              .whereType<Map>()
              .map((item) => _ThresholdAlert.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      time: _readDate(data['createdAt']),
      sensorReadingId: _nullableString(data['sensorReadingId']),
    );
  }
}

class _ThresholdAlert {
  const _ThresholdAlert({
    required this.label,
    required this.status,
    required this.unit,
    required this.valueText,
    required this.thresholdText,
  });

  final String label;
  final String status;
  final String unit;
  final String valueText;
  final String thresholdText;

  factory _ThresholdAlert.fromMap(Map<String, dynamic> data) {
    return _ThresholdAlert(
      label: _readString(data['label'], fallback: 'Sensor'),
      status: _readString(data['status'], fallback: 'Alert'),
      unit: _readString(data['unit']),
      valueText: _formatNumber(data['value']),
      thresholdText: _formatNumber(data['threshold']),
    );
  }
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

List<int> _readIntList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
      .whereType<int>()
      .toList(growable: false);
}

String _readString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = _readString(value);
  return text.isEmpty ? null : text;
}

int _readInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

DateTime? _readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _formatNumber(Object? value) {
  if (value is num) return value.toStringAsFixed(1);
  final parsed = double.tryParse('$value');
  if (parsed != null) return parsed.toStringAsFixed(1);
  return '-';
}
