import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_credentials_store.dart';
import 'package:wifi_apk/lte/lte_service.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('stores several LTE routers and updates a host in place', () async {
    final store = LteCredentialsStore();
    const first = LteConnection(
      host: '192.0.2.1',
      username: 'monitor',
      password: 'first-secret',
      transport: TransportPreference.ssh,
      port: 2222,
    );
    const second = LteConnection(
      host: '192.0.2.2',
      username: 'reader',
      password: 'second-secret',
      transport: TransportPreference.rest,
    );

    await store.save(first);
    await store.save(second);
    expect((await store.loadAll()).map((profile) => profile.host),
        ['192.0.2.2', '192.0.2.1']);

    await store.save(const LteConnection(
      host: '192.0.2.1',
      username: 'new-reader',
      password: 'new-secret',
      transport: TransportPreference.binary,
      interfaceName: 'lte-main',
    ));
    final updated = await store.loadAll();
    expect(updated, hasLength(2));
    expect(updated.first.host, '192.0.2.1');
    expect(updated.first.username, 'new-reader');
    expect(updated.first.transport, TransportPreference.binary);
    expect(updated.first.interfaceName, 'lte-main');

    await store.removeHost('192.0.2.1');
    expect((await store.loadAll()).single.host, '192.0.2.2');
  });

  test('migrates the previous single LTE profile', () async {
    FlutterSecureStorage.setMockInitialValues({
      'lte_router_v1': jsonEncode({
        'host': '198.51.100.1',
        'username': 'monitor',
        'password': 'secret',
        'port': 2222,
        'interface': 'lte1',
      }),
    });
    final store = LteCredentialsStore();

    final profiles = await store.loadAll();
    expect(profiles, hasLength(1));
    expect(profiles.single.host, '198.51.100.1');
    expect(profiles.single.transport, TransportPreference.ssh);
    expect(profiles.single.port, 2222);

    // A second read comes from the new list and remains intact.
    expect((await store.loadAll()).single.interfaceName, 'lte1');
  });
}
