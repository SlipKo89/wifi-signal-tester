import 'dart:async';
import 'dart:io';

import 'port_knocking.dart';
import 'router_os_transport.dart';
import 'ssh_host_key_store.dart';

/// Adds an explicitly configured port knock before a read-only transport is
/// opened, and one bounded recovery attempt after a genuine network failure.
///
/// RouterOS operations still pass through [RouterOsTransport]'s read-only
/// contract. This decorator only sends TCP/UDP packets and reconnects the same
/// selected transport; it never probes alternative management ports.
class KnockAwareTransport implements RouterOsTransport {
  final RouterOsTransport delegate;
  final String host;
  final PortKnockConfig config;
  final PortKnocker _knocker;

  int _generation = 0;
  bool _closed = true;
  Future<void>? _recovery;

  KnockAwareTransport({
    required this.delegate,
    required this.host,
    required this.config,
    PortKnocker? knocker,
  }) : _knocker = knocker ?? PortKnocker();

  @override
  String get kind => delegate.kind;

  @override
  Future<void> connect() async {
    _closed = false;
    await _knocker.knock(host, config);
    if (_closed) throw RouterOsException('Connection was closed');
    await _connectAfterKnock();
    _generation++;
  }

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  }) =>
      _withRecovery(
        () => delegate.read(menuPath, filters: filters, fields: fields),
      );

  @override
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  ) =>
      _withRecovery(() => delegate.command(path, params));

  Future<T> _withRecovery<T>(Future<T> Function() operation) async {
    final observedGeneration = _generation;
    try {
      return await operation();
    } catch (error, stackTrace) {
      if (_closed || !isRecoverableKnockFailure(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      await _recover(observedGeneration);
      return operation();
    }
  }

  Future<void> _recover(int observedGeneration) async {
    if (_closed) throw RouterOsException('Connection was closed');
    if (_generation != observedGeneration) return;

    final active = _recovery;
    if (active != null) return active;

    final recovery = _performRecovery(observedGeneration);
    _recovery = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_recovery, recovery)) _recovery = null;
    }
  }

  Future<void> _performRecovery(int observedGeneration) async {
    if (_closed || _generation != observedGeneration) return;
    await delegate.close();
    if (_closed) throw RouterOsException('Connection was closed');
    await _knocker.knock(host, config);
    if (_closed) throw RouterOsException('Connection was closed');
    await _connectAfterKnock();
    if (_closed) {
      await delegate.close();
      throw RouterOsException('Connection was closed');
    }
    _generation++;
  }

  Future<void> _connectAfterKnock() async {
    try {
      await delegate.connect();
    } catch (error, stackTrace) {
      if (isRecoverableKnockFailure(error)) {
        throw const PortKnockException(
          'The sequence was sent, but the selected service is still unreachable.',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _generation++;
    final recovery = _recovery;
    if (recovery != null) {
      try {
        await recovery;
      } catch (_) {
        // The caller is closing; a failed in-flight reconnect is irrelevant.
      }
    }
    await delegate.close();
  }
}

/// Conservative failure classifier: only network/session failures may trigger
/// a second knock. Authentication, RouterOS syntax/permission errors and an SSH
/// host-key change are intentionally never retried.
bool isRecoverableKnockFailure(Object error) {
  if (error is SshHostKeyChangedException || error is PortKnockException) {
    return false;
  }
  if (error is SocketException || error is TimeoutException) return true;

  final text = error.toString().toLowerCase();
  const networkMarkers = [
    'connection closed',
    'connection was closed',
    'transport is closed',
    'connection reset',
    'connection refused',
    'connection terminated',
    'broken pipe',
    'read timed out',
    'timed out',
    'network is unreachable',
    'no route to host',
    'failed host lookup',
    'software caused connection abort',
    'socketexception',
    'not connected',
  ];
  return networkMarkers.any(text.contains);
}
