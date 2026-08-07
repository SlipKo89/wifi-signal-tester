import 'lte_signal.dart';

enum LteScoreGrade { poor, fair, good, excellent, unavailable }

class LteQualitySample {
  final DateTime sampledAt;
  final bool registered;
  final double? rsrp;
  final double? rsrq;
  final double? sinr;
  final double? rssi;
  final int? cqi;
  final String? band;
  final String? radioKey;

  const LteQualitySample({
    required this.sampledAt,
    required this.registered,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
    this.cqi,
    this.band,
    this.radioKey,
  });

  factory LteQualitySample.fromSignal(LteSignal signal) => LteQualitySample(
        sampledAt: signal.sampledAt,
        registered: signal.registered,
        rsrp: signal.rsrp,
        rsrq: signal.rsrq,
        sinr: signal.sinr,
        rssi: signal.rssi,
        cqi: signal.cqi,
        band: signal.band,
        radioKey: radioKeyForSignal(signal),
      );

  static String? radioKeyForSignal(LteSignal signal) {
    if (signal.cellId != null) return 'cell:${signal.cellId}';
    if (signal.enbId != null || signal.sectorId != null) {
      return 'sector:${signal.enbId ?? '?'}:${signal.sectorId ?? '?'}';
    }
    if (signal.physicalCellId != null) return 'pci:${signal.physicalCellId}';
    return null;
  }
}

class LteQualityValue {
  final DateTime sampledAt;
  final bool registered;
  final double? score;
  final double confidence;
  final double? rsrp;
  final double? rsrq;
  final double? sinr;
  final double? rssi;
  final int? cqi;
  final double rsrpSpread;
  final double rsrqSpread;
  final double sinrSpread;
  final String? band;
  final String? radioKey;
  final bool radioChanged;

  const LteQualityValue({
    required this.sampledAt,
    required this.registered,
    required this.score,
    required this.confidence,
    required this.rsrp,
    required this.rsrq,
    required this.sinr,
    required this.rssi,
    required this.cqi,
    required this.rsrpSpread,
    required this.rsrqSpread,
    required this.sinrSpread,
    required this.band,
    required this.radioKey,
    this.radioChanged = false,
  });

  LteScoreGrade get grade => LteQualityScorer.grade(score);

  LteQualityValue copyWith({bool? radioChanged}) => LteQualityValue(
        sampledAt: sampledAt,
        registered: registered,
        score: score,
        confidence: confidence,
        rsrp: rsrp,
        rsrq: rsrq,
        sinr: sinr,
        rssi: rssi,
        cqi: cqi,
        rsrpSpread: rsrpSpread,
        rsrqSpread: rsrqSpread,
        sinrSpread: sinrSpread,
        band: band,
        radioKey: radioKey,
        radioChanged: radioChanged ?? this.radioChanged,
      );
}

class LteQualitySeriesStats {
  final double min;
  final double average;
  final double max;
  final double p10;

  const LteQualitySeriesStats({
    required this.min,
    required this.average,
    required this.max,
    required this.p10,
  });

  double get spread => max - min;
}

/// One shared radio-quality formula for the live dashboard, saved history and
/// the antenna-alignment assistant. A higher score is always better.
///
/// This deliberately estimates radio quality, not Internet speed: sector load,
/// traffic shaping and upstream congestion are outside the available metrics.
class LteQualityScorer {
  static const timelineWindow = 5;

  static LteScoreGrade grade(double? score) {
    if (score == null) return LteScoreGrade.unavailable;
    if (score >= 80) return LteScoreGrade.excellent;
    if (score >= 60) return LteScoreGrade.good;
    if (score >= 40) return LteScoreGrade.fair;
    return LteScoreGrade.poor;
  }

  static LteQualityValue evaluateSignals(List<LteSignal> signals) => evaluate(
      signals.map(LteQualitySample.fromSignal).toList(growable: false));

  static LteQualityValue evaluate(List<LteQualitySample> samples) {
    if (samples.isEmpty) {
      return LteQualityValue(
        sampledAt: DateTime.now(),
        registered: false,
        score: null,
        confidence: 0,
        rsrp: null,
        rsrq: null,
        sinr: null,
        rssi: null,
        cqi: null,
        rsrpSpread: 0,
        rsrqSpread: 0,
        sinrSpread: 0,
        band: null,
        radioKey: null,
      );
    }

    final registered =
        samples.where((sample) => sample.registered).length * 2 >=
            samples.length;
    final rsrp = _median(samples.map((sample) => sample.rsrp));
    final rsrq = _median(samples.map((sample) => sample.rsrq));
    final sinr = _median(samples.map((sample) => sample.sinr));
    final rssi = _median(samples.map((sample) => sample.rssi));
    final cqiValue = _median(samples.map((sample) => sample.cqi?.toDouble()));
    final rsrpSpread = _spread(samples.map((sample) => sample.rsrp));
    final rsrqSpread = _spread(samples.map((sample) => sample.rsrq));
    final sinrSpread = _spread(samples.map((sample) => sample.sinr));
    final availableCoreMetrics = [rsrp, rsrq, sinr].whereType<double>().length;
    final score = registered && availableCoreMetrics >= 2
        ? _score(
            rsrp: rsrp,
            rsrq: rsrq,
            sinr: sinr,
            cqi: cqiValue,
            rsrpSpread: rsrpSpread,
            rsrqSpread: rsrqSpread,
            sinrSpread: sinrSpread,
          )
        : registered
            ? null
            : 0.0;

    return LteQualityValue(
      sampledAt: samples.last.sampledAt,
      registered: registered,
      score: score,
      confidence: _confidence(
        sampleCount: samples.length,
        registered: registered,
        availableCoreMetrics: availableCoreMetrics,
        rsrpSpread: rsrpSpread,
        rsrqSpread: rsrqSpread,
        sinrSpread: sinrSpread,
      ),
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
      rssi: rssi,
      cqi: cqiValue?.round(),
      rsrpSpread: rsrpSpread,
      rsrqSpread: rsrqSpread,
      sinrSpread: sinrSpread,
      band: samples.last.band,
      radioKey: samples.last.radioKey,
    );
  }

  static List<LteQualityValue> timeline(
    List<LteQualitySample> samples, {
    int windowSize = timelineWindow,
  }) {
    if (samples.isEmpty) return const [];
    final safeWindow = windowSize.clamp(1, 30);
    final values = <LteQualityValue>[];
    var segmentStart = 0;
    for (var index = 0; index < samples.length; index++) {
      final previousKey = index == 0 ? null : samples[index - 1].radioKey;
      final currentKey = samples[index].radioKey;
      final previousBand = index == 0 ? null : samples[index - 1].band;
      final currentBand = samples[index].band;
      final bandChanged = index > 0 &&
          previousBand != null &&
          currentBand != null &&
          previousBand != currentBand;
      final comparableCellKeys = previousKey != null &&
          currentKey != null &&
          previousKey.split(':').first == currentKey.split(':').first;
      final cellChanged =
          index > 0 && comparableCellKeys && previousKey != currentKey;
      final radioChanged = bandChanged || cellChanged;
      if (radioChanged) segmentStart = index;
      final start = (index - safeWindow + 1).clamp(segmentStart, index);
      values.add(evaluate(samples.sublist(start, index + 1))
          .copyWith(radioChanged: radioChanged));
    }
    return values;
  }

  static List<LteQualityValue> signalTimeline(
    List<LteSignal> signals, {
    int windowSize = timelineWindow,
  }) =>
      timeline(
        signals.map(LteQualitySample.fromSignal).toList(growable: false),
        windowSize: windowSize,
      );

  static LteQualitySeriesStats? summarise(Iterable<LteQualityValue> timeline) {
    final values = timeline.toList(growable: false);
    final stableValues = values
        .where((value) => value.score != null && value.confidence >= 0.5)
        .toList(growable: false);
    final source = stableValues.isEmpty ? values : stableValues;
    final scores = source
        .map((value) => value.score)
        .whereType<double>()
        .toList(growable: false)
      ..sort();
    if (scores.isEmpty) return null;
    final p10Index = ((scores.length - 1) * 0.10).floor();
    return LteQualitySeriesStats(
      min: scores.first,
      average: scores.reduce((a, b) => a + b) / scores.length,
      max: scores.last,
      p10: scores[p10Index],
    );
  }

  static double? _score({
    required double? rsrp,
    required double? rsrq,
    required double? sinr,
    required double? cqi,
    required double rsrpSpread,
    required double rsrqSpread,
    required double sinrSpread,
  }) {
    final weakCoverage = rsrp != null && rsrp < -105;
    final metrics = <(double?, double)>[
      (_normalise(rsrp, -120, -80), weakCoverage ? 0.45 : 0.25),
      (_normalise(rsrq, -20, -8), weakCoverage ? 0.20 : 0.25),
      (_normalise(sinr, -5, 25), weakCoverage ? 0.30 : 0.45),
      (_normalise(cqi, 0, 15), 0.05),
    ];
    var weighted = 0.0;
    var weight = 0.0;
    for (final metric in metrics) {
      if (metric.$1 == null) continue;
      weighted += metric.$1! * metric.$2;
      weight += metric.$2;
    }
    if (weight == 0) return null;

    final penalty = ((rsrpSpread - 3).clamp(0, 12) * 0.8) +
        ((rsrqSpread - 2).clamp(0, 8) * 0.9) +
        ((sinrSpread - 4).clamp(0, 20) * 0.7);
    return ((weighted / weight) - penalty).clamp(0, 100).toDouble();
  }

  static double _confidence({
    required int sampleCount,
    required bool registered,
    required int availableCoreMetrics,
    required double rsrpSpread,
    required double rsrqSpread,
    required double sinrSpread,
  }) {
    if (!registered || availableCoreMetrics == 0) return 0;
    final countFactor = (sampleCount / 6).clamp(0, 1).toDouble();
    final completeness = (availableCoreMetrics / 3).clamp(0, 1).toDouble();
    final instability =
        (rsrpSpread / 12 + rsrqSpread / 8 + sinrSpread / 20) / 3;
    return (countFactor * completeness * (1 - instability.clamp(0, 0.55)))
        .clamp(0, 1)
        .toDouble();
  }

  static double? _normalise(double? value, double bad, double good) {
    if (value == null) return null;
    return ((value - bad) * 100 / (good - bad)).clamp(0, 100).toDouble();
  }

  static double? _median(Iterable<double?> source) {
    final values = source.whereType<double>().toList()..sort();
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  static double _spread(Iterable<double?> source) {
    final values = source.whereType<double>().toList()..sort();
    return values.length < 2 ? 0 : values.last - values.first;
  }
}
