import '../mikrotik/binary_api_transport.dart';
import '../mikrotik/rest_transport.dart';
import '../mikrotik/router_os_transport.dart';
import '../mikrotik/ssh_transport.dart';
import 'lte_signal.dart';

class LteConnection {
  final String host;
  final String username;
  final String password;
  final TransportPreference transport;
  final bool useTls;
  final int? port;
  final String? interfaceName;

  const LteConnection({
    required this.host,
    required this.username,
    required this.password,
    this.transport = TransportPreference.auto,
    this.useTls = true,
    this.port,
    this.interfaceName,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'username': username,
        'password': password,
        'transport': transport.name,
        'useTls': useTls,
        if (port != null) 'port': port,
        if (interfaceName != null && interfaceName!.isNotEmpty)
          'interface': interfaceName,
      };

  factory LteConnection.fromJson(Map<String, dynamic> json) {
    final savedTransport = json['transport'] as String?;
    // v1 profiles were SSH-only and contained just port 22. Keep them working
    // instead of silently reinterpreting that port as an automatic profile.
    final transport = savedTransport == null
        ? TransportPreference.ssh
        : TransportPreference.values.firstWhere(
            (value) => value.name == savedTransport,
            orElse: () => TransportPreference.auto,
          );
    return LteConnection(
      host: json['host'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      transport: transport,
      useTls: json['useTls'] as bool? ?? true,
      port: (json['port'] as num?)?.toInt(),
      interfaceName: json['interface'] as String?,
    );
  }
}

typedef LteTransportCandidates = List<RouterOsTransport> Function(
  LteConnection connection,
);

/// Read-only LTE access over REST, binary API or the whitelisted SSH transport.
///
/// Only these commands can be reached:
/// - `/interface lte print`
/// - `/interface lte monitor <name> once`
/// - `/system resource print`
///
/// The monitor response contains SIM/modem identifiers on many devices. It is
/// immediately reduced to [LteSignal], which deliberately has no IMEI/IMSI/
/// ICCID fields and is never persisted.
class LteService {
  final LteTransportCandidates _transportCandidates;
  RouterOsTransport? _transport;
  String? interfaceName;

  LteService({LteTransportCandidates? transportCandidates})
      : _transportCandidates = transportCandidates ?? _defaultCandidates;

  String? get transportKind => _transport?.kind;

  Future<void> connect(LteConnection connection) async {
    await close();
    Object? lastError;
    for (final transport in _transportCandidates(connection)) {
      try {
        await transport.connect();
        final selected =
            await _selectInterface(transport, connection.interfaceName);
        _transport = transport;
        interfaceName = selected;
        return;
      } catch (error) {
        lastError = error;
        await transport.close();
      }
    }
    throw RouterOsException(
      'Could not connect to the LTE router: ${lastError ?? 'unknown error'}',
    );
  }

  Future<LteSignal> readSignal() async {
    final transport = _transport;
    final name = interfaceName;
    if (transport == null || name == null) {
      throw RouterOsException('LTE router is not connected');
    }
    final rows = await transport.command(
      '/interface/lte/monitor',
      {'numbers': name, 'once': ''},
    );
    if (rows.isEmpty) {
      throw RouterOsException('LTE monitor returned no data');
    }
    return LteSignal.fromMonitor(rows.first, interfaceName: name);
  }

  Future<Map<String, String>?> readResource() async {
    final transport = _transport;
    if (transport == null) return null;
    try {
      final rows = await transport.read('/system/resource');
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    await _transport?.close();
    _transport = null;
    interfaceName = null;
  }

  static List<RouterOsTransport> _defaultCandidates(
    LteConnection connection,
  ) {
    RouterOsTransport rest() => RestTransport(
          host: connection.host,
          username: connection.username,
          password: connection.password,
          useTls: connection.useTls,
          port: _portFor(connection, TransportPreference.rest),
        );
    RouterOsTransport binary() => BinaryApiTransport(
          host: connection.host,
          username: connection.username,
          password: connection.password,
          useTls: connection.useTls,
          port: _portFor(connection, TransportPreference.binary),
        );
    RouterOsTransport ssh() => SshTransport(
          host: connection.host,
          username: connection.username,
          password: connection.password,
          port: _portFor(connection, TransportPreference.ssh),
        );

    return switch (connection.transport) {
      TransportPreference.rest => [rest()],
      TransportPreference.binary => [binary()],
      TransportPreference.ssh => [ssh()],
      TransportPreference.auto => [rest(), binary(), ssh()],
    };
  }

  static int? _portFor(
    LteConnection connection,
    TransportPreference transport,
  ) =>
      connection.transport == transport ? connection.port : null;

  Future<String> _selectInterface(
    RouterOsTransport transport,
    String? requestedInterface,
  ) async {
    final interfaces = await transport.read('/interface/lte');
    final usable = interfaces
        .where((row) => row['disabled'] != 'true')
        .toList(growable: false);
    if (usable.isEmpty) {
      throw RouterOsException('No enabled LTE interface found');
    }

    final requested = requestedInterface?.trim();
    Map<String, String>? selected;
    if (requested != null && requested.isNotEmpty) {
      for (final row in usable) {
        if (row['name'] == requested || row['default-name'] == requested) {
          selected = row;
          break;
        }
      }
      if (selected == null) {
        throw RouterOsException('LTE interface "$requested" was not found');
      }
    } else {
      for (final row in usable) {
        if (row['running'] == 'true') {
          selected = row;
          break;
        }
      }
      selected ??= usable.first;
    }

    final name = selected['name'] ?? selected['default-name'];
    if (name == null || name.isEmpty) {
      throw RouterOsException('LTE interface has no name');
    }
    return name;
  }
}
