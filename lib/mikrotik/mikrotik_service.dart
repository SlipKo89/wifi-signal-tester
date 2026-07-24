import '../models/station_signal.dart';
import '../models/wireless_stack.dart';
import 'binary_api_transport.dart';
import 'rest_transport.dart';
import 'router_os_transport.dart';

/// Connection settings for a router.
class RouterConnection {
  final String host;
  final String username;
  final String password;

  /// Preferred transport; the service falls back to the other one on failure.
  final TransportPreference transport;
  final bool useTls;

  const RouterConnection({
    required this.host,
    required this.username,
    required this.password,
    this.transport = TransportPreference.auto,
    this.useTls = true,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'username': username,
        'password': password,
        'transport': transport.name,
        'useTls': useTls,
      };

  factory RouterConnection.fromJson(Map<String, dynamic> j) => RouterConnection(
        host: j['host'] as String,
        username: j['username'] as String,
        password: j['password'] as String,
        transport: TransportPreference.values.firstWhere(
          (t) => t.name == j['transport'],
          orElse: () => TransportPreference.auto,
        ),
        useTls: j['useTls'] as bool? ?? true,
      );
}

enum TransportPreference { auto, rest, binary }

/// High-level, read-only orchestration over a [RouterOsTransport]:
/// picks a transport, detects the wireless stack, and returns the signal for
/// exactly one MAC (ours).
class MikrotikService {
  RouterOsTransport? _transport;

  /// The router this service talks to (host is used as a label).
  String? host;

  /// Every registration table the router actually exposes (an endpoint can
  /// answer 200 yet be empty — e.g. a WifiWave2 table on a legacy+CAPsMAN box).
  final List<WirelessStack> _availableStacks = [];

  /// Radio/BSSID MAC → AP name, so a phone's BSSID can be mapped to an AP even
  /// before it shows up in a registration table.
  final Map<String, String> _bssidToAp = {};

  /// The stack where the client was last found — for UI labelling and to probe
  /// first next time (roaming-friendly).
  WirelessStack? _stack;

  /// Measured noise floor (dBm) of this router's own radios, per band. Used to
  /// estimate SNR where the registration table doesn't report it (CAPsMAN).
  int? _nf2g;
  int? _nf5g;

  WirelessStack? get stack => _stack;
  String? get transportKind => _transport?.kind;

  /// AP name for a BSSID the phone reports, if this router owns that radio.
  String? apNameForBssid(String? bssid) =>
      bssid == null ? null : _bssidToAp[bssid.toLowerCase()];

  /// Reads any menu directly (read-only) — used by the config audit.
  Future<List<Map<String, String>>> readMenu(String path) async {
    final t = _transport;
    if (t == null) throw RouterOsException('Not connected');
    return t.read(path);
  }

  /// Noise floor for the band of [mhz], falling back to the other band.
  int? noiseFloorForFreq(int? mhz) {
    if (mhz != null && mhz >= 4900) return _nf5g ?? _nf2g;
    return _nf2g ?? _nf5g;
  }

  /// Connects using the preferred transport, falling back to the other.
  Future<void> connect(RouterConnection cfg) async {
    host = cfg.host;
    final attempts = <RouterOsTransport>[];
    switch (cfg.transport) {
      case TransportPreference.rest:
        attempts.add(_rest(cfg));
        break;
      case TransportPreference.binary:
        attempts.add(_binary(cfg));
        break;
      case TransportPreference.auto:
        attempts.add(_rest(cfg));
        attempts.add(_binary(cfg));
        break;
    }

    Object? lastError;
    for (final t in attempts) {
      try {
        await t.connect();
        _transport = t;
        await _detectStacks();
        await _loadBssidMap();
        await _loadNoiseFloor();
        return;
      } catch (e) {
        lastError = e;
        await t.close();
      }
    }
    throw RouterOsException('Could not connect: ${lastError ?? 'unknown'}');
  }

  RestTransport _rest(RouterConnection cfg) => RestTransport(
        host: cfg.host,
        username: cfg.username,
        password: cfg.password,
        useTls: cfg.useTls,
      );

  BinaryApiTransport _binary(RouterConnection cfg) => BinaryApiTransport(
        host: cfg.host,
        username: cfg.username,
        password: cfg.password,
        useTls: cfg.useTls,
      );

  Future<void> _detectStacks() async {
    final t = _transport!;
    _availableStacks.clear();
    for (final candidate in kStackProbeOrder) {
      try {
        await t.read(candidate.registrationPath);
        _availableStacks.add(candidate);
      } catch (_) {
        // Menu doesn't exist on this stack — try the next.
      }
    }
    if (_availableStacks.isEmpty) {
      throw RouterOsException('No wireless registration table found');
    }
  }

  /// Builds the BSSID/radio-MAC → AP-name map from whichever interface menus
  /// exist. Best-effort: any menu that isn't present is skipped.
  Future<void> _loadBssidMap() async {
    _bssidToAp.clear();
    Future<void> harvest(String menu, String nameKey) async {
      try {
        for (final row in await _transport!.read(menu)) {
          final name = row[nameKey] ?? row['name'];
          if (name == null || name.isEmpty) continue;
          for (final macKey in ['mac-address', 'radio-mac', 'bssid']) {
            final mac = row[macKey];
            if (mac != null &&
                mac.isNotEmpty &&
                mac != '00:00:00:00:00:00') {
              _bssidToAp[mac.toLowerCase()] = name;
            }
          }
        }
      } catch (_) {
        // Menu absent on this stack.
      }
    }

    await harvest('/caps-man/interface', 'name');
    await harvest('/interface/wireless', 'name');
    await harvest('/interface/wifi', 'name');
  }

  /// Reads the noise floor of this router's own radios via `monitor once`.
  /// Best-effort; a manager with no local radios simply yields nothing.
  Future<void> _loadNoiseFloor() async {
    _nf2g = null;
    _nf5g = null;
    for (final menu in ['/interface/wireless', '/interface/wifi']) {
      try {
        for (final iface in await _transport!.read(menu)) {
          final name = iface['name'];
          if (name == null || name.isEmpty) continue;
          try {
            final mon = await _transport!
                .command('$menu/monitor', {'.id': name, 'once': ''});
            if (mon.isEmpty) continue;
            final nf = _parseInt(mon.first['noise-floor']);
            if (nf == null) continue;
            final is5 = '${iface['band']} $name'.contains('5');
            if (is5) {
              _nf5g = nf;
            } else {
              _nf2g = nf;
            }
          } catch (_) {
            // monitor not supported for this interface — skip.
          }
        }
      } catch (_) {
        // Menu absent.
      }
    }
  }

  int? _parseInt(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'-?\d+').firstMatch(raw);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  /// Resolves our MAC from our IP via ARP, then DHCP leases as a fallback.
  Future<String?> resolveMacForIp(String ip) async {
    final t = _transport!;
    final arp = await t.read('/ip/arp');
    final byArp = _matchIp(arp, ip);
    if (byArp != null) return byArp;

    try {
      final leases = await t.read('/ip/dhcp-server/lease');
      return _matchIp(leases, ip);
    } catch (_) {
      return null;
    }
  }

  String? _matchIp(List<Map<String, String>> rows, String ip) {
    for (final row in rows) {
      if (row['address'] == ip) {
        final mac = row['mac-address'];
        if (mac != null && mac.isNotEmpty) return mac;
      }
    }
    return null;
  }

  /// Finds the registration entry for one MAC across every available stack.
  ///
  /// With CAPsMAN + roaming the client hops between APs and even stacks, and
  /// some tables answer 200-but-empty, so we search them all (last-found first)
  /// instead of committing to one. Matches case-insensitively and locally —
  /// registration tables are tiny.
  Future<StationSignal?> fetchStation(String mac) async {
    final t = _transport!;
    final target = mac.toLowerCase();
    final order = <WirelessStack>[
      if (_stack != null) _stack!,
      for (final s in _availableStacks) if (s != _stack) s,
    ];
    for (final stack in order) {
      final rows = await t.read(stack.registrationPath);
      for (final row in rows) {
        if ((row['mac-address'] ?? '').toLowerCase() == target) {
          _stack = stack;
          return StationSignal.fromRecord(row, stack);
        }
      }
    }
    return null;
  }

  Future<void> close() async {
    await _transport?.close();
    _transport = null;
    _stack = null;
    _availableStacks.clear();
    _bssidToAp.clear();
  }
}
