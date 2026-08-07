import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_signal.dart';

void main() {
  group('LteSignal', () {
    test('parses R11e-LTE monitor fields', () {
      final signal = LteSignal.fromMonitor({
        'status': 'registered',
        'registration-status': 'registered',
        'manufacturer': 'MikroTik',
        'model': 'R11e-LTE',
        'current-operator': 'Example Mobile',
        'access-technology': 'LTE',
        'earfcn': '2850 (band 7, bandwidth 20Mhz)',
        'cqi': '12',
        'rsrp': '-102dBm',
        'rsrq': '-8dB',
        'sinr': '13dB',
        'imei': 'must-not-have-a-field-in-the-model',
        'imsi': 'must-not-have-a-field-in-the-model',
        'iccid': 'must-not-have-a-field-in-the-model',
      }, interfaceName: 'lte1');

      expect(signal.registered, isTrue);
      expect(signal.modemModel, 'R11e-LTE');
      expect(signal.band, 'B7');
      expect(signal.bandwidthMhz, 20);
      expect(signal.earfcn, 2850);
      expect(signal.cqi, 12);
      expect(signal.rsrp, -102);
      expect(signal.rsrq, -8);
      expect(signal.sinr, 13);
      expect(signal.rssi, isNull);
    });

    test('parses MBIM primary-band and decimal RSRQ', () {
      final signal = LteSignal.fromMonitor({
        'status': 'running',
        'model': 'FG621-EA',
        'current-operator': 'Example LTE',
        'data-class': 'LTE',
        // Some RouterOS console versions put the following labels on one line;
        // the generic SSH parser keeps that tail in primary-band.
        'primary-band': 'B7@20Mhz earfcn: 3250 phy-cellid: 353',
        'phy-cellid': '353',
        'rssi': '-80dBm',
        'rsrp': '-108dBm',
        'rsrq': '-12.5dB',
        'sinr': '-1dB',
      }, interfaceName: 'lte1');

      expect(signal.registered, isTrue);
      expect(signal.technology, 'LTE');
      expect(signal.band, 'B7');
      expect(signal.bandwidthMhz, 20);
      expect(signal.earfcn, 3250);
      expect(signal.physicalCellId, 353);
      expect(signal.rssi, -80);
      expect(signal.rsrq, -12.5);
      expect(signal.sinr, -1);
    });

    test('does not treat an idle empty modem as registered', () {
      final signal = LteSignal.fromMonitor(
        {'status': 'not-registered'},
        interfaceName: 'lte1',
      );
      expect(signal.registered, isFalse);
      expect(signal.hasRadioMetrics, isFalse);
    });
  });
}
