import 'lte_quality_score.dart';
import 'lte_signal.dart';

enum LteAlignmentDirection { left, right, up, down }

enum LteAlignmentOutcome { first, better, similar, worse, radioChanged }

class LteAlignmentTarget {
  final int round;
  final int x;
  final int y;
  final LteAlignmentDirection? probeDirection;

  const LteAlignmentTarget({
    required this.round,
    required this.x,
    required this.y,
    this.probeDirection,
  });
}

class LteAlignmentPoint {
  final int id;
  final int round;
  final int x;
  final int y;
  final DateTime capturedAt;
  final int sampleCount;
  final bool registered;
  final double? rsrp;
  final double? rsrq;
  final double? sinr;
  final double? rssi;
  final int? cqi;
  final double rsrpSpread;
  final double rsrqSpread;
  final double sinrSpread;
  final String? band;
  final String? cellKey;
  final double score;
  final double confidence;
  final double? deltaFromPreviousBest;
  final LteAlignmentOutcome outcome;
  final LteAlignmentDirection? probeDirection;

  const LteAlignmentPoint({
    required this.id,
    required this.round,
    required this.x,
    required this.y,
    required this.capturedAt,
    required this.sampleCount,
    required this.registered,
    required this.rsrp,
    required this.rsrq,
    required this.sinr,
    required this.rssi,
    required this.cqi,
    required this.rsrpSpread,
    required this.rsrqSpread,
    required this.sinrSpread,
    required this.band,
    required this.cellKey,
    required this.score,
    required this.confidence,
    required this.deltaFromPreviousBest,
    required this.outcome,
    required this.probeDirection,
  });

  bool sameRadioAs(LteAlignmentPoint other) {
    if (band != null && other.band != null && band != other.band) return false;
    if (cellKey != null && other.cellKey != null && cellKey != other.cellKey) {
      return false;
    }
    return true;
  }
}

/// Turns a stable window of raw modem samples into one comparable checkpoint.
class LteAlignmentAnalyzer {
  static const double meaningfulScoreDelta = 3;

  static LteAlignmentPoint capture({
    required int id,
    required LteAlignmentTarget target,
    required List<LteSignal> samples,
    required LteAlignmentPoint? previousBest,
  }) {
    final quality = LteQualityScorer.evaluateSignals(samples);
    final registered = quality.registered;
    final rsrp = quality.rsrp;
    final rsrq = quality.rsrq;
    final sinr = quality.sinr;
    final rssi = quality.rssi;
    final cqiValue = quality.cqi;
    final rsrpSpread = quality.rsrpSpread;
    final rsrqSpread = quality.rsrqSpread;
    final sinrSpread = quality.sinrSpread;
    final band = _dominant(samples.map((sample) => sample.band));
    final cellKey = _dominant(samples.map(_cellKey));
    final score = quality.score ?? 0;
    final confidence = quality.confidence;

    double? delta;
    var outcome = LteAlignmentOutcome.first;
    if (previousBest != null) {
      delta = score - previousBest.score;
      final sameRadio = (band == null ||
              previousBest.band == null ||
              band == previousBest.band) &&
          (cellKey == null ||
              previousBest.cellKey == null ||
              cellKey == previousBest.cellKey);
      if (!sameRadio) {
        outcome = LteAlignmentOutcome.radioChanged;
      } else if (delta >= meaningfulScoreDelta) {
        outcome = LteAlignmentOutcome.better;
      } else if (delta <= -meaningfulScoreDelta) {
        outcome = LteAlignmentOutcome.worse;
      } else {
        outcome = LteAlignmentOutcome.similar;
      }
    }

    return LteAlignmentPoint(
      id: id,
      round: target.round,
      x: target.x,
      y: target.y,
      capturedAt: samples.isEmpty ? DateTime.now() : samples.last.sampledAt,
      sampleCount: samples.length,
      registered: registered,
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
      rssi: rssi,
      cqi: cqiValue,
      rsrpSpread: rsrpSpread,
      rsrqSpread: rsrqSpread,
      sinrSpread: sinrSpread,
      band: band,
      cellKey: cellKey,
      score: score,
      confidence: confidence,
      deltaFromPreviousBest: delta,
      outcome: outcome,
      probeDirection: target.probeDirection,
    );
  }

  static String? _dominant(Iterable<String?> source) {
    final counts = <String, int>{};
    for (final value in source.whereType<String>()) {
      if (value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static String? _cellKey(LteSignal sample) {
    final parts = <String>[
      if (sample.cellId != null) 'cell:${sample.cellId}',
      if (sample.enbId != null) 'enb:${sample.enbId}',
      if (sample.sectorId != null) 'sector:${sample.sectorId}',
      if (sample.physicalCellId != null) 'pci:${sample.physicalCellId}',
    ];
    return parts.isEmpty ? null : parts.join('/');
  }
}

/// Pure grid-search state. Coordinates are operator-defined physical steps,
/// not degrees: the app cannot know the dish orientation unless a sensor is
/// physically attached to it.
class LteAlignmentSession {
  final List<LteAlignmentPoint> _points = [];
  int _round = 0;
  int _nextId = 1;

  List<LteAlignmentPoint> get points => List.unmodifiable(_points);
  int get round => _round;
  List<LteAlignmentPoint> get roundPoints =>
      _points.where((point) => point.round == _round).toList(growable: false);
  LteAlignmentPoint? get latest =>
      roundPoints.isEmpty ? null : roundPoints.last;
  int get currentX => latest?.x ?? 0;
  int get currentY => latest?.y ?? 0;

  LteAlignmentPoint? get best => _confirmedBest(roundPoints);
  LteAlignmentPoint? get bestOverall => _confirmedBest(_points);

  void reset() {
    _points.clear();
    _round = 0;
    _nextId = 1;
  }

  void startFineRound() {
    _round++;
  }

  LteAlignmentTarget get baselineTarget =>
      LteAlignmentTarget(round: _round, x: 0, y: 0);

  LteAlignmentPoint add(
    LteAlignmentTarget target,
    List<LteSignal> samples,
  ) {
    final previousBest = best;
    final point = LteAlignmentAnalyzer.capture(
      id: _nextId++,
      target: target,
      samples: samples,
      previousBest: previousBest,
    );
    _points.add(point);
    return point;
  }

  LteAlignmentTarget targetFromCurrent(LteAlignmentDirection direction) {
    final delta = _delta(direction);
    return LteAlignmentTarget(
      round: _round,
      x: currentX + delta.$1,
      y: currentY + delta.$2,
      probeDirection: direction,
    );
  }

  LteAlignmentTarget? nextTarget() {
    final currentBest = best;
    if (currentBest == null) return baselineTarget;
    final visited = {
      for (final point in roundPoints) '${point.x}:${point.y}',
    };
    final last = latest;
    final directions = <LteAlignmentDirection>[];
    if (identical(last, currentBest) && last?.probeDirection != null) {
      directions.add(last!.probeDirection!);
    }
    for (final direction in const [
      LteAlignmentDirection.right,
      LteAlignmentDirection.left,
      LteAlignmentDirection.up,
      LteAlignmentDirection.down,
    ]) {
      if (!directions.contains(direction)) directions.add(direction);
    }
    for (final direction in directions) {
      final delta = _delta(direction);
      final x = currentBest.x + delta.$1;
      final y = currentBest.y + delta.$2;
      if (visited.contains('$x:$y')) continue;
      return LteAlignmentTarget(
        round: _round,
        x: x,
        y: y,
        probeDirection: direction,
      );
    }
    return null;
  }

  ({int dx, int dy}) movementTo(LteAlignmentTarget target) => (
        dx: target.x - currentX,
        dy: target.y - currentY,
      );

  ({int dx, int dy}) get movementToBest {
    final target = best;
    return (
      dx: (target?.x ?? currentX) - currentX,
      dy: (target?.y ?? currentY) - currentY,
    );
  }

  LteAlignmentPoint? _confirmedBest(List<LteAlignmentPoint> candidates) {
    LteAlignmentPoint? result;
    for (final candidate in candidates) {
      if (result == null ||
          candidate.score >=
              result.score + LteAlignmentAnalyzer.meaningfulScoreDelta) {
        result = candidate;
      }
    }
    return result;
  }

  static (int, int) _delta(LteAlignmentDirection direction) =>
      switch (direction) {
        LteAlignmentDirection.left => (-1, 0),
        LteAlignmentDirection.right => (1, 0),
        LteAlignmentDirection.up => (0, 1),
        LteAlignmentDirection.down => (0, -1),
      };
}
