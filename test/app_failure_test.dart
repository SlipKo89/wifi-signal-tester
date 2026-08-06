import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/diagnostics/app_failure.dart';

void main() {
  group('AppFailure.classify', () {
    test('uses stable codes for actionable failures', () {
      expect(
        AppFailure.classify('HTTP 401 authentication failed').code,
        'AUTH-01',
      );
      expect(AppFailure.classify(TimeoutException('late')).code, 'NET-03');
      expect(
        AppFailure.classify(const SocketException('Connection refused')).code,
        'NET-02',
      );
      expect(
        AppFailure.classify('TLS certificate handshake failed').code,
        'TLS-01',
      );
      expect(
        AppFailure.classify('RouterOsException: Connection closed').code,
        'SESSION-01',
      );
    });

    test('station failures distinguish known and unmanaged APs', () {
      expect(AppFailure.station(knownAp: true).code, 'STATION-01');
      expect(AppFailure.station(knownAp: false).code, 'STATION-02');
    });
  });
}
