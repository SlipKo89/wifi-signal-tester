import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/models/device_identity.dart';

void main() {
  group('DeviceIdentity', () {
    test('prefers operator comments over a DHCP hostname', () {
      const identity = DeviceIdentity(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        dhcpHostName: 'android-1234',
        dhcpComment: 'John phone',
        accessListComment: 'Warehouse scanner',
      );

      expect(identity.displayName, 'Warehouse scanner');
    });

    test('uses DHCP comment before hostname when access-list has no label', () {
      const identity = DeviceIdentity(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        dhcpHostName: 'ESP-A1B2',
        dhcpComment: 'Kitchen sensor',
      );

      expect(identity.displayName, 'Kitchen sensor');
    });

    test('cleans and merges access-list comments without duplicates', () {
      expect(
        DeviceIdentity.mergeComments([
          '-= Camera entrance =-',
          'Camera entrance',
          '5 GHz rule',
        ]),
        'Camera entrance · 5 GHz rule',
      );
    });

    test('search covers comments, hostname, IP and MAC', () {
      const identity = DeviceIdentity(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        ipAddress: '192.168.88.42',
        dhcpHostName: 'pixel-9',
        dhcpComment: 'Guest phone',
        accessListComment: 'Test device',
      );

      for (final query in ['guest', 'pixel', '88.42', 'dd:ee', 'test']) {
        expect(identity.matches(query), isTrue, reason: query);
      }
    });

    test('covers every RouterOS wireless access-list generation', () {
      expect(kDeviceAccessListPaths, [
        '/caps-man/access-list',
        '/interface/wireless/access-list',
        '/interface/wifi/access-list',
      ]);
    });
  });
}
