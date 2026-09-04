import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/services/credentials_store.dart';
import 'package:wifi_apk/sites/wifi_site.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('migrates legacy MikroTik and Keenetic profiles without mixing them',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'routers_v2': jsonEncode([
        {
          'vendor': 'mikrotik',
          'host': '192.168.88.1',
          'username': 'monitor',
          'password': 'mikrotik-secret',
          'transport': 'auto',
          'useTls': true,
        },
        {
          'vendor': 'keenetic',
          'host': 'router.example',
          'username': 'monitor',
          'password': 'keenetic-secret',
          'transport': 'auto',
          'useTls': true,
        },
      ]),
    });
    final store = CredentialsStore();

    final sites = await store.loadSites();
    final keenetic = await store.loadKeeneticProfiles();

    expect(sites, hasLength(1));
    expect(sites.single.imported, isTrue);
    expect(sites.single.routers.single.host, '192.168.88.1');
    expect(keenetic.single.host, 'router.example');
  });

  test('site round-trip preserves its router set and metadata', () async {
    final store = CredentialsStore();
    const site = WifiSite(
      id: 'office',
      name: 'Office',
      notes: 'Second floor',
      lastUsedAtMs: 123,
    );

    await store.saveSites([site]);
    final loaded = await store.loadSites();

    expect(loaded.single.id, 'office');
    expect(loaded.single.name, 'Office');
    expect(loaded.single.notes, 'Second floor');
    expect(loaded.single.lastUsedAtMs, 123);
  });

  test('an intentionally empty site list is not migrated again', () async {
    FlutterSecureStorage.setMockInitialValues({
      'routers_v2': jsonEncode([
        {
          'host': '192.168.88.1',
          'username': 'monitor',
          'password': 'secret',
          'transport': 'auto',
          'useTls': true,
        },
      ]),
      'wifi_sites_v1': '[]',
    });

    expect(await CredentialsStore().loadSites(), isEmpty);
  });
}
