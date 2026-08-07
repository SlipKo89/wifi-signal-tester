import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/wifi_logs/wifi_log_analysis.dart';

void main() {
  const target = 'AA:BB:CC:DD:EE:FF';

  WifiLogSourceSnapshot source(List<Map<String, String>> rows) =>
      WifiLogSourceSnapshot(
        host: '192.0.2.1',
        transport: 'API',
        rows: rows,
        totalRows: rows.length,
        truncated: false,
        infoLogging: true,
        debugLogging: false,
      );

  test('selected MAC is analyzed and other client events are ignored', () {
    final report = WifiLogAnalyzer.analyze(
      targetMac: target,
      sources: [
        source(const [
          {
            'time': '2026-08-08 12:00:00',
            'topics': 'wireless,info',
            'message': '11:22:33:44:55:66@wifi1 connected, signal strength -50',
          },
          {
            'time': '2026-08-08 12:00:01',
            'topics': 'wireless,info',
            'message':
                'AA:BB:CC:DD:EE:FF@wifi2: connected, signal strength -61',
          },
        ]),
      ],
    );

    expect(report.events, hasLength(1));
    expect(report.events.single.kind, WifiLogKind.connected);
    expect(report.events.single.interfaceName, 'wifi2');
    expect(report.events.single.signalDbm, -61);
  });

  test('disconnect and next AP connect become a measured roam', () {
    final report = WifiLogAnalyzer.analyze(
      targetMac: target,
      sources: [
        source(const [
          {
            'time': '2026-08-08 12:41:08.125',
            'topics': 'caps,info',
            'message':
                'AA:BB:CC:DD:EE:FF@hAP ac3 5GHz disconnected, received disassoc: sending station leaving (8), signal strength -68',
          },
          {
            'time': '2026-08-08 12:41:08.417',
            'topics': 'caps,info',
            'message':
                'AA:BB:CC:DD:EE:FF@cAP ax 5GHz connected, signal strength -61',
          },
        ]),
      ],
    );

    expect(report.handoffs, hasLength(1));
    expect(report.handoffs.single.roam, isTrue);
    expect(report.handoffs.single.fromInterface, 'hAP ac3 5GHz');
    expect(report.handoffs.single.toInterface, 'cAP ax 5GHz');
    expect(report.handoffs.single.gap, const Duration(milliseconds: 292));
    expect(report.handoffs.single.severity, WifiLogSeverity.ok);
  });

  test('explicit radio and access-list failures get distinct diagnoses', () {
    final report = WifiLogAnalyzer.analyze(
      targetMac: target,
      sources: [
        source(const [
          {
            'time': '12:00:00',
            'topics': 'wireless,info',
            'message':
                'AA:BB:CC:DD:EE:FF@wlan1 disconnected, extensive data loss',
          },
          {
            'time': '12:01:00',
            'topics': 'caps,info',
            'message':
                'AA:BB:CC:DD:EE:FF@guest rejected, forbidden by access-list',
          },
        ]),
      ],
      now: DateTime(2026, 8, 8, 12, 2),
    );

    expect(
      report.events.map((event) => event.kind),
      containsAll([WifiLogKind.radioLoss, WifiLogKind.accessDenied]),
    );
    expect(report.severity, WifiLogSeverity.warning);
    expect(report.verdictEn, 'Repeated Wi-Fi failures found');
  });

  test('CAP control events are kept without accepting unrelated clients', () {
    final report = WifiLogAnalyzer.analyze(
      targetMac: target,
      sources: [
        source(const [
          {
            'time': '2026-08-08 12:05:00',
            'topics': 'caps,info',
            'message':
                'disconnected from capsman@00:11:22:33:44:55, failed to connect',
          },
          {
            'time': '2026-08-08 12:05:03',
            'topics': 'wireless,info',
            'message': '11:22:33:44:55:66@wifi1 connected',
          },
        ]),
      ],
    );

    expect(report.events, hasLength(1));
    expect(report.events.single.kind, WifiLogKind.capDisconnected);
    expect(report.events.single.targetSpecific, isFalse);
    expect(report.severity, WifiLogSeverity.critical);
  });

  test('RouterOS month and time-only timestamps remain comparable', () {
    final report = WifiLogAnalyzer.analyze(
      targetMac: target,
      sources: [
        source(const [
          {
            'time': 'aug/08/2026 12:41:08.125',
            'topics': 'wireless,info',
            'message': 'AA:BB:CC:DD:EE:FF@wifi1 disconnected',
          },
          {
            'time': 'aug/08/2026 12:41:09.125',
            'topics': 'wireless,info',
            'message': 'AA:BB:CC:DD:EE:FF@wifi2 connected',
          },
        ]),
      ],
      now: DateTime(2026, 8, 8, 13),
    );

    expect(report.handoffs.single.gap, const Duration(seconds: 1));
  });
}
