import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/diagnostics/link_diagnostics.dart';

void main() {
  group('LinkDiagnosticsEngine', () {
    test('waits for a stable six-sample window', () {
      final engine = LinkDiagnosticsEngine();
      for (var i = 0; i < 5; i++) {
        engine.add(_sample(i));
      }

      expect(engine.report.ready, isFalse);
      expect(engine.report.sampleCount, 5);

      engine.add(_sample(5));
      expect(engine.report.ready, isTrue);
      expect(engine.report.healthy, isTrue);
    });

    test('finds low CCQ despite strong signal', () {
      final engine = LinkDiagnosticsEngine();
      for (var i = 0; i < 6; i++) {
        engine.add(_sample(i, txCcq: 44, rxCcq: 48));
      }

      final report = engine.report;
      expect(report.primary?.kind, LinkIssueKind.lowCcq);
      expect(report.primary?.severity, LinkIssueSeverity.critical);
      expect(report.summary.lowestCcq, 44);
    });

    test('correlates high router CPU with poor local latency', () {
      final engine = LinkDiagnosticsEngine();
      for (var i = 0; i < 6; i++) {
        engine.add(_sample(i, pingMs: 170, cpuLoad: 92));
      }

      final report = engine.report;
      expect(report.primary?.kind, LinkIssueKind.routerLoad);
      expect(report.primary?.severity, LinkIssueSeverity.critical);
      expect(
        report.findings.map((f) => f.kind),
        contains(LinkIssueKind.highLatency),
      );
    });

    test('does not diagnose a single latency spike', () {
      final engine = LinkDiagnosticsEngine();
      const ping = [10, 11, 210, 12, 9, 10];
      for (var i = 0; i < ping.length; i++) {
        engine.add(_sample(i, pingMs: ping[i]));
      }

      expect(engine.report.healthy, isTrue);
    });

    test('requires at least two lost pings before reporting packet loss', () {
      final oneLost = LinkDiagnosticsEngine();
      final twoLost = LinkDiagnosticsEngine();
      for (var i = 0; i < 6; i++) {
        oneLost.add(_sample(i, pingLossPct: 5, pingSamples: 20));
        twoLost.add(_sample(i, pingLossPct: 10, pingSamples: 20));
      }

      expect(oneLost.report.healthy, isTrue);
      expect(twoLost.report.primary?.kind, LinkIssueKind.packetLoss);
    });

    test('ignores a metric seen in only one sample', () {
      final engine = LinkDiagnosticsEngine();
      engine.add(_sample(0, txCcq: 20));
      for (var i = 1; i < 6; i++) {
        engine.add(_sample(i));
      }

      expect(engine.report.healthy, isTrue);
    });

    test('detects sustained uplink asymmetry', () {
      final engine = LinkDiagnosticsEngine();
      for (var i = 0; i < 6; i++) {
        engine.add(_sample(i, delta: -16));
      }

      expect(engine.report.primary?.kind, LinkIssueKind.uplinkAsymmetry);
    });

    test('parses RouterOS rates without guessing unknown values', () {
      expect(
          LinkDiagnosticsEngine.parseRateMbps('866.6Mbps-80MHz/2S/SGI'), 866.6);
      expect(LinkDiagnosticsEngine.parseRateMbps('1Gbps'), 1000);
      expect(LinkDiagnosticsEngine.parseRateMbps('54000Kbps'), 54);
      expect(LinkDiagnosticsEngine.parseRateMbps('unknown'), isNull);
    });
  });

  group('LinkDiagnosticSession', () {
    test('waits, runs once and freezes the completed report', () {
      final session = LinkDiagnosticSession();

      session.waitForStableLink();
      expect(session.phase, LinkDiagnosticPhase.waiting);
      expect(session.add(_sample(0)), isFalse);
      expect(session.report.sampleCount, 0);

      session.start();
      for (var i = 0; i < 5; i++) {
        expect(session.add(_sample(i)), isFalse);
      }
      expect(session.phase, LinkDiagnosticPhase.collecting);
      expect(session.add(_sample(5)), isTrue);
      expect(session.phase, LinkDiagnosticPhase.complete);
      expect(session.report.sampleCount, 6);

      expect(session.add(_sample(6, txCcq: 20)), isFalse);
      expect(session.report.sampleCount, 6);
      expect(session.report.healthy, isTrue);
    });

    test('reset discards an unfinished run', () {
      final session = LinkDiagnosticSession()..start();
      session.add(_sample(0));

      session.reset();

      expect(session.phase, LinkDiagnosticPhase.idle);
      expect(session.report.sampleCount, 0);
    });
  });
}

LinkDiagnosticSample _sample(
  int index, {
  int? txCcq,
  int? rxCcq,
  int pingMs = 12,
  int pingLossPct = 0,
  int pingSamples = 6,
  int cpuLoad = 20,
  int delta = 2,
}) =>
    LinkDiagnosticSample(
      timestamp: DateTime(2026, 8, 6).add(Duration(seconds: index * 2)),
      phoneRssi: -50,
      apSignal: -52,
      phoneSnr: 40,
      apSnr: 38,
      delta: delta,
      txCcq: txCcq,
      rxCcq: rxCcq,
      phoneRateMbps: 300,
      apTxRateMbps: 288,
      apRxRateMbps: 240,
      pThroughputKbps: 180000,
      pingAvgMs: pingMs,
      pingLossPct: pingLossPct,
      pingSamples: pingSamples,
      cpuLoad: cpuLoad,
    );
