import 'dart:async';
import 'dart:io';

/// Protocol of one packet in a port-knocking sequence.
enum PortKnockProtocol { tcp, udp }

class PortKnockStep {
  final PortKnockProtocol protocol;
  final int port;

  const PortKnockStep({required this.protocol, required this.port});

  Map<String, Object> toJson() => {
        'protocol': protocol.name,
        'port': port,
      };

  static PortKnockStep? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final protocolName = value['protocol'];
    final port = (value['port'] as num?)?.toInt();
    if (protocolName is! String || port == null || port < 1 || port > 65535) {
      return null;
    }
    PortKnockProtocol? protocol;
    for (final candidate in PortKnockProtocol.values) {
      if (candidate.name == protocolName) {
        protocol = candidate;
        break;
      }
    }
    return protocol == null
        ? null
        : PortKnockStep(protocol: protocol, port: port);
  }
}

/// Port-knocking settings stored together with a router profile.
///
/// The sequence is treated like a credential and therefore only serialized
/// into the existing platform-backed secure profile stores. It must never be
/// copied to diagnostic logs or support bundles.
class PortKnockConfig {
  static const maxSteps = 8;

  final bool enabled;
  final List<PortKnockStep> steps;
  final int intervalMs;
  final int settleMs;

  const PortKnockConfig({
    this.enabled = false,
    this.steps = const [],
    this.intervalMs = 300,
    this.settleMs = 500,
  });

  const PortKnockConfig.disabled() : this();

  String? get validationError {
    if (!enabled) return null;
    if (steps.isEmpty || steps.length > maxSteps) {
      return 'A port-knocking sequence must contain 1–$maxSteps steps.';
    }
    if (steps.any((step) => step.port < 1 || step.port > 65535)) {
      return 'Every port-knocking port must be between 1 and 65535.';
    }
    if (intervalMs < 0 || intervalMs > 5000) {
      return 'The inter-step delay must be between 0 and 5000 ms.';
    }
    if (settleMs < 0 || settleMs > 10000) {
      return 'The post-knock wait must be between 0 and 10000 ms.';
    }
    return null;
  }

  PortKnockConfig copyWith({
    bool? enabled,
    List<PortKnockStep>? steps,
    int? intervalMs,
    int? settleMs,
  }) =>
      PortKnockConfig(
        enabled: enabled ?? this.enabled,
        steps: steps ?? this.steps,
        intervalMs: intervalMs ?? this.intervalMs,
        settleMs: settleMs ?? this.settleMs,
      );

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'steps': steps.map((step) => step.toJson()).toList(growable: false),
        'intervalMs': intervalMs,
        'settleMs': settleMs,
      };

  factory PortKnockConfig.fromJson(Object? value) {
    if (value is! Map) return const PortKnockConfig.disabled();
    final rawSteps = value['steps'];
    final steps = rawSteps is List
        ? rawSteps
            .map(PortKnockStep.tryFromJson)
            .whereType<PortKnockStep>()
            .take(maxSteps)
            .toList(growable: false)
        : const <PortKnockStep>[];
    return PortKnockConfig(
      enabled: value['enabled'] == true,
      steps: steps,
      intervalMs: ((value['intervalMs'] as num?)?.toInt() ?? 300)
          .clamp(0, 5000)
          .toInt(),
      settleMs:
          ((value['settleMs'] as num?)?.toInt() ?? 500).clamp(0, 10000).toInt(),
    );
  }
}

class PortKnockException implements Exception {
  final String message;
  const PortKnockException(this.message);

  @override
  String toString() => 'PortKnockException: $message';
}

typedef PortKnockLookup = Future<List<InternetAddress>> Function(String host);
typedef PortKnockSender = Future<void> Function(
  InternetAddress address,
  PortKnockStep step,
);
typedef PortKnockWait = Future<void> Function(Duration duration);

/// Sends only the explicitly configured TCP/UDP sequence to one router host.
///
/// There is no discovery or scanning here. TCP refusal/timeout is expected for
/// a closed knock port: the SYN itself is the signal RouterOS needs to see.
class PortKnocker {
  final PortKnockLookup _lookup;
  final PortKnockSender _send;
  final PortKnockWait _wait;

  PortKnocker({
    PortKnockLookup? lookup,
    PortKnockSender? send,
    PortKnockWait? wait,
  })  : _lookup = lookup ?? InternetAddress.lookup,
        _send = send ?? _sendPacket,
        _wait = wait ?? Future<void>.delayed;

  Future<void> knock(String host, PortKnockConfig config) async {
    if (!config.enabled) return;
    if (config.validationError != null) {
      throw const PortKnockException('Invalid port-knocking configuration.');
    }

    final target = _normalizeHost(host);
    if (target.isEmpty) {
      throw const PortKnockException('The port-knocking target is empty.');
    }

    List<InternetAddress> addresses;
    try {
      addresses = await _lookup(target).timeout(const Duration(seconds: 3));
    } catch (_) {
      throw const PortKnockException(
          'Could not resolve the port-knocking target.');
    }
    if (addresses.isEmpty) {
      throw const PortKnockException(
          'Could not resolve the port-knocking target.');
    }

    final address = addresses.first;
    for (var index = 0; index < config.steps.length; index++) {
      try {
        await _send(address, config.steps[index]);
      } catch (_) {
        // Deliberately omit host, protocol and port: the sequence is secret-ish
        // profile material and must not leak into diagnostics or UI exceptions.
        throw const PortKnockException(
            'Could not send the port-knocking sequence.');
      }
      if (index + 1 < config.steps.length && config.intervalMs > 0) {
        await _wait(Duration(milliseconds: config.intervalMs));
      }
    }
    if (config.settleMs > 0) {
      await _wait(Duration(milliseconds: config.settleMs));
    }
  }

  static String _normalizeHost(String host) {
    final trimmed = host.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith('[') &&
        trimmed.endsWith(']')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  static Future<void> _sendPacket(
    InternetAddress address,
    PortKnockStep step,
  ) async {
    if (step.protocol == PortKnockProtocol.tcp) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          address,
          step.port,
          timeout: const Duration(milliseconds: 400),
        );
      } on SocketException {
        // A reset/refusal/filtered timeout is normal: RouterOS has already seen
        // the incoming SYN and can advance its address-list state.
      } on TimeoutException {
        // Same as above: do not turn a closed knock port into a user-visible
        // connection error.
      } finally {
        socket?.destroy();
      }
      return;
    }

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        address.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      if (socket.send(const [0], address, step.port) <= 0) {
        throw const PortKnockException(
            'UDP packet was not accepted by the socket.');
      }
    } finally {
      socket?.close();
    }
  }
}
