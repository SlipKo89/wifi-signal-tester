import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_history_store.dart';
import 'package:wifi_apk/lte/lte_signal.dart';

void main() {
  test('recorded LTE sample contains radio facts but no modem identifiers', () {
    final signal = LteSignal(
      sampledAt: DateTime(2026, 8, 7, 12),
      interfaceName: 'lte1',
      registered: true,
      rsrp: -101,
      rsrq: -10.5,
      sinr: 12,
      rssi: -78,
      cqi: 9,
      band: 'B7',
      bandwidthMhz: 20,
      earfcn: 3250,
      physicalCellId: 353,
      cellId: 'cell-a',
      modemModel: 'FG621-EA',
    );

    final sample = LteRecordedSample.fromSignal(signal);
    final row = sample.toRow(7);

    expect(sample.rsrp, -101);
    expect(sample.band, 'B7');
    expect(row, isNot(contains('imei')));
    expect(row, isNot(contains('imsi')));
    expect(row, isNot(contains('iccid')));
    expect(row, isNot(contains('model')));
  });

  test('session analysis calculates retrospective statistics and dominant cell',
      () {
    final samples = [
      _sample(1, rsrp: -110, rsrq: -13, sinr: 4, band: 'B7', cell: 'a'),
      _sample(2, rsrp: -100, rsrq: -11, sinr: 8, band: 'B7', cell: 'a'),
      _sample(3, rsrp: -90, rsrq: -9, sinr: 12, band: 'B3', cell: 'b'),
    ];

    final analysis = LteSessionAnalysis.fromSamples(samples);

    expect(analysis.sampleCount, 3);
    expect(analysis.rsrp?.min, -110);
    expect(analysis.rsrp?.average, -100);
    expect(analysis.rsrp?.max, -90);
    expect(analysis.rsrp?.spread, 20);
    expect(analysis.quality, isNotNull);
    expect(analysis.qualityP10, isNotNull);
    expect(analysis.dominantBand, 'B7');
    expect(analysis.dominantCell, 'a');
  });
}

LteRecordedSample _sample(
  int ts, {
  required double rsrp,
  required double rsrq,
  required double sinr,
  required String band,
  required String cell,
}) =>
    LteRecordedSample(
      tsMs: ts,
      registered: true,
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
      band: band,
      cellId: cell,
    );
