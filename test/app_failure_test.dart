import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/diagnostics/app_failure.dart';
import 'package:wifi_apk/mikrotik/port_knocking.dart';
import 'package:wifi_apk/mikrotik/ssh_host_key_store.dart';

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

    test('port knocking has a dedicated editable failure', () {
      final failure = AppFailure.classify(
        const PortKnockException('Could not send the port-knocking sequence.'),
      );

      expect(failure.code, 'KNOCK-01');
      expect(failure.kind, AppFailureKind.portKnocking);
      expect(failure.canRetry, isTrue);
      expect(failure.wantsConnectionEdit, isTrue);
    });

    test('changed SSH host key has a dedicated non-retryable warning', () {
      final failure = AppFailure.classify(
        const SshHostKeyChangedException(
          expected: SshHostKeyRecord(
            host: '192.0.2.1',
            port: 22,
            algorithm: 'ssh-ed25519',
            fingerprint: 'SHA256:old',
          ),
          presented: SshHostKeyRecord(
            host: '192.0.2.1',
            port: 22,
            algorithm: 'ssh-ed25519',
            fingerprint: 'SHA256:new',
          ),
        ),
      );

      expect(failure.code, 'SSH-KEY-01');
      expect(failure.kind, AppFailureKind.sshHostKeyChanged);
      expect(failure.canRetry, isFalse);
      expect(failure.sshHostKeyChange?.presented.fingerprint, 'SHA256:new');
    });
  });
}
