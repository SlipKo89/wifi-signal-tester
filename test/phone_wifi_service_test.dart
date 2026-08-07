import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/services/phone_wifi_service.dart';

void main() {
  test('macOS adapter reads finish when CoreWLAN facts stall', () async {
    final never = Completer<String?>().future;
    final service = PhoneWifiService(
      isMacOS: true,
      queryTimeout: const Duration(milliseconds: 20),
      wifiNameReader: () => never,
      wifiBssidReader: () => never,
      wifiIpReader: () async => '192.0.2.25',
    );

    final signal = await service.read().timeout(const Duration(seconds: 1));

    expect(signal.ipAddress, '192.0.2.25');
    expect(signal.ssid, isNull);
    expect(signal.bssid, isNull);
    expect(signal.rssiDbm, isNull);
    expect(signal.gatewayIp, isNull);
  });
}
