import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../router/router_connection.dart';
import '../sites/wifi_site.dart';

/// Persists the configured routers in platform-backed secure storage
/// (Android Keystore / iOS Keychain). Passwords never touch plain prefs.
class CredentialsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kRouters = 'routers_v2';
  static const _kSites = 'wifi_sites_v1';
  static const _kKeeneticProfiles = 'keenetic_profiles_v1';
  static const _operationTimeout = Duration(seconds: 8);

  Future<String?> _read(String key) =>
      _storage.read(key: key).timeout(_operationTimeout);

  Future<void> _write(String key, String value) =>
      _storage.write(key: key, value: value).timeout(_operationTimeout);

  Future<void> _delete(String key) =>
      _storage.delete(key: key).timeout(_operationTimeout);

  Future<void> saveRouters(List<RouterConnection> routers) async {
    final data = jsonEncode(routers.map((r) => r.toJson()).toList());
    await _write(_kRouters, data);
  }

  Future<List<RouterConnection>> loadRouters() async {
    final raw = await _read(_kRouters);
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

  /// Loads named MikroTik sites. The previous global router list is migrated
  /// once into a single imported site without deleting the old key, allowing a
  /// downgrade to an older app build without losing credentials.
  Future<List<WifiSite>> loadSites() async {
    final raw = await _read(_kSites);
    if (raw != null) return _decodeSites(raw);

    final legacy = await loadRouters();
    final mikrotik = legacy
        .where((router) => router.vendor == RouterVendor.mikrotik)
        .toList();
    final migrated = mikrotik.isEmpty
        ? <WifiSite>[]
        : [
            WifiSite(
              id: 'imported-routers',
              name: 'Imported routers',
              routers: List.unmodifiable(mikrotik),
              imported: true,
            ),
          ];
    await saveSites(migrated);
    return migrated;
  }

  Future<void> saveSites(List<WifiSite> sites) async {
    await _write(
      _kSites,
      jsonEncode(sites.map((site) => site.toJson()).toList()),
    );
  }

  Future<void> upsertSite(WifiSite site) async {
    final sites = await loadSites();
    final index = sites.indexWhere((saved) => saved.id == site.id);
    if (index < 0) {
      sites.add(site);
    } else {
      sites[index] = site;
    }
    await saveSites(sites);
  }

  Future<void> deleteSite(String id) async {
    final sites = await loadSites();
    sites.removeWhere((site) => site.id == id);
    await saveSites(sites);
  }

  Future<List<RouterConnection>> loadKeeneticProfiles() async {
    final raw = await _read(_kKeeneticProfiles);
    if (raw != null) return _decodeRouters(raw, RouterVendor.keenetic);
    final migrated = (await loadRouters())
        .where((router) => router.vendor == RouterVendor.keenetic)
        .toList();
    await saveKeeneticProfiles(migrated);
    return migrated;
  }

  Future<void> saveKeeneticProfiles(List<RouterConnection> profiles) async {
    final keenetic = profiles
        .where((router) => router.vendor == RouterVendor.keenetic)
        .toList();
    await _write(
      _kKeeneticProfiles,
      jsonEncode(keenetic.map((router) => router.toJson()).toList()),
    );
  }

  List<WifiSite> _decodeSites(String raw) {
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((value) => WifiSite.fromJson(Map<String, dynamic>.from(value)))
          .where((site) => site.id.isNotEmpty && site.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<RouterConnection> _decodeRouters(String raw, RouterVendor vendor) {
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((value) => RouterConnection.fromJson(
                Map<String, dynamic>.from(value),
              ))
          .where((router) => router.vendor == vendor)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clear() async {
    await _delete(_kRouters);
    await _delete(_kSites);
    await _delete(_kKeeneticProfiles);
  }
}
