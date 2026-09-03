import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/audit/audit.dart';
import 'package:wifi_apk/lte/lte_audit.dart';
import 'package:wifi_apk/lte/lte_controller.dart';
import 'package:wifi_apk/lte/lte_service.dart';
import 'package:wifi_apk/lte/lte_signal.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/lte_audit_screen.dart';
import 'package:wifi_apk/ui/theme.dart';

void main() {
  test('healthy primary LTE configuration produces no warnings', () async {
    final transport = _AuditTransport(_healthyMenus());
    final service = await _connectedService(transport);

    final findings = await LteAuditEngine().run(
      service,
      role: LteAuditRole.primary,
      signal: _registeredSignal(),
    );

    expect(
      findings.where((finding) =>
          finding.sev == AuditSeverity.critical ||
          finding.sev == AuditSeverity.warn),
      isEmpty,
    );
    expect(
        _finding(findings, 'LTE interface is enabled').sev, AuditSeverity.ok);
    expect(_finding(findings, 'APN profile resolved: uplink').sev,
        AuditSeverity.ok);
    expect(_finding(findings, 'LTE default route is enabled').sev,
        AuditSeverity.ok);
    expect(_finding(findings, 'LTE MTU is automatic').sev, AuditSeverity.ok);
  });

  test('flags APN conflict, unsafe passthrough, IPv6 gap and invalid MTU',
      () async {
    final menus = _healthyMenus();
    menus['/interface/lte'] = [
      {
        'name': 'lte1',
        'disabled': 'false',
        'running': 'true',
        'apn-profiles': 'uplink',
        'band': '7',
        'mtu': '1200',
      },
    ];
    menus['/interface/lte/apn'] = [
      {
        'name': 'uplink',
        'apn': 'private.operator',
        'use-network-apn': 'true',
        'authentication': 'none',
        'add-default-route': 'true',
        'default-route-distance': '1',
        'ip-type': 'ipv4-ipv6',
        'passthrough-interface': 'ether1',
        'passthrough-mac': 'auto',
      },
    ];
    menus['/ipv6/firewall/filter'] = [];
    final service = await _connectedService(_AuditTransport(menus));

    final findings = await LteAuditEngine().run(
      service,
      role: LteAuditRole.passthrough,
      signal: _registeredSignal(),
    );

    expect(
        _finding(findings, 'Manual APN may be overridden by the network').sev,
        AuditSeverity.warn);
    expect(
      _finding(findings, 'Passthrough learns the first client automatically')
          .sev,
      AuditSeverity.warn,
    );
    expect(
      _finding(
              findings, 'IPv6 requested, but no active IPv6 filter rules found')
          .sev,
      AuditSeverity.warn,
    );
    expect(_finding(findings, 'MTU 1200 is too small for IPv6').sev,
        AuditSeverity.critical);
    expect(_finding(findings, 'Radio selection is restricted').sev,
        AuditSeverity.info);
  });

  test('missing applied APN profile is a real configuration error', () async {
    final menus = _healthyMenus();
    menus['/interface/lte'] = [
      {
        'name': 'lte1',
        'disabled': 'false',
        'running': 'true',
        'apn-profiles': 'missing-profile',
      },
    ];
    final service = await _connectedService(_AuditTransport(menus));

    final findings = await LteAuditEngine().run(
      service,
      role: LteAuditRole.general,
      signal: _registeredSignal(),
    );

    expect(
        _finding(findings, 'APN profile "missing-profile" was not found').sev,
        AuditSeverity.critical);
  });

  test('an unreadable APN menu is reported as a gap, not a missing profile',
      () async {
    final transport = _AuditTransport(
      _healthyMenus(),
      failPaths: {'/interface/lte/apn'},
    );
    final service = await _connectedService(transport);

    final findings = await LteAuditEngine().run(
      service,
      role: LteAuditRole.general,
      signal: _registeredSignal(),
    );

    expect(
        findings.any((finding) => finding.titleEn == 'LTE audit is incomplete'),
        isTrue);
    expect(
      findings.any((finding) => finding.titleEn.contains('was not found')),
      isFalse,
    );
  });

  test('RouterOS 6 skips v7-only settings and network APN grading', () async {
    final menus = _healthyMenus();
    menus['/system/resource'] = [
      {'board-name': 'SXT LTE', 'version': '6.49.18', 'uptime': '1d'},
    ];
    final transport = _AuditTransport(menus);
    final service = await _connectedService(transport);

    final findings = await LteAuditEngine().run(
      service,
      role: LteAuditRole.general,
      signal: _registeredSignal(),
    );

    expect(
        transport.requestedPaths, isNot(contains('/interface/lte/settings')));
    expect(_finding(findings, 'RouterOS 6 LTE compatibility mode').sev,
        AuditSeverity.info);
    expect(_finding(findings, 'APN is explicit on RouterOS 6').sev,
        AuditSeverity.ok);
  });

  test('audit never requests LTE secrets or arbitrary modem commands',
      () async {
    final transport = _AuditTransport(_healthyMenus());
    final service = await _connectedService(transport);
    await LteAuditEngine().run(
      service,
      role: LteAuditRole.general,
      signal: _registeredSignal(),
    );

    final requestedFields =
        transport.requestedFields.expand((fields) => fields);
    for (final secret in const [
      'pin',
      'password',
      'user',
      'modem-init',
      'imei',
      'imsi',
      'iccid',
    ]) {
      expect(requestedFields, isNot(contains(secret)));
    }
    for (final activeCommand in const [
      '/interface/lte/at-chat',
      '/interface/lte/scan',
      '/interface/lte/cell-monitor',
    ]) {
      expect(transport.requestedPaths, isNot(contains(activeCommand)));
    }
    await expectLater(
      service.readMenu('/interface/lte/at-chat', fields: const ['output']),
      throwsA(isA<RouterOsException>()),
    );
    await expectLater(
      service.readMenu('/interface/lte', fields: const []),
      throwsA(isA<RouterOsException>()),
    );
    expect(transport.commandCount, 0);
  });

  test('optional SSH properties cannot hide an already selected interface',
      () async {
    final transport = _ProjectionSensitiveSshTransport();
    final service = await _connectedService(transport);

    final findings = await LteAuditEngine().run(
      service,
      role: LteAuditRole.primary,
      signal: _registeredSignal(),
    );

    expect(
      findings.any((finding) =>
          finding.titleEn == 'Selected LTE interface is unavailable'),
      isFalse,
    );
    expect(
        _finding(findings, 'LTE interface is enabled').sev, AuditSeverity.ok);
    expect(
      findings.any((finding) =>
          finding.titleEn == 'LTE audit is incomplete' &&
          finding.detailEn.contains('/interface/lte (optional properties)')),
      isTrue,
    );
  });

  testWidgets('LTE audit stays readable on a narrow phone screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = await _connectedService(_AuditTransport(_healthyMenus()));
    final controller = LteController(service: service);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsController(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: LteAuditScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How is this LTE link used?'), findsOneWidget);
    final apnFinding = find.text('APN profile resolved: uplink');
    await tester.scrollUntilVisible(
      apnFinding,
      180,
      scrollable: find.byType(Scrollable),
    );
    expect(apnFinding, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Map<String, List<Map<String, String>>> _healthyMenus() => {
      '/system/resource': [
        {
          'board-name': 'SXT LTE',
          'version': '7.21.1 (stable)',
          'uptime': '1d2h',
        },
      ],
      '/interface/lte': [
        {
          'name': 'lte1',
          'disabled': 'false',
          'running': 'true',
          'apn-profiles': 'uplink',
          'allow-roaming': 'false',
          'mtu': 'auto',
        },
      ],
      '/interface/lte/apn': [
        {
          'name': 'uplink',
          'apn': 'internet',
          'use-network-apn': 'false',
          'authentication': 'none',
          'add-default-route': 'true',
          'default-route-distance': '2',
          'ip-type': 'ipv4',
          'use-peer-dns': 'true',
        },
      ],
      '/interface/lte/settings': [
        {'mode': 'auto', 'sim-slot': 'a'},
      ],
    };

Future<LteService> _connectedService(RouterOsTransport transport) async {
  final service = LteService(transportCandidates: (_) => [transport]);
  await service.connect(const LteConnection(
    host: '192.0.2.1',
    username: 'monitor',
    password: 'secret',
    transport: TransportPreference.ssh,
  ));
  return service;
}

LteSignal _registeredSignal() => LteSignal(
      sampledAt: DateTime(2026, 8, 14),
      interfaceName: 'lte1',
      registered: true,
      status: 'registered',
      operatorName: 'Example Mobile',
      technology: 'LTE',
      modemModel: 'FG621-EA',
      revision: '01.001',
      rsrp: -96,
      rsrq: -10,
      sinr: 12,
    );

Finding _finding(List<Finding> findings, String title) =>
    findings.singleWhere((finding) => finding.titleEn == title);

class _AuditTransport implements RouterOsTransport {
  final Map<String, List<Map<String, String>>> menus;
  final Set<String> failPaths;
  final List<String> requestedPaths = [];
  final List<List<String>> requestedFields = [];
  int commandCount = 0;

  _AuditTransport(this.menus, {this.failPaths = const {}});

  @override
  String get kind => 'SSH';

  @override
  Future<void> connect() async {}

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  }) async {
    requestedPaths.add(menuPath);
    requestedFields.add(List.of(fields ?? const []));
    if (failPaths.contains(menuPath)) {
      throw RouterOsException('unreadable: $menuPath');
    }
    return (menus[menuPath] ?? const [])
        .map((row) => projectReadFields(row, fields))
        .toList();
  }

  @override
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  ) async {
    commandCount++;
    return const [];
  }

  @override
  Future<void> close() async {}
}

class _ProjectionSensitiveSshTransport implements RouterOsTransport {
  @override
  String get kind => 'SSH';

  @override
  Future<void> connect() async {}

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  }) async {
    if (menuPath == '/interface/lte') {
      const identity = {'name', 'default-name', 'disabled', 'running'};
      if ((fields ?? const []).any((field) => !identity.contains(field))) {
        return const [];
      }
      return [
        projectReadFields({
          'name': 'lte1',
          'disabled': 'false',
          'running': 'true',
        }, fields),
      ];
    }
    final rows = _healthyMenus()[menuPath] ?? const [];
    return rows.map((row) => projectReadFields(row, fields)).toList();
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
