import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/ui/widgets/synchronized_timeline.dart';
import 'package:wifi_apk/ui/widgets/zabbix_session_context.dart';
import 'package:wifi_apk/zabbix/zabbix_binding.dart';
import 'package:wifi_apk/zabbix/zabbix_binding_store.dart';
import 'package:wifi_apk/zabbix/zabbix_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('binding persistence contains mapping metadata but no API token',
      () async {
    const binding = ZabbixBinding(
      scope: ZabbixBindingScope.lte,
      subjectKey: 'router:192.0.2.10',
      profileUrl: 'http://zabbix.local:8080/zabbix',
      hostId: '42',
      hostName: 'LTE uplink',
      metrics: [
        ZabbixBoundMetric(
          kind: ZabbixMetricKind.lteRsrp,
          itemId: '1001',
          name: 'LTE RSRP',
          key: 'mikrotik.lte.rsrp',
          valueType: 0,
          units: 'dBm',
        ),
      ],
    );
    final store = ZabbixBindingStore();

    await store.save(binding);
    final restored = await store.load(
      ZabbixBindingScope.lte,
      'router:192.0.2.10',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('zabbix_session_bindings_v1')!;

    expect(restored?.hostId, '42');
    expect(restored?.metrics.single.kind, ZabbixMetricKind.lteRsrp);
    expect(raw, isNot(contains('api_token')));
    expect(raw, isNot(contains('test-token')));
  });

  test('semantic suggestions distinguish LTE signal items', () {
    const items = [
      ZabbixItem(
        itemId: '1',
        name: 'Wi-Fi RSSI',
        key: 'mikrotik.wifi.rssi',
        valueType: 0,
        units: 'dBm',
        lastValue: null,
        lastReceivedAt: null,
      ),
      ZabbixItem(
        itemId: '2',
        name: 'LTE modem RSRP',
        key: 'mikrotik.lte.rsrp',
        valueType: 0,
        units: 'dBm',
        lastValue: null,
        lastReceivedAt: null,
      ),
    ];

    expect(suggestZabbixItem(ZabbixMetricKind.lteRsrp, items)?.itemId, '2');
    expect(suggestZabbixItem(ZabbixMetricKind.wifiSignal, items)?.itemId, '1');
  });

  test('combined CSV keeps local and Zabbix points in long format', () {
    final csv = buildCombinedTimelineCsv([
      const SessionTimelineTrack(
        key: 'lte_rsrp',
        title: 'LTE RSRP',
        unit: 'dBm',
        series: [
          SessionTimelineSeries(
            label: 'Local',
            source: 'local',
            color: Colors.green,
            points: [SessionTimelinePoint(1000, -101)],
          ),
          SessionTimelineSeries(
            label: 'Zabbix, RSRP',
            source: 'zabbix',
            color: Colors.blue,
            points: [SessionTimelinePoint(2000, -99)],
          ),
        ],
      ),
    ]);

    expect(csv, contains('local,LTE RSRP,Local,1000,-101.0,dBm'));
    expect(csv, contains('zabbix,LTE RSRP,"Zabbix, RSRP",2000,-99.0,dBm'));
  });

  testWidgets('synchronized timeline fits a narrow phone width',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SynchronizedTimeline(
              startedMs: 1000,
              endedMs: 3000,
              ru: true,
              tracks: [
                SessionTimelineTrack(
                  key: 'signal',
                  title: 'Очень длинное название радиосигнала',
                  unit: 'dBm',
                  series: [
                    SessionTimelineSeries(
                      label: 'Очень длинный источник',
                      source: 'local',
                      color: Colors.green,
                      points: [
                        SessionTimelinePoint(1000, -100),
                        SessionTimelinePoint(3000, -90),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
