import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_alignment.dart';
import 'package:wifi_apk/lte/lte_quality_score.dart';
import 'package:wifi_apk/lte/lte_signal.dart';

void main() {
  test('alignment and general LTE quality use the same score', () {
    final samples = _window(rsrp: -97, rsrq: -10, sinr: 16, cqi: 10);
    final point = LteAlignmentAnalyzer.capture(
      id: 1,
      target: const LteAlignmentTarget(round: 0, x: 0, y: 0),
      samples: samples,
      previousBest: null,
    );
    final quality = LteQualityScorer.evaluateSignals(samples);

    expect(point.score, quality.score);
    expect(point.confidence, quality.confidence);
  });

  test('clean usable signal beats stronger but noisy signal', () {
    final clean = LteAlignmentAnalyzer.capture(
      id: 1,
      target: const LteAlignmentTarget(round: 0, x: 0, y: 0),
      samples: _window(rsrp: -99, rsrq: -9, sinr: 18, cqi: 11),
      previousBest: null,
    );
    final noisy = LteAlignmentAnalyzer.capture(
      id: 2,
      target: const LteAlignmentTarget(round: 0, x: 1, y: 0),
      samples: _window(rsrp: -85, rsrq: -18, sinr: 1, cqi: 4),
      previousBest: clean,
    );

    expect(clean.score, greaterThan(noisy.score));
    expect(noisy.outcome, LteAlignmentOutcome.worse);
  });

  test('unstable peak is penalised against a repeatable checkpoint', () {
    final stable = LteAlignmentAnalyzer.capture(
      id: 1,
      target: const LteAlignmentTarget(round: 0, x: 0, y: 0),
      samples: _window(rsrp: -96, rsrq: -10, sinr: 15),
      previousBest: null,
    );
    final unstableSamples = <LteSignal>[
      _sample(0, rsrp: -108, rsrq: -15, sinr: 4),
      _sample(1, rsrp: -84, rsrq: -6, sinr: 27),
      _sample(2, rsrp: -96, rsrq: -10, sinr: 15),
      _sample(3, rsrp: -96, rsrq: -10, sinr: 15),
      _sample(4, rsrp: -96, rsrq: -10, sinr: 15),
      _sample(5, rsrp: -96, rsrq: -10, sinr: 15),
    ];
    final unstable = LteAlignmentAnalyzer.capture(
      id: 2,
      target: const LteAlignmentTarget(round: 0, x: 1, y: 0),
      samples: unstableSamples,
      previousBest: stable,
    );

    expect(stable.score, greaterThan(unstable.score));
    expect(stable.confidence, greaterThan(unstable.confidence));
  });

  test('checkpoint confidence reflects missing core radio metrics', () {
    final complete = LteAlignmentAnalyzer.capture(
      id: 1,
      target: const LteAlignmentTarget(round: 0, x: 0, y: 0),
      samples: _window(rsrp: -96, rsrq: -10, sinr: 15),
      previousBest: null,
    );
    final rsrpOnly = LteAlignmentAnalyzer.capture(
      id: 2,
      target: const LteAlignmentTarget(round: 0, x: 1, y: 0),
      samples: [
        for (var index = 0; index < 6; index++)
          LteSignal(
            sampledAt: DateTime(2026, 8, 7).add(Duration(seconds: index * 2)),
            interfaceName: 'lte1',
            registered: true,
            rsrp: -96,
          ),
      ],
      previousBest: complete,
    );

    expect(complete.confidence, 1);
    expect(rsrpOnly.confidence, closeTo(1 / 3, 0.01));
  });

  test('grid search continues an improvement then probes around the best', () {
    final session = LteAlignmentSession();
    session.add(
      session.baselineTarget,
      _window(rsrp: -104, rsrq: -13, sinr: 8),
    );

    final right = session.nextTarget()!;
    expect((right.x, right.y), (1, 0));
    session.add(right, _window(rsrp: -96, rsrq: -10, sinr: 17));

    final furtherRight = session.nextTarget()!;
    expect((furtherRight.x, furtherRight.y), (2, 0));
    session.add(furtherRight, _window(rsrp: -101, rsrq: -14, sinr: 7));

    expect((session.best!.x, session.best!.y), (1, 0));
    final up = session.nextTarget()!;
    expect((up.x, up.y), (1, 1));
    expect(session.movementTo(up), (dx: -1, dy: 1));
    session.add(up, _window(rsrp: -100, rsrq: -13, sinr: 9));

    final down = session.nextTarget()!;
    expect((down.x, down.y), (1, -1));
    session.add(down, _window(rsrp: -102, rsrq: -14, sinr: 6));

    expect(session.nextTarget(), isNull);
    expect(session.movementToBest, (dx: 0, dy: 1));
  });

  test('band or cell handoff is marked as a separate candidate', () {
    final baseline = LteAlignmentAnalyzer.capture(
      id: 1,
      target: const LteAlignmentTarget(round: 0, x: 0, y: 0),
      samples: _window(
        rsrp: -100,
        rsrq: -11,
        sinr: 14,
        band: 'B7',
        cell: 'cell-a',
      ),
      previousBest: null,
    );
    final changed = LteAlignmentAnalyzer.capture(
      id: 2,
      target: const LteAlignmentTarget(round: 0, x: 1, y: 0),
      samples: _window(
        rsrp: -92,
        rsrq: -9,
        sinr: 20,
        band: 'B3',
        cell: 'cell-b',
      ),
      previousBest: baseline,
    );

    expect(changed.outcome, LteAlignmentOutcome.radioChanged);
  });

  test('fine pass keeps history and starts a new local coordinate grid', () {
    final session = LteAlignmentSession();
    session.add(
        session.baselineTarget, _window(rsrp: -98, rsrq: -10, sinr: 15));

    session.startFineRound();

    expect(session.round, 1);
    expect(session.points, hasLength(1));
    expect(session.roundPoints, isEmpty);
    expect((session.baselineTarget.x, session.baselineTarget.y), (0, 0));
  });
}

List<LteSignal> _window({
  required double rsrp,
  required double rsrq,
  required double sinr,
  int cqi = 10,
  String band = 'B7',
  String cell = 'cell-a',
}) =>
    [
      for (var index = 0; index < 6; index++)
        _sample(
          index,
          rsrp: rsrp,
          rsrq: rsrq,
          sinr: sinr,
          cqi: cqi,
          band: band,
          cell: cell,
        ),
    ];

LteSignal _sample(
  int index, {
  required double rsrp,
  required double rsrq,
  required double sinr,
  int cqi = 10,
  String band = 'B7',
  String cell = 'cell-a',
}) =>
    LteSignal(
      sampledAt: DateTime(2026, 8, 7).add(Duration(seconds: index * 2)),
      interfaceName: 'lte1',
      registered: true,
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
      cqi: cqi,
      band: band,
      cellId: cell,
    );
