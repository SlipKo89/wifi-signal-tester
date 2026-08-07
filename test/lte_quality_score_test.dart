import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_quality_score.dart';

void main() {
  test('clean usable radio scores above stronger but noisy radio', () {
    final clean = LteQualityScorer.evaluate(
      _window(rsrp: -99, rsrq: -9, sinr: 18, cqi: 11),
    );
    final noisy = LteQualityScorer.evaluate(
      _window(rsrp: -85, rsrq: -18, sinr: 1, cqi: 4),
    );

    expect(clean.score, greaterThan(noisy.score!));
    expect(clean.grade, isNot(LteScoreGrade.poor));
  });

  test('unstable radio is penalised', () {
    final stable = LteQualityScorer.evaluate(
      _window(rsrp: -96, rsrq: -10, sinr: 15),
    );
    final unstable = LteQualityScorer.evaluate([
      _sample(0, rsrp: -108, rsrq: -15, sinr: 4),
      _sample(1, rsrp: -84, rsrq: -6, sinr: 27),
      ..._window(rsrp: -96, rsrq: -10, sinr: 15).take(4),
    ]);

    expect(stable.score, greaterThan(unstable.score!));
    expect(stable.confidence, greaterThan(unstable.confidence));
  });

  test('timeline resets smoothing after a band or cell handoff', () {
    final samples = [
      for (var index = 0; index < 5; index++)
        _sample(index,
            rsrp: -112, rsrq: -15, sinr: 2, band: 'B7', radioKey: 'B7/cell-a'),
      _sample(6,
          rsrp: -88, rsrq: -9, sinr: 21, band: 'B3', radioKey: 'B3/cell-b'),
    ];

    final timeline = LteQualityScorer.timeline(samples);
    final newRadioOnly = LteQualityScorer.evaluate([samples.last]);

    expect(timeline.last.radioChanged, isTrue);
    expect(timeline.last.score, closeTo(newRadioOnly.score!, 0.001));
  });

  test('temporarily missing cell identity is not treated as a handoff', () {
    final samples = [
      _sample(0,
          rsrp: -96, rsrq: -10, sinr: 15, band: 'B7', radioKey: 'cell:a'),
      _sample(1,
          rsrp: -96, rsrq: -10, sinr: 15, band: 'B7', radioKey: 'pci:353'),
    ];

    final timeline = LteQualityScorer.timeline(samples);

    expect(timeline.last.radioChanged, isFalse);
    expect(timeline.last.confidence, greaterThan(timeline.first.confidence));
  });

  test('summary includes a conservative P10 value', () {
    final timeline = LteQualityScorer.timeline([
      for (var index = 0; index < 10; index++)
        _sample(index,
            rsrp: -110 + index * 2, rsrq: -14 + index / 2, sinr: 2 + index * 2),
    ]);
    final summary = LteQualityScorer.summarise(timeline)!;

    expect(summary.min, lessThanOrEqualTo(summary.p10));
    expect(summary.p10, lessThan(summary.average));
    expect(summary.average, lessThan(summary.max));
  });

  test('score grade boundaries are stable', () {
    expect(LteQualityScorer.grade(null), LteScoreGrade.unavailable);
    expect(LteQualityScorer.grade(39.9), LteScoreGrade.poor);
    expect(LteQualityScorer.grade(40), LteScoreGrade.fair);
    expect(LteQualityScorer.grade(60), LteScoreGrade.good);
    expect(LteQualityScorer.grade(80), LteScoreGrade.excellent);
  });
}

List<LteQualitySample> _window({
  required double rsrp,
  required double rsrq,
  required double sinr,
  int? cqi,
}) =>
    [
      for (var index = 0; index < 6; index++)
        _sample(index, rsrp: rsrp, rsrq: rsrq, sinr: sinr, cqi: cqi),
    ];

LteQualitySample _sample(
  int second, {
  required double rsrp,
  required double rsrq,
  required double sinr,
  int? cqi,
  String band = 'B7',
  String radioKey = 'B7/cell-a',
}) =>
    LteQualitySample(
      sampledAt: DateTime(2026).add(Duration(seconds: second)),
      registered: true,
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
      cqi: cqi,
      band: band,
      radioKey: radioKey,
    );
