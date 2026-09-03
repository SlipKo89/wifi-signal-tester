import '../models/station_signal.dart';
import '../router/router_connection.dart';
import '../router/wifi_router_service.dart';
import 'keenetic_compatibility.dart';
import 'keenetic_rci_client.dart';

typedef KeeneticRciFactory = KeeneticRciClient Function(
  RouterConnection connection,
);

/// Read-only Keenetic Alpha adapter for the two-sided Wi-Fi dashboard.
class KeeneticService implements WifiRouterService {
  final KeeneticRciFactory _clientFactory;
  KeeneticRciClient? _client;

  KeeneticService({KeeneticRciFactory? clientFactory})
      : _clientFactory = clientFactory ?? _defaultClient;

  @override
  RouterVendor get vendor => RouterVendor.keenetic;
  @override
  String? host;
  @override
  String? get transportKind => _client?.kind;
  @override
  String get stackLabel => 'Keenetic Alpha';
  @override
  String get platformLabel => 'KeeneticOS';
  @override
  bool get alphaIntegration => true;
  @override
  String? deviceModel;
  @override
  String? softwareVersion;
  @override
  bool get compatibilityVerified => isVerifiedKeeneticAlpha(
        model: deviceModel,
        release: softwareVersion,
      );

  static KeeneticRciClient _defaultClient(RouterConnection connection) =>
      KeeneticRciClient(
        host: connection.host,
        username: connection.username,
        password: connection.password,
        useTls: connection.useTls,
        port: connection.port,
      );

  @override
  Future<void> connect(RouterConnection connection) async {
    await close();
    final client = _clientFactory(connection);
    try {
      await client.connect();
      final version = await client.getObject('/rci/show/version');
      if ((version['vendor'] ?? '').toString().toLowerCase() != 'keenetic') {
        throw const RouterAccessException(
          'The RCI endpoint did not identify as Keenetic',
        );
      }
      host = connection.host;
      deviceModel = _text(version['model']) ?? _text(version['device']);
      softwareVersion = _text(version['release']);
      _client = client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  @override
  String? apNameForBssid(String? bssid) => null;

  @override
  int? noiseFloorForFreq(int? mhz) => null;

  @override
  Future<String?> resolveMacForIp(String ip) async {
    final client = _requireClient();
    final bindings = await client.getObject('/rci/show/ip/dhcp/bindings');
    final fromDhcp = _macForIp(_records(bindings, 'lease'), ip);
    if (fromDhcp != null) return fromDhcp;
    try {
      final arp = await client.getObject('/rci/show/ip/arp');
      return _macForIp(
        [
          ..._records(arp, 'host'),
          ..._records(arp, 'arp'),
        ],
        ip,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StationSignal?> fetchStation(String mac) async {
    final root = await _requireClient().getObject('/rci/show/associations');
    final target = mac.toLowerCase();
    for (final row in _records(root, 'station')) {
      if ((_text(row['mac']) ?? '').toLowerCase() != target) continue;
      return StationSignal(
        macAddress: _text(row['mac']) ?? '',
        signalDbm: _integer(row['rssi']),
        txRate: _rate(row['txrate']),
        rxRate: _rate(row['rxrate']),
        interfaceName: _text(row['ap']),
        uptime: _duration(_integer(row['uptime'])),
        apTxBytes: _integer(row['txbytes']),
        apRxBytes: _integer(row['rxbytes']),
        wifiMode: _text(row['mode']),
        security: _text(row['security']),
        pmf: row['pmf'] is bool ? row['pmf'] as bool : null,
        spatialStreams: _integer(row['txss']),
        channelWidthMhz: _integer(row['ht']),
        mcs: _integer(row['mcs']),
        guardIntervalNs: _integer(row['gi']),
      );
    }
    return null;
  }

  @override
  Future<Map<String, String>?> readResource() async {
    final system = await _requireClient().getObject('/rci/show/system');
    return {
      if (deviceModel != null) 'board-name': deviceModel!,
      if (softwareVersion != null) 'version': softwareVersion!,
      if (_text(system['cpuload']) != null)
        'cpu-load': _text(system['cpuload'])!,
      if (_duration(_integer(system['uptime'])) != null)
        'uptime': _duration(_integer(system['uptime']))!,
      if (_text(system['memory']) != null) 'memory': _text(system['memory'])!,
    };
  }

  KeeneticRciClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const RouterAccessException('Keenetic RCI is not connected');
    }
    return client;
  }

  static String? _macForIp(List<Map<String, dynamic>> rows, String ip) {
    for (final row in rows) {
      if (_text(row['ip']) == ip || _text(row['address']) == ip) {
        final mac = _text(row['mac']);
        if (mac != null) return mac;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _records(
    Map<String, dynamic> root,
    String key,
  ) {
    final value = root[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((row) => row.map(
                (rowKey, rowValue) => MapEntry(rowKey.toString(), rowValue),
              ))
          .toList();
    }
    if (value is Map) {
      return [
        value.map(
          (rowKey, rowValue) => MapEntry(rowKey.toString(), rowValue),
        ),
      ];
    }
    return const [];
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(_text(value) ?? '');
  }

  static String? _rate(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    return RegExp(r'[A-Za-z]').hasMatch(text) ? text : '$text Mbps';
  }

  static String? _duration(int? seconds) {
    if (seconds == null) return null;
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return [
      if (days > 0) '${days}d',
      if (hours > 0) '${hours}h',
      if (minutes > 0) '${minutes}m',
      if (days == 0 && hours == 0) '${secs}s',
    ].join();
  }

  @override
  Future<void> close() async {
    _client?.close();
    _client = null;
    host = null;
    deviceModel = null;
    softwareVersion = null;
  }
}
