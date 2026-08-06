import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/audit/audit.dart';
import 'package:wifi_apk/mikrotik/mikrotik_service.dart';

class _FakeMikrotikService extends MikrotikService {
  final Map<String, List<Map<String, String>>> menus;
  final List<String> reads = [];

  _FakeMikrotikService(this.menus) {
    host = 'router.test';
  }

  @override
  Future<List<Map<String, String>>> readMenu(String path) async {
    reads.add(path);
    return menus[path] ?? const [];
  }
}

Map<String, List<Map<String, String>>> _menus({
  required List<Map<String, String>> services,
  List<Map<String, String>> ipv4Firewall = const [],
  List<Map<String, String>> ipv6Firewall = const [],
  Map<String, List<Map<String, String>>> extra = const {},
}) =>
    {
      '/system/resource': [
        {'board-name': 'test', 'version': '7.20', 'cpu-load': '1'}
      ],
      '/ip/service': services,
      '/ip/firewall/filter': ipv4Firewall,
      '/ipv6/firewall/filter': ipv6Firewall,
      ...extra,
    };

void main() {
  group('system audit management services', () {
    test('system audit does not query wireless configuration menus', () async {
      final svc = _FakeMikrotikService(_menus(services: const []));

      await AuditEngine().run([svc], scope: AuditScope.system);

      expect(svc.reads, isNot(contains('/caps-man/configuration')));
      expect(svc.reads, isNot(contains('/interface/wireless')));
      expect(svc.reads, contains('/tool/mac-server'));
    });

    test('Wi-Fi audit does not query hardening menus', () async {
      final svc = _FakeMikrotikService(_menus(services: const []));

      await AuditEngine().run([svc], scope: AuditScope.wifi);

      expect(svc.reads, contains('/interface/wireless'));
      expect(svc.reads, isNot(contains('/tool/mac-server')));
      expect(svc.reads, isNot(contains('/ipv6/firewall/filter')));
    });

    test('detects plaintext services on non-standard ports', () async {
      final svc = _FakeMikrotikService(_menus(services: const [
        {'name': 'telnet', 'port': '2323', 'disabled': 'false'},
        {'name': 'www', 'port': '8080', 'disabled': 'false'},
        {'name': 'api', 'port': '18728', 'disabled': 'false'},
        {'name': 'ftp', 'port': '2121', 'disabled': 'false'},
      ]));

      final findings = await AuditEngine().run([svc], scope: AuditScope.system);
      final titles = findings.map((f) => f.titleEn).toList();

      expect(titles, contains('telnet:2323 is enabled'));
      expect(titles, contains('www:8080 is enabled'));
      expect(titles, contains('api:18728 is enabled'));
      expect(titles, contains('ftp:2121 is enabled'));
      expect(
        findings
            .singleWhere((f) => f.titleEn == 'Active management services')
            .detailEn,
        contains('telnet:2323 (custom)'),
      );
    });

    test('reports service ACL facts without claiming internet exposure',
        () async {
      final svc = _FakeMikrotikService(_menus(services: const [
        {'name': 'ssh', 'port': '2222', 'disabled': 'false', 'address': ''},
        {
          'name': 'winbox',
          'port': '18291',
          'disabled': 'false',
          'address': '0.0.0.0/0'
        },
      ]));

      final findings = await AuditEngine().run([svc], scope: AuditScope.system);
      final acl = findings.singleWhere(
          (f) => f.titleEn == 'No own IP restriction on management services');

      expect(acl.detailEn, contains('ssh:2222'));
      expect(acl.detailEn, contains('winbox:18291'));
      expect(acl.detailEn, contains('not a claim'));
      expect(acl.detailEn, contains('firewall rules are not analysed'));
      expect(acl.sourceUrl, contains('services'));
      expect(
        findings.where((f) => f.titleEn.contains('exposed')),
        isEmpty,
      );
    });

    test('firewall audit checks presence only for IPv4 and IPv6', () async {
      final svc = _FakeMikrotikService(_menus(
        services: const [
          {'name': 'ssh', 'port': '2222', 'disabled': 'false', 'address': ''},
        ],
        ipv4Firewall: const [
          {'chain': 'input', 'action': 'drop', 'disabled': 'false'},
        ],
        ipv6Firewall: const [
          {
            'chain': 'forward',
            'action': 'accept',
            'disabled': 'false',
          },
        ],
      ));

      final findings = await AuditEngine().run([svc], scope: AuditScope.system);

      expect(
        findings.where((f) => f.titleEn.contains('default-deny')),
        isEmpty,
      );
      expect(
        findings.map((f) => f.titleEn),
        containsAll(
            ['IPv4 firewall rules present', 'IPv6 firewall rules present']),
      );
      expect(
        findings
            .singleWhere((f) => f.titleEn == 'IPv4 firewall rules present')
            .detailEn,
        contains('does not analyse'),
      );
    });

    test('warns when a protocol family has no firewall rules', () async {
      final svc = _FakeMikrotikService(_menus(services: const []));

      final findings = await AuditEngine().run([svc], scope: AuditScope.system);

      expect(
        findings.map((f) => f.titleEn),
        containsAll([
          'No IPv4 firewall filter rules',
          'No IPv6 firewall filter rules',
        ]),
      );
    });

    test('disabled custom-port service is ignored', () async {
      final svc = _FakeMikrotikService(_menus(services: const [
        {'name': 'telnet', 'port': '2323', 'disabled': 'true'},
      ]));

      final findings = await AuditEngine().run([svc], scope: AuditScope.system);

      expect(findings.where((f) => f.titleEn.contains('telnet')), isEmpty);
    });

    test('checks MikroTik hardening recommendations and adds sources',
        () async {
      final svc = _FakeMikrotikService(_menus(
        services: const [
          {'name': 'ssh', 'port': '22', 'disabled': 'false', 'address': ''},
        ],
        extra: const {
          '/tool/mac-server': [
            {'allowed-interface-list': 'all'},
          ],
          '/tool/mac-server/mac-winbox': [
            {'allowed-interface-list': 'none'},
          ],
          '/tool/mac-server/ping': [
            {'enabled': 'true'},
          ],
          '/ip/neighbor/discovery-settings': [
            {'discover-interface-list': 'all'},
          ],
          '/tool/bandwidth-server': [
            {'enabled': 'true', 'authenticate': 'false'},
          ],
          '/ip/dns': [
            {'allow-remote-requests': 'true'},
          ],
          '/ip/proxy': [
            {'enabled': 'true'},
          ],
          '/ip/socks': [
            {'enabled': 'false'},
          ],
          '/ip/upnp': [
            {'enabled': 'true'},
          ],
          '/ip/cloud': [
            {'ddns-enabled': 'true', 'update-time': 'false'},
          ],
          '/ip/ssh': [
            {'strong-crypto': 'false'},
          ],
        },
      ));

      final findings = await AuditEngine().run([svc], scope: AuditScope.system);
      final titles = findings.map((f) => f.titleEn);

      expect(
        titles,
        containsAll([
          'MAC Telnet enabled',
          'MAC WinBox disabled',
          'MAC Ping enabled',
          'Neighbor Discovery enabled',
          'Bandwidth Test Server has no authentication',
          'Router accepts client DNS requests',
          'Web proxy enabled',
          'SOCKS proxy disabled',
          'UPnP enabled',
          'MikroTik Cloud feature enabled',
          'SSH strong crypto off',
        ]),
      );
      for (final finding in findings.where((f) => titles.contains(f.titleEn))) {
        if (const {
          'MAC Telnet enabled',
          'MAC WinBox disabled',
          'MAC Ping enabled',
          'Neighbor Discovery enabled',
          'Bandwidth Test Server has no authentication',
          'Router accepts client DNS requests',
          'Web proxy enabled',
          'SOCKS proxy disabled',
          'UPnP enabled',
          'MikroTik Cloud feature enabled',
          'SSH strong crypto off',
        }.contains(finding.titleEn)) {
          expect(finding.sourceUrl, startsWith('https://manual.mikrotik.com/'));
        }
      }
    });
  });
}
