import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/zabbix/zabbix_credentials_store.dart';
import 'package:wifi_apk/zabbix/zabbix_models.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('stores tokens securely and updates a profile by URL', () async {
    final store = ZabbixCredentialsStore();
    await store.save(const ZabbixConnection(
      name: 'Office',
      url: 'https://zabbix.example.com/',
      apiToken: 'first-token',
    ));
    await store.save(const ZabbixConnection(
      name: 'Home',
      url: 'https://home.example.com/zabbix',
      apiToken: 'home-token',
    ));
    await store.save(const ZabbixConnection(
      name: 'Office updated',
      url: 'https://zabbix.example.com',
      apiToken: 'new-token',
    ));
    await store.save(const ZabbixConnection(
      name: 'Lab HTTP',
      url: 'http://zabbix.lan:8080/zabbix',
      apiToken: 'lab-token',
    ));

    final profiles = await store.loadAll();
    expect(profiles, hasLength(3));
    expect(profiles.first.name, 'Lab HTTP');
    expect(profiles[1].name, 'Office updated');
    expect(profiles[1].apiToken, 'new-token');
    expect(profiles.last.name, 'Home');

    await store.remove('https://zabbix.example.com/');
    expect(
      (await store.loadAll()).map((profile) => profile.name),
      ['Lab HTTP', 'Home'],
    );
  });
}
