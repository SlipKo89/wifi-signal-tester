import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_diagnostics.dart';
import 'package:wifi_apk/lte/lte_signal.dart';

LteSignal sample({
  double? rsrp,
  double? rsrq,
  double? sinr,
  int? cqi,
  bool registered = true,
}) =>
    LteSignal(
      sampledAt: DateTime(2026),
      interfaceName: 'lte1',
      registered: registered,
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
      cqi: cqi,
    );

void main() {
  group('LteDiagnostics', () {
    test('distinguishes weak but clean coverage', () {
      final report = LteDiagnostics.evaluate(
        sample(rsrp: -104, rsrq: -9, sinr: 15, cqi: 12),
      );
      expect(report.quality, LteQuality.fair);
      expect(report.titleEn, contains('Weak but fairly clean'));
    });

    test('distinguishes sufficient power with interference', () {
      final report = LteDiagnostics.evaluate(
        sample(rsrp: -88, rsrq: -17, sinr: 2, cqi: 5),
      );
      expect(report.quality, LteQuality.fair);
      expect(report.titleEn, contains('needs attention'));
      expect(report.factsEn, isNotEmpty);
    });

    test('grades the S24 screenshot values as usable but weak', () {
      final report = LteDiagnostics.evaluate(
        sample(rsrp: -108, rsrq: -10.5, sinr: 7),
      );
      expect(report.quality, LteQuality.fair);
      expect(report.titleEn, 'LTE works, but the signal is weak');
      expect(report.titleRu, 'LTE работает, но сигнал слабый');
      expect(report.summaryRu, contains('RSRP -108 dBm'));
    });

    test('reports weak and noisy link', () {
      final report = LteDiagnostics.evaluate(
        sample(rsrp: -108, rsrq: -12.5, sinr: -1),
      );
      expect(report.quality, LteQuality.poor);
      expect(report.titleEn, contains('weak and noisy'));
    });

    test('detects instability after enough samples', () {
      final history = [
        sample(rsrp: -88, rsrq: -9, sinr: 22),
        sample(rsrp: -90, rsrq: -9, sinr: 20),
        sample(rsrp: -97, rsrq: -10, sinr: 10),
        sample(rsrp: -89, rsrq: -9, sinr: 21),
      ];
      final report = LteDiagnostics.evaluate(history.last, history: history);
      expect(report.quality, LteQuality.fair);
      expect(report.titleEn, contains('unstable'));
    });

    test('never calls a poor stable result healthy', () {
      final report = LteDiagnostics.evaluate(
        sample(rsrp: -95, rsrq: -12, sinr: 7, cqi: 3),
      );
      expect(report.quality, LteQuality.poor);
      expect(report.titleEn, 'LTE radio link is poor');
      expect(report.titleRu, 'Радиоканал LTE плохой');
    });

    test('uses the healthy title only for a genuinely good link', () {
      final report = LteDiagnostics.evaluate(
        sample(rsrp: -85, rsrq: -9, sinr: 18, cqi: 11),
      );
      expect(report.quality, LteQuality.good);
      expect(report.titleEn, 'LTE radio link looks healthy');
    });

    test('explains a modem without registration', () {
      final report = LteDiagnostics.evaluate(sample(registered: false));
      expect(report.quality, LteQuality.poor);
      expect(report.titleEn, contains('not registered'));
    });
  });
}
