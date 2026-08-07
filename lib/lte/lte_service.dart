import '../mikrotik/router_os_transport.dart';
import '../mikrotik/ssh_transport.dart';
import 'lte_signal.dart';

class LteConnection {
  final String host;
  final String username;
  final String password;
  final int port;
  final String? interfaceName;

  const LteConnection({
    required this.host,
    required this.username,
    required this.password,
    this.port = 22,
    this.interfaceName,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'username': username,
        'password': password,
        'port': port,
        if (interfaceName != null && interfaceName!.isNotEmpty)
          'interface': interfaceName,
      };

  factory LteConnection.fromJson(Map<String, dynamic> json) => LteConnection(
        host: json['host'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 22,
        interfaceName: json['interface'] as String?,
      );
}

/// Read-only LTE access over the already-whitelisted RouterOS SSH transport.
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
  SshTransport? _transport;
  String? interfaceName;

  Future<void> connect(LteConnection connection) async {
    await close();
    final transport = SshTransport(
      host: connection.host,
      username: connection.username,
      password: connection.password,
      port: connection.port,
    );
    await transport.connect();

    try {
      final interfaces = await transport.read('/interface/lte');
      final usable = interfaces
          .where((row) => row['disabled'] != 'true')
          .toList(growable: false);
      if (usable.isEmpty) {
        throw RouterOsException('No enabled LTE interface found');
      }

      final requested = connection.interfaceName?.trim();
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
      interfaceName = name;
      _transport = transport;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  Future<LteSignal> readSignal() async {
    final transport = _transport;
    final name = interfaceName;
    if (transport == null || name == null) {
      throw RouterOsException('LTE SSH session is not connected');
    }
    final rows = await transport.command(
      '/interface/lte/monitor',
      {'.id': name, 'once': ''},
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
}
