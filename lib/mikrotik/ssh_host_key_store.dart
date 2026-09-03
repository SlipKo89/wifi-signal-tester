import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One SSH host key remembered after a successful first connection.
class SshHostKeyRecord {
  final String host;
  final int port;
  final String algorithm;
  final String fingerprint;

  const SshHostKeyRecord({
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprint,
  });

  Map<String, Object> toJson() => {
        'host': host,
        'port': port,
        'algorithm': algorithm,
        'fingerprint': fingerprint,
      };

  factory SshHostKeyRecord.fromJson(Map<String, dynamic> json) =>
      SshHostKeyRecord(
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 22,
        algorithm: json['algorithm'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
      );
}

/// Raised when a host that was seen before presents another SSH key.
///
/// This is deliberately not folded into a generic SSH error: controllers use
/// the structured values to show a warning and offer an explicit trust action.
class SshHostKeyChangedException implements Exception {
  final SshHostKeyRecord expected;
  final SshHostKeyRecord presented;

  const SshHostKeyChangedException({
    required this.expected,
    required this.presented,
  });

  @override
  String toString() =>
      'SSH host key changed for ${presented.host}:${presented.port} '
      '(expected ${expected.fingerprint}, got ${presented.fingerprint})';
}

abstract interface class SshHostKeyStore {
  Future<SshHostKeyRecord?> read(String host, int port);
  Future<void> write(SshHostKeyRecord record);
}

/// TOFU known-hosts storage backed by Android Keystore / Apple Keychain.
class SecureSshHostKeyStore implements SshHostKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _prefix = 'ssh_known_host_v1_';

  const SecureSshHostKeyStore();

  @override
  Future<SshHostKeyRecord?> read(String host, int port) async {
    final raw = await _storage.read(key: _key(host, port));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final record = SshHostKeyRecord.fromJson(decoded);
      if (record.fingerprint.isEmpty || record.algorithm.isEmpty) return null;
      return record;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SshHostKeyRecord record) => _storage.write(
        key: _key(record.host, record.port),
        value: jsonEncode(record.toJson()),
      );

  static String _key(String host, int port) {
    final identity = '${host.trim().toLowerCase()}\u0000$port';
    return '$_prefix${base64Url.encode(utf8.encode(identity))}';
  }
}

/// Shared production store. Tests can inject another [SshHostKeyStore] into
/// [SshTransport], while controllers use this instance for an accepted change.
const defaultSshHostKeyStore = SecureSshHostKeyStore();

Future<void> trustChangedSshHostKey(SshHostKeyChangedException change) =>
    defaultSshHostKeyStore.write(change.presented);
