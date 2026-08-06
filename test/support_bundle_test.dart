import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/diagnostics/diagnostic_log.dart';
import 'package:wifi_apk/diagnostics/support_bundle.dart';

void main() {
  SupportSnapshot snapshot() => SupportSnapshot(
        createdAt: DateTime.utc(2026, 8, 6, 12, 34, 56),
        report: {
          'network': {
            'ssid': 'HomeWiFi',
            'router_host': '192.168.175.1',
            'backup_router_host': 'router.home',
            'client_mac': 'AA:BB:CC:DD:EE:FF',
          },
          'accidental': {
            'password': 'do-not-export',
            'message': 'Authorization: Bearer-secret token=also-secret',
          },
        },
        events: [
          DiagnosticEvent(
            timestamp: DateTime.utc(2026, 8, 6, 12, 34, 50),
            code: 'NET-03',
            message: 'Read timed out from router.home at 192.168.175.1',
            details: const {'bssid': 'AA:BB:CC:DD:EE:FF'},
          ),
        ],
      );

  test('default report masks network identifiers and always removes secrets',
      () {
    final builder = SupportBundleBuilder(
      snapshot: snapshot(),
      includeNetworkIdentifiers: false,
    );
    final text = builder.renderText();

    expect(text, isNot(contains('HomeWiFi')));
    expect(text, contains('Hom***'));
    expect(text, isNot(contains('192.168.175.1')));
    expect(text, isNot(contains('router.home')));
    expect(text, contains('192.168.x.x'));
    expect(text, isNot(contains('AA:BB:CC:DD:EE:FF')));
    expect(text, contains('AA:BB:CC:XX:XX:XX'));
    expect(text, isNot(contains('do-not-export')));
    expect(text, isNot(contains('Bearer-secret')));
    expect(text, isNot(contains('also-secret')));
  });

  test('identifiers may be included, credentials never are', () {
    final text = SupportBundleBuilder(
      snapshot: snapshot(),
      includeNetworkIdentifiers: true,
    ).renderText();

    expect(text, contains('HomeWiFi'));
    expect(text, contains('192.168.175.1'));
    expect(text, contains('router.home'));
    expect(text, contains('AA:BB:CC:DD:EE:FF'));
    expect(text, isNot(contains('do-not-export')));
    expect(text, isNot(contains('Bearer-secret')));
    expect(text, isNot(contains('also-secret')));
  });

  test('ZIP contains the documented support files', () {
    final bytes = SupportBundleBuilder(
      snapshot: snapshot(),
      includeNetworkIdentifiers: false,
    ).archiveBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((file) => file.name).toSet();

    expect(names, {'report.txt', 'report.json', 'events.log', 'README.txt'});
    final jsonFile = archive.files.singleWhere((f) => f.name == 'report.json');
    final decoded = jsonDecode(utf8.decode(jsonFile.content));
    expect(decoded['privacy']['credentials_included'], isFalse);
    expect(decoded['privacy']['automatic_upload'], isFalse);
  });
}
