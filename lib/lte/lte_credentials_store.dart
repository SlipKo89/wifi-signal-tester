import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'lte_service.dart';

/// Separate LTE profile storage. It shares the platform Keystore/Keychain but
/// not the Wi-Fi profile key, keeping the two features independent.
class LteCredentialsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _legacyKey = 'lte_router_v1';
  static const _profilesKey = 'lte_routers_v2';

  /// Adds or updates one router. A host represents one saved LTE router; its
  /// credentials, transport and preferred interface are replaced atomically.
  Future<void> save(LteConnection connection) async {
    final profiles = await loadAll();
    profiles.removeWhere((saved) => _sameHost(saved.host, connection.host));
    profiles.insert(0, connection);
    await _writeAll(profiles);
  }

  Future<List<LteConnection>> loadAll() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw != null && raw.isNotEmpty) return _decodeList(raw);

    // v1 stored a single SSH/RouterOS profile. Migrate it transparently so an
    // existing installation does not lose the router or its custom port.
    final legacy = await _loadLegacy();
    if (legacy == null) return [];
    await _writeAll([legacy]);
    await _storage.delete(key: _legacyKey);
    return [legacy];
  }

  Future<LteConnection?> load() async {
    final profiles = await loadAll();
    return profiles.isEmpty ? null : profiles.first;
  }

  Future<void> removeHost(String host) async {
    final profiles = await loadAll();
    profiles.removeWhere((saved) => _sameHost(saved.host, host));
    await _writeAll(profiles);
  }

  Future<void> clear() async {
    await _storage.delete(key: _profilesKey);
    await _storage.delete(key: _legacyKey);
  }

  Future<LteConnection?> _loadLegacy() async {
    final raw = await _storage.read(key: _legacyKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? LteConnection.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  List<LteConnection> _decodeList(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! List) return [];
      return json
          .whereType<Map<String, dynamic>>()
          .map(LteConnection.fromJson)
          .where((connection) => connection.host.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<LteConnection> profiles) => _storage.write(
        key: _profilesKey,
        value: jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
      );

  bool _sameHost(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();
}
