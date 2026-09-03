import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/mikrotik/ssh_host_key_store.dart';
import 'package:wifi_apk/mikrotik/ssh_transport.dart';

void main() {
  group('SSH host-key TOFU', () {
    test('remembers a first-use key only after the successful probe', () async {
      final store = _MemoryHostKeyStore();
      final transport = _transport(store);

      expect(
        await transport.verifyHostKeyForTesting('ssh-ed25519', 'SHA256:first'),
        isTrue,
      );
      expect(await store.read('192.0.2.1', 22), isNull);

      await transport.rememberFirstUseKeyForTesting();
      expect(
        (await store.read('192.0.2.1', 22))?.fingerprint,
        'SHA256:first',
      );
    });

    test('accepts the remembered key without a warning', () async {
      final store = _MemoryHostKeyStore()
        ..record = const SshHostKeyRecord(
          host: '192.0.2.1',
          port: 22,
          algorithm: 'ssh-ed25519',
          fingerprint: 'SHA256:first',
        );

      expect(
        await _transport(store)
            .verifyHostKeyForTesting('ssh-ed25519', 'SHA256:first'),
        isTrue,
      );
    });

    test('rejects a changed key and retains both fingerprints', () async {
      final store = _MemoryHostKeyStore()
        ..record = const SshHostKeyRecord(
          host: '192.0.2.1',
          port: 22,
          algorithm: 'ssh-ed25519',
          fingerprint: 'SHA256:old',
        );
      final transport = _transport(store);

      expect(
        await transport.verifyHostKeyForTesting('ssh-ed25519', 'SHA256:new'),
        isFalse,
      );
      expect(transport.rejectedHostKeyForTesting?.expected.fingerprint,
          'SHA256:old');
      expect(transport.rejectedHostKeyForTesting?.presented.fingerprint,
          'SHA256:new');
      expect(store.record?.fingerprint, 'SHA256:old');
    });
  });
}

SshTransport _transport(SshHostKeyStore store) => SshTransport(
      host: '192.0.2.1',
      username: 'monitor',
      password: 'secret',
      hostKeyStore: store,
    );

class _MemoryHostKeyStore implements SshHostKeyStore {
  SshHostKeyRecord? record;

  @override
  Future<SshHostKeyRecord?> read(String host, int port) async => record;

  @override
  Future<void> write(SshHostKeyRecord value) async => record = value;
}
