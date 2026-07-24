import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../mikrotik/mikrotik_service.dart';

/// Persists the configured routers in platform-backed secure storage
/// (Android Keystore / iOS Keychain). Passwords never touch plain prefs.
class CredentialsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kRouters = 'routers_v2';

  Future<void> saveRouters(List<RouterConnection> routers) async {
    final data = jsonEncode(routers.map((r) => r.toJson()).toList());
    await _storage.write(key: _kRouters, value: data);
  }

  Future<List<RouterConnection>> loadRouters() async {
    final raw = await _storage.read(key: _kRouters);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(RouterConnection.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _kRouters);
  }
}
