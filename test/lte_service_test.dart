import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_service.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';

void main() {
  test('transport command gate allows monitor once and rejects writes', () {
    expect(
      () => validateReadOnlyCommand(
        '/interface/lte/monitor',
        {'numbers': 'lte1', 'once': ''},
      ),
      returnsNormally,
    );
    expect(
      () => validateReadOnlyCommand('/system/reboot', const {}),
      throwsA(isA<RouterOsException>()),
    );
    expect(
      () => validateReadOnlyCommand(
        '/interface/lte/monitor',
        {'numbers': 'lte1', 'once': '', 'set': 'anything'},
      ),
      throwsA(isA<RouterOsException>()),
    );
  });

  test('LTE auto fallback uses the first transport that can read LTE',
      () async {
    final unavailableRest = _FakeTransport(
      kind: 'REST',
      connectError: RouterOsException('REST unavailable'),
    );
    final api = _FakeTransport(
      kind: 'API',
      reads: {
        '/interface/lte': [
          {'name': 'lte-disabled', 'disabled': 'true'},
          {'name': 'lte1', 'disabled': 'false', 'running': 'true'},
        ],
        '/system/resource': [
          {'board-name': 'SXT LTE', 'cpu-load': '4'},
        ],
      },
      monitor: {
        'status': 'registered',
        'rsrp': '-96dBm',
        'rsrq': '-9dB',
        'sinr': '14dB',
      },
    );
    final service = LteService(
      transportCandidates: (_) => [unavailableRest, api],
    );

    await service.connect(const LteConnection(
      host: '192.0.2.1',
      username: 'monitor',
      password: 'secret',
    ));

    expect(unavailableRest.closed, isTrue);
    expect(service.transportKind, 'API');
    expect(service.interfaceName, 'lte1');
    expect(await service.readResource(), containsPair('board-name', 'SXT LTE'));

    final signal = await service.readSignal();
    expect(signal.rsrp, -96);
    expect(api.lastCommandPath, '/interface/lte/monitor');
    expect(api.lastCommandParams, {'numbers': 'lte1', 'once': ''});

    await service.close();
    expect(api.closed, isTrue);
  });

  test('legacy SSH-only profile keeps its transport during migration', () {
    final migrated = LteConnection.fromJson({
      'host': '192.0.2.2',
      'username': 'monitor',
      'password': 'secret',
      'port': 2222,
      'interface': 'lte1',
    });

    expect(migrated.transport, TransportPreference.ssh);
    expect(migrated.port, 2222);
    expect(migrated.interfaceName, 'lte1');
  });

  test('new LTE profile round-trips transport, TLS and custom port', () {
    const original = LteConnection(
      host: '192.0.2.3',
      username: 'monitor',
      password: 'secret',
      transport: TransportPreference.rest,
      useTls: false,
      port: 8080,
      interfaceName: 'lte-main',
    );

    final restored = LteConnection.fromJson(original.toJson());
    expect(restored.transport, TransportPreference.rest);
    expect(restored.useTls, isFalse);
    expect(restored.port, 8080);
    expect(restored.interfaceName, 'lte-main');
  });
}

class _FakeTransport implements RouterOsTransport {
  @override
  final String kind;
  final Object? connectError;
  final Map<String, List<Map<String, String>>> reads;
  final Map<String, String> monitor;

  bool closed = false;
  String? lastCommandPath;
  Map<String, String>? lastCommandParams;

  _FakeTransport({
    required this.kind,
    this.connectError,
    this.reads = const {},
    this.monitor = const {},
  });

  @override
  Future<void> connect() async {
    if (connectError != null) throw connectError!;
  }

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
  }) async =>
      reads[menuPath] ?? const [];

  @override
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  ) async {
    lastCommandPath = path;
    lastCommandParams = Map.of(params);
    return [monitor];
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
