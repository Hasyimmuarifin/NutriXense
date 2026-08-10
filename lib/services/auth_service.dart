import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? 'user_local',
      name: map['name'] as String? ?? 'Pengguna NutriXense',
      email: map['email'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class AuthService extends ChangeNotifier {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  static const String _keyIsLoggedIn = 'auth_is_logged_in';
  static const String _keyUserId = 'auth_user_id';
  static const String _keyUserName = 'auth_user_name';
  static const String _keyUserEmail = 'auth_user_email';
  static const String _keyRegisteredUsers = 'auth_registered_users_map';

  bool _isLoggedIn = false;
  UserModel? _currentUser;
  final Map<String, Map<String, String>> _localRegisteredUsers = {};

  bool get isLoggedIn => _isLoggedIn;
  UserModel? get currentUser => _currentUser;
  String get userName => _currentUser?.name ?? 'Pengguna NutriXense';
  String get userEmail => _currentUser?.email ?? '';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;

    // Load registered users cache
    final rawRegUsers = prefs.getString(_keyRegisteredUsers);
    if (rawRegUsers != null && rawRegUsers.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawRegUsers) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            _localRegisteredUsers[key] =
                val.map((k, v) => MapEntry(k, v.toString()));
          }
        });
      } catch (e) {
        debugPrint('Error parsing registered users cache: $e');
      }
    }

    if (_isLoggedIn) {
      final uid = prefs.getString(_keyUserId);
      final name = prefs.getString(_keyUserName);
      final email = prefs.getString(_keyUserEmail);

      if (uid != null && uid.isNotEmpty) {
        _currentUser = UserModel(
          uid: uid,
          name: (name != null && name.isNotEmpty) ? name : 'Petani NutriXense',
          email: email ?? '',
          createdAt: DateTime.now(),
        );
      } else {
        // Fallback for valid login without saved uid
        final fallbackUid = 'usr_${DateTime.now().millisecondsSinceEpoch}';
        _currentUser = UserModel(
          uid: fallbackUid,
          name: (name != null && name.isNotEmpty) ? name : 'Petani NutriXense',
          email: email ?? '',
          createdAt: DateTime.now(),
        );
        await prefs.setString(_keyUserId, fallbackUid);
      }
    }
  }

  /// STRICT LOGIN FUNCTION: Checks if user is registered in Firestore / Local cache
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPass = password.trim();

    if (trimmedEmail.isEmpty || trimmedPass.isEmpty) {
      throw Exception('Email dan kata sandi tidak boleh kosong');
    }

    if (!trimmedEmail.contains('@')) {
      throw Exception('Format email tidak valid');
    }

    Map<String, dynamic>? userData;

    // 1. Check local registered users cache first
    if (_localRegisteredUsers.containsKey(trimmedEmail)) {
      userData = _localRegisteredUsers[trimmedEmail];
    }

    // 2. Check Firebase Firestore if not in local cache
    if (userData == null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: trimmedEmail)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));

        if (snapshot.docs.isNotEmpty) {
          userData = snapshot.docs.first.data();
          _localRegisteredUsers[trimmedEmail] = {
            'uid': snapshot.docs.first.id,
            'name': userData['name']?.toString() ?? 'Petani NutriXense',
            'email': trimmedEmail,
            'password': userData['password']?.toString() ?? trimmedPass,
          };
          await _saveRegisteredUsersToStorage();
        }
      } catch (e) {
        debugPrint('Firestore user check failed/offline: $e');
      }
    }

    // 3. If STILL not found -> USER IS NOT REGISTERED!
    if (userData == null) {
      throw Exception(
        'Akun "$trimmedEmail" belum terdaftar. Silakan klik "Daftar Sekarang" untuk mendaftarkan akun baru.',
      );
    }

    // 4. Check password match
    final expectedPass = userData['password']?.toString();
    if (expectedPass != null &&
        expectedPass.isNotEmpty &&
        expectedPass != trimmedPass) {
      throw Exception('Kata sandi yang Anda masukkan salah');
    }

    final uid =
        userData['uid']?.toString() ?? 'usr_${trimmedEmail.hashCode.abs()}';
    final name = userData['name']?.toString() ?? 'Petani NutriXense';

    _currentUser = UserModel(
      uid: uid,
      name: name,
      email: trimmedEmail,
      createdAt: DateTime.now(),
    );

    _isLoggedIn = true;
    await _saveSessionToStorage();
    await _syncUserToFirestore();

    notifyListeners();
    return true;
  }

  /// STRICT REGISTER FUNCTION: Saves new user account to Firestore & Local Cache
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPass = password.trim();

    if (trimmedName.isEmpty) {
      throw Exception('Nama lengkap wajib diisi');
    }
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      throw Exception('Email tidak valid');
    }
    if (trimmedPass.length < 6) {
      throw Exception('Password minimal 6 karakter');
    }

    // Check if email already registered
    if (_localRegisteredUsers.containsKey(trimmedEmail)) {
      throw Exception(
          'Email "$trimmedEmail" sudah terdaftar. Silakan langsung masuk.');
    }

    final uid = 'usr_${DateTime.now().millisecondsSinceEpoch}';

    // Store in local cache
    _localRegisteredUsers[trimmedEmail] = {
      'uid': uid,
      'name': trimmedName,
      'email': trimmedEmail,
      'password': trimmedPass,
    };
    await _saveRegisteredUsersToStorage();

    // Store user data in Firestore
    final newModel = UserModel(
      uid: uid,
      name: trimmedName,
      email: trimmedEmail,
      createdAt: DateTime.now(),
    );

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        ...newModel.toMap(),
        'password': trimmedPass,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtIso': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      debugPrint(
          'SUCCESS: Registered user written to Firestore collection "users" with ID: $uid');
    } catch (e) {
      debugPrint('ERROR writing user to Firestore: $e');
      throw Exception(
          'Gagal menyimpan data ke Firestore: $e. Periksa koneksi internet Anda.');
    }

    notifyListeners();
    return true;
  }

  Future<void> updateProfile({
    required String name,
    required String email,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase();

    if (trimmedName.isEmpty) throw Exception('Nama tidak boleh kosong');
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      throw Exception('Email tidak valid');
    }

    _currentUser = UserModel(
      uid: _currentUser?.uid ?? 'usr_local',
      name: trimmedName,
      email: trimmedEmail,
      createdAt: _currentUser?.createdAt ?? DateTime.now(),
    );

    if (_localRegisteredUsers.containsKey(trimmedEmail)) {
      _localRegisteredUsers[trimmedEmail]!['name'] = trimmedName;
      await _saveRegisteredUsersToStorage();
    }

    await _saveSessionToStorage();
    await _syncUserToFirestore();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);

    _isLoggedIn = false;
    _currentUser = null;
    notifyListeners();
  }

  Future<void> _saveSessionToStorage() async {
    if (_currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserId, _currentUser!.uid);
    await prefs.setString(_keyUserName, _currentUser!.name);
    await prefs.setString(_keyUserEmail, _currentUser!.email);
  }

  Future<void> _saveRegisteredUsersToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyRegisteredUsers, jsonEncode(_localRegisteredUsers));
  }

  Future<void> _syncUserToFirestore({String? password}) async {
    if (_currentUser == null) return;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid);

      final data = {
        ..._currentUser!.toMap(),
        'lastLogin': FieldValue.serverTimestamp(),
      };
      if (password != null) {
        data['password'] = password;
      }

      await docRef.set(data, SetOptions(merge: true));
      debugPrint(
          'SUCCESS: User profile synced to Firestore: ${_currentUser!.uid}');
    } catch (e) {
      debugPrint('Firestore user sync error: $e');
    }
  }
}
