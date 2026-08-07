import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/services/ping_service.dart';

void main() {
  test('unsupported platforms never start a ping probe', () async {
    final service = PingService(supported: false);

    expect(service.isSupported, isFalse);
    expect(await service.pingOnce('192.0.2.1'), isNull);
    await service.cancel();
  });
}
