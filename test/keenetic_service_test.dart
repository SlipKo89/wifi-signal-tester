import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wifi_apk/keenetic/keenetic_compatibility.dart';
import 'package:wifi_apk/keenetic/keenetic_rci_client.dart';
import 'package:wifi_apk/keenetic/keenetic_service.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';
import 'package:wifi_apk/router/router_connection.dart';

void main() {
  test('Keenetic service maps only the selected phone station', () async {
    final service = KeeneticService(
      clientFactory: (connection) => KeeneticRciClient(
        host: connection.host,
        username: connection.username,
        password: connection.password,
        client: _fixtureClient(),
      ),
    );
    addTearDown(service.close);

    await service.connect(const RouterConnection(
      vendor: RouterVendor.keenetic,
      host: 'router.example',
      username: 'monitor',
      password: 'secret',
    ));

    expect(service.deviceModel, kKeeneticAlphaModel);
    expect(service.softwareVersion, kKeeneticAlphaRelease);
    expect(service.compatibilityVerified, isTrue);

    final mac = await service.resolveMacForIp('192.168.1.25');
    expect(mac, 'AA:BB:CC:DD:EE:25');
    final station = await service.fetchStation(mac!);
    expect(station, isNotNull);
    expect(station!.macAddress, 'AA:BB:CC:DD:EE:25');
    expect(station.signalDbm, -57);
    expect(station.txRate, '866 Mbps');
    expect(station.rxRate, '585 Mbps');
    expect(station.interfaceName, 'WifiMaster1/AccessPoint0');
    expect(station.uptime, '1h1m');
    expect(station.security, 'WPA2-PSK');
    expect(station.pmf, isTrue);
    expect(station.spatialStreams, 2);
    expect(station.channelWidthMhz, 80);
    expect(station.mcs, 9);

    // Another associated station was present in the RCI response, but the
    // service returns no data unless its exact MAC is explicitly requested.
    expect(await service.fetchStation('11:22:33:44:55:66'), isNotNull);
    expect(await service.fetchStation('00:00:00:00:00:00'), isNull);

    expect(await service.readResource(), containsPair('cpu-load', '27'));
    expect(
      await service.readResource(),
      containsPair('board-name', kKeeneticAlphaModel),
    );
  });

  test('legacy connection profiles default to MikroTik', () {
    final connection = RouterConnection.fromJson({
      'host': '192.168.88.1',
      'username': 'monitor',
      'password': 'secret',
      'transport': TransportPreference.auto.name,
    });
    expect(connection.vendor, RouterVendor.mikrotik);
  });
}

MockClient _fixtureClient() => MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth') {
        return http.Response('', 401, headers: {
          'x-ndm-realm': 'realm',
          'x-ndm-challenge': 'challenge',
          'set-cookie': 'session=value; Path=/',
        });
      }
      if (request.method == 'POST' && request.url.path == '/auth') {
        return http.Response('{}', 200);
      }
      final fixture = switch (request.url.path) {
        '/rci/show/version' => {
            'vendor': 'Keenetic',
            'model': kKeeneticAlphaModel,
            'release': kKeeneticAlphaRelease,
          },
        '/rci/show/ip/dhcp/bindings' => {
            'lease': [
              {
                'ip': '192.168.1.25',
                'mac': 'AA:BB:CC:DD:EE:25',
                'hostname': 'phone',
              },
              {
                'ip': '192.168.1.44',
                'mac': '11:22:33:44:55:66',
                'hostname': 'laptop',
              },
            ],
          },
        '/rci/show/associations' => {
            'station': [
              {
                'mac': 'AA:BB:CC:DD:EE:25',
                'rssi': -57,
                'txrate': 866,
                'rxrate': 585,
                'ap': 'WifiMaster1/AccessPoint0',
                'uptime': 3661,
                'txbytes': 1000,
                'rxbytes': 2000,
                'mode': '11ax',
                'security': 'WPA2-PSK',
                'pmf': true,
                'txss': 2,
                'ht': 80,
                'mcs': 9,
                'gi': 800,
              },
              {
                'mac': '11:22:33:44:55:66',
                'rssi': -70,
              },
            ],
          },
        '/rci/show/system' => {
            'cpuload': 27,
            'uptime': 90061,
            'memory': '40820/131072',
          },
        _ => throw StateError('Unexpected fixture path ${request.url.path}'),
      };
      return http.Response(jsonEncode(fixture), 200);
    });
