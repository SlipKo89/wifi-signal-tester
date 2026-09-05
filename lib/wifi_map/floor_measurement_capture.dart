import 'wifi_floor_plan.dart';

class FloorSignalSnapshot {
  final DateTime capturedAt;
  final String linkKey;
  final String? apName;
  final int phoneRssi;
  final int apRssi;
  final int phoneSnr;
  final int apSnr;
  final bool phoneSnrEstimated;
  final bool apSnrEstimated;

  const FloorSignalSnapshot({
    required this.capturedAt,
    required this.linkKey,
    required this.phoneRssi,
    required this.apRssi,
    required this.phoneSnr,
    required this.apSnr,
    this.phoneSnrEstimated = false,
    this.apSnrEstimated = false,
    this.apName,
  });
}

/// Accumulates only readings from one physical link, so a roam cannot silently
/// blend two access points into one pin.
class FloorMeasurementAccumulator {
  final String linkKey;
  final List<FloorSignalSnapshot> _samples = [];

  FloorMeasurementAccumulator(FloorSignalSnapshot first)
      : linkKey = first.linkKey {
    _samples.add(first);
  }

  int get length => _samples.length;
  bool accepts(FloorSignalSnapshot sample) => sample.linkKey == linkKey;

  bool add(FloorSignalSnapshot sample) {
    if (!accepts(sample)) return false;
    _samples.add(sample);
    return true;
  }

  FloorMeasurement build({
    required String id,
    required String surveyId,
    required FloorPoint position,
    FloorGeoFix? geo,
  }) {
    if (_samples.isEmpty) throw StateError('No floor-map signal samples');
    final first = _samples.first;
    final last = _samples.last;
    return FloorMeasurement(
      id: id,
      surveyId: surveyId,
      position: position,
      timestampMs: last.capturedAt.millisecondsSinceEpoch,
      phoneRssi: _average(_samples.map((sample) => sample.phoneRssi)),
      apRssi: _average(_samples.map((sample) => sample.apRssi)),
      phoneSnr: _average(_samples.map((sample) => sample.phoneSnr)),
      apSnr: _average(_samples.map((sample) => sample.apSnr)),
      phoneRssiMin: _min(_samples.map((sample) => sample.phoneRssi)),
      phoneRssiMax: _max(_samples.map((sample) => sample.phoneRssi)),
      apRssiMin: _min(_samples.map((sample) => sample.apRssi)),
      apRssiMax: _max(_samples.map((sample) => sample.apRssi)),
      phoneSnrMin: _min(_samples.map((sample) => sample.phoneSnr)),
      phoneSnrMax: _max(_samples.map((sample) => sample.phoneSnr)),
      apSnrMin: _min(_samples.map((sample) => sample.apSnr)),
      apSnrMax: _max(_samples.map((sample) => sample.apSnr)),
      phoneSnrEstimated: _samples.any((sample) => sample.phoneSnrEstimated),
      apSnrEstimated: _samples.any((sample) => sample.apSnrEstimated),
      sampleCount: _samples.length,
      durationMs: last.capturedAt.difference(first.capturedAt).inMilliseconds,
      apName: last.apName ?? first.apName,
      geo: geo,
    );
  }
}

int _average(Iterable<int> values) {
  final list = values.toList(growable: false);
  return (list.reduce((a, b) => a + b) / list.length).round();
}

int _min(Iterable<int> values) => values.reduce((a, b) => a < b ? a : b);
int _max(Iterable<int> values) => values.reduce((a, b) => a > b ? a : b);
