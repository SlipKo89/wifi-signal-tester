import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/l10n/l10n.dart';
import 'package:wifi_apk/mikrotik/knock_aware_transport.dart';
import 'package:wifi_apk/mikrotik/port_knocking.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';
import 'package:wifi_apk/router/router_connection.dart';
import 'package:wifi_apk/ui/theme.dart';
import 'package:wifi_apk/ui/widgets/port_knocking_editor.dart';

void main() {
  const config = PortKnockConfig(
    enabled: true,
    steps: [
      PortKnockStep(protocol: PortKnockProtocol.tcp, port: 1234),
      PortKnockStep(protocol: PortKnockProtocol.udp, port: 5678),
    ],
    intervalMs: 300,
    settleMs: 500,
  );

  test('knocker sends the configured sequence in order and waits', () async {
    final sent = <String>[];
    final waits = <Duration>[];
    final knocker = PortKnocker(
      lookup: (_) async => [InternetAddress('192.0.2.1')],
      send: (_, step) async => sent.add('${step.protocol.name}:${step.port}'),
      wait: (duration) async => waits.add(duration),
    );

    await knocker.knock('router.example', config);

    expect(sent, ['tcp:1234', 'udp:5678']);
    expect(waits, const [
      Duration(milliseconds: 300),
      Duration(milliseconds: 500),
    ]);
  });

  test('knocker errors never disclose the sequence', () async {
    final knocker = PortKnocker(
      lookup: (_) async => [InternetAddress('192.0.2.1')],
      send: (_, __) async => throw const SocketException('failed'),
      wait: (_) async {},
    );

    Object? error;
    try {
      await knocker.knock('router.example', config);
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<PortKnockException>());
    expect(error.toString(), isNot(contains('1234')));
    expect(error.toString(), isNot(contains('5678')));
    expect(error.toString(), isNot(contains('router.example')));
  });

  test('transport knocks initially and once after a dropped session', () async {
    final delegate = _FakeTransport(failFirstRead: true);
    var knocks = 0;
    final transport = KnockAwareTransport(
      delegate: delegate,
      host: 'router.example',
      config: config,
      knocker: PortKnocker(
        lookup: (_) async => [InternetAddress('192.0.2.1')],
        send: (_, __) async => knocks++,
        wait: (_) async {},
      ),
    );

    await transport.connect();
    final rows = await transport.read('/system/resource');

    expect(rows.single['ok'], 'true');
    expect(knocks, 4); // Two packets before each of two connections.
    expect(delegate.connects, 2);
    expect(delegate.reads, 2);
  });

  test('transport never re-knocks after an authentication error', () async {
    final delegate = _FakeTransport(
      readError: RouterOsException('Authentication failed (401)'),
    );
    var knocks = 0;
    final transport = KnockAwareTransport(
      delegate: delegate,
      host: 'router.example',
      config: config,
      knocker: PortKnocker(
        lookup: (_) async => [InternetAddress('192.0.2.1')],
        send: (_, __) async => knocks++,
        wait: (_) async {},
      ),
    );

    await transport.connect();
    await expectLater(
      transport.read('/system/resource'),
      throwsA(isA<RouterOsException>()),
    );

    expect(knocks, 2);
    expect(delegate.connects, 1);
    expect(delegate.reads, 1);
  });

  test('unreachable service after the initial sequence is a knock failure',
      () async {
    final delegate = _FakeTransport(
      connectError: const SocketException('Connection refused'),
    );
    final transport = KnockAwareTransport(
      delegate: delegate,
      host: 'router.example',
      config: config,
      knocker: PortKnocker(
        lookup: (_) async => [InternetAddress('192.0.2.1')],
        send: (_, __) async {},
        wait: (_) async {},
      ),
    );

    await expectLater(
      transport.connect(),
      throwsA(isA<PortKnockException>()),
    );
    expect(delegate.connects, 1);
  });

  test('Wi-Fi profile round-trips knocking inside the secure payload', () {
    const original = RouterConnection(
      host: '192.0.2.5',
      username: 'monitor',
      password: 'secret',
      transport: TransportPreference.binary,
      portKnocking: config,
    );

    final restored = RouterConnection.fromJson(original.toJson());

    expect(restored.portKnocking.enabled, isTrue);
    expect(restored.portKnocking.steps, hasLength(2));
    expect(restored.portKnocking.steps.last.protocol, PortKnockProtocol.udp);
    expect(restored.portKnocking.steps.last.port, 5678);
    expect(restored.portKnocking.intervalMs, 300);
    expect(restored.portKnocking.settleMs, 500);
  });

  test('invalid stored steps are discarded safely', () {
    final restored = PortKnockConfig.fromJson({
      'enabled': true,
      'steps': [
        {'protocol': 'tcp', 'port': 0},
        {'protocol': 'other', 'port': 1234},
      ],
      'intervalMs': -100,
      'settleMs': 99999,
    });

    expect(restored.enabled, isTrue);
    expect(restored.steps, isEmpty);
    expect(restored.intervalMs, 0);
    expect(restored.settleMs, 10000);
    expect(restored.validationError, isNotNull);
  });

  testWidgets('editor conceals ports by default and fits a narrow screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PortKnockingEditor(
            value: config,
            l: const L10n(false),
            onChanged: (_) {},
          ),
        ),
      ),
    ));

    expect(find.textContaining('TCP · ••••'), findsOneWidget);
    expect(find.textContaining('1234'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Show ports'));
    await tester.pump();
    expect(find.textContaining('TCP · 1234'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeTransport implements RouterOsTransport {
  final bool failFirstRead;
  final Object? readError;
  final Object? connectError;
  int connects = 0;
  int reads = 0;

  _FakeTransport({
    this.failFirstRead = false,
    this.readError,
    this.connectError,
  });

  @override
  String get kind => 'FAKE';

  @override
  Future<void> connect() async {
    connects++;
    if (connectError != null) throw connectError!;
  }

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  }) async {
    reads++;
    if (readError != null) throw readError!;
    if (failFirstRead && reads == 1) {
      throw RouterOsException('Connection closed');
    }
    return [
      const {'ok': 'true'}
    ];
  }

  @override
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  ) async =>
      const [];

  @override
  Future<void> close() async {}
}
