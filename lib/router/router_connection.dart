import '../mikrotik/port_knocking.dart';
import '../mikrotik/router_os_transport.dart';

enum RouterVendor { mikrotik, keenetic }

/// Saved connection settings for a supported Wi-Fi router.
///
/// Older profiles did not contain [vendor] and therefore migrate to MikroTik.
/// Keenetic Alpha currently uses HTTPS RCI only; the RouterOS transport fields
/// stay in the shared model so mixed-vendor router lists remain possible.
class RouterConnection {
  final RouterVendor vendor;
  final String host;
  final String username;
  final String password;
  final TransportPreference transport;
  final bool useTls;
  final int? port;
  final PortKnockConfig portKnocking;

  const RouterConnection({
    this.vendor = RouterVendor.mikrotik,
    required this.host,
    required this.username,
    required this.password,
    this.transport = TransportPreference.auto,
    this.useTls = true,
    this.port,
    this.portKnocking = const PortKnockConfig.disabled(),
  });

  Map<String, dynamic> toJson() => {
        'vendor': vendor.name,
        'host': host,
        'username': username,
        'password': password,
        'transport': transport.name,
        'useTls': useTls,
        if (port != null) 'port': port,
        'portKnocking': portKnocking.toJson(),
      };

  factory RouterConnection.fromJson(Map<String, dynamic> json) =>
      RouterConnection(
        vendor: RouterVendor.values.firstWhere(
          (value) => value.name == json['vendor'],
          orElse: () => RouterVendor.mikrotik,
        ),
        host: json['host'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        transport: TransportPreference.values.firstWhere(
          (value) => value.name == json['transport'],
          orElse: () => TransportPreference.auto,
        ),
        useTls: json['useTls'] as bool? ?? true,
        port: (json['port'] as num?)?.toInt(),
        portKnocking: PortKnockConfig.fromJson(json['portKnocking']),
      );
}
