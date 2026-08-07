import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'lte_service.dart';

/// Separate LTE profile storage. It shares the platform Keystore/Keychain but
/// not the Wi-Fi profile key, keeping the two features independent.
class LteCredentialsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'lte_router_v1';

  Future<void> save(LteConnection connection) => _storage.write(
        key: _key,
        value: jsonEncode(connection.toJson()),
      );

  Future<LteConnection?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? LteConnection.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}
