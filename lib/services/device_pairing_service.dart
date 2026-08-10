import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class PairedDeviceModel {
  final String deviceId;
  final String deviceName;
  final DateTime pairedAt;

  PairedDeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.pairedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'pairedAt': pairedAt.toIso8601String(),
    };
  }

  factory PairedDeviceModel.fromMap(Map<String, dynamic> map) {
    return PairedDeviceModel(
      deviceId: map['deviceId'] as String? ?? 'NTX-001',
      deviceName: map['deviceName'] as String? ?? 'NutriXense Prototype 1',
      pairedAt: map['pairedAt'] != null
          ? DateTime.tryParse(map['pairedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class DevicePairingService extends ChangeNotifier {
  DevicePairingService._internal();
  static final DevicePairingService instance = DevicePairingService._internal();

  static const String _keyIsPaired = 'device_is_paired';
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceName = 'device_name';
  static const String _keyPairedAt = 'device_paired_at';

  bool _isPaired = false;
  PairedDeviceModel? _currentDevice;

  bool get isPaired => _isPaired;
  PairedDeviceModel? get currentDevice => _currentDevice;
  String get pairedDeviceId => _currentDevice?.deviceId ?? 'NTX-001';
  String get pairedDeviceName => _currentDevice?.deviceName ?? 'NutriXense Prototype 1';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isPaired = prefs.getBool(_keyIsPaired) ?? false;

    if (_isPaired) {
      final deviceId = prefs.getString(_keyDeviceId) ?? 'NTX-001';
      final deviceName = prefs.getString(_keyDeviceName) ?? 'NutriXense Prototype 1';
      final pairedAtStr = prefs.getString(_keyPairedAt);

      _currentDevice = PairedDeviceModel(
        deviceId: deviceId,
        deviceName: deviceName,
        pairedAt: pairedAtStr != null
            ? DateTime.tryParse(pairedAtStr) ?? DateTime.now()
            : DateTime.now(),
      );
    } else {
      // Default single prototype pairing
      await pairDevice('NTX-001', deviceName: 'NutriXense Prototype 1');
    }
  }

  Future<bool> pairDevice(String deviceId, {String? deviceName}) async {
    final cleanedId = deviceId.trim().toUpperCase();
    if (cleanedId.isEmpty) {
      throw Exception('ID Perangkat tidak boleh kosong');
    }

    final name = deviceName?.trim().isNotEmpty == true
        ? deviceName!.trim()
        : 'NutriXense Device ($cleanedId)';

    _currentDevice = PairedDeviceModel(
      deviceId: cleanedId,
      deviceName: name,
      pairedAt: DateTime.now(),
    );

    _isPaired = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsPaired, true);
    await prefs.setString(_keyDeviceId, cleanedId);
    await prefs.setString(_keyDeviceName, name);
    await prefs.setString(_keyPairedAt, _currentDevice!.pairedAt.toIso8601String());

    await _syncDeviceToFirestore();
    notifyListeners();
    return true;
  }

  Future<void> unpairDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsPaired);
    await prefs.remove(_keyDeviceId);
    await prefs.remove(_keyDeviceName);
    await prefs.remove(_keyPairedAt);

    _isPaired = false;
    _currentDevice = null;

    try {
      final userId = AuthService.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({'pairedDevice': FieldValue.delete()})
            .timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      debugPrint('Firestore unpair sync skipped: $e');
    }

    notifyListeners();
  }

  Future<void> _syncDeviceToFirestore() async {
    if (_currentDevice == null) return;
    try {
      final userId = AuthService.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .set({
          'pairedDevice': _currentDevice!.toMap(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      debugPrint('Firestore device pairing sync skipped: $e');
    }
  }
}
