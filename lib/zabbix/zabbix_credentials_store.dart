import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'zabbix_models.dart';

/// Stores Zabbix API tokens in platform-backed secure storage. Tokens never
/// enter SharedPreferences, app logs, reports or the local history databases.
class ZabbixCredentialsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _profilesKey = 'zabbix_profiles_v1';

  Future<void> save(ZabbixConnection connection) async {
    final profiles = await loadAll();
    profiles.removeWhere(
      (saved) => _sameUrl(saved.url, connection.url),
    );
    profiles.insert(0, connection);
    await _writeAll(profiles);
  }

  Future<List<ZabbixConnection>> loadAll() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ZabbixConnection.fromJson)
          .where(
            (profile) =>
                profile.url.trim().isNotEmpty &&
                profile.apiToken.trim().isNotEmpty,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> remove(String url) async {
    final profiles = await loadAll();
    profiles.removeWhere((profile) => _sameUrl(profile.url, url));
    await _writeAll(profiles);
  }

  Future<void> clear() => _storage.delete(key: _profilesKey);

  Future<void> _writeAll(List<ZabbixConnection> profiles) => _storage.write(
        key: _profilesKey,
        value: jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
      );

  bool _sameUrl(String left, String right) =>
      left.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '') ==
      right.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
}
