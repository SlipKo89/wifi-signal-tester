import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/wifi_map/floor_measurement_capture.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan.dart';

void main() {
  FloorSignalSnapshot sample(
    int second, {
    String link = 'aa:bb',
    int phoneRssi = -60,
    int apRssi = -65,
    int phoneSnr = 35,
    int apSnr = 30,
  }) =>
      FloorSignalSnapshot(
        capturedAt: DateTime.fromMillisecondsSinceEpoch(second * 1000),
        linkKey: link,
        apName: 'hall-ap',
        phoneRssi: phoneRssi,
        apRssi: apRssi,
        phoneSnr: phoneSnr,
        apSnr: apSnr,
      );

  test('averages a stable two-sided window and keeps ranges', () {
    final capture = FloorMeasurementAccumulator(sample(1, phoneRssi: -60));
    capture.add(sample(3, phoneRssi: -64, apRssi: -67, phoneSnr: 31));
    capture.add(sample(5, phoneRssi: -62, apRssi: -64, apSnr: 32));

    final point = capture.build(
      id: 'p1',
      surveyId: 's1',
      position: const FloorPoint(2, 4),
    );

    expect(point.phoneRssi, -62);
    expect(point.phoneRssiMin, -64);
    expect(point.phoneRssiMax, -60);
    expect(point.apRssi, -65);
    expect(point.sampleCount, 3);
    expect(point.durationMs, 4000);
    expect(point.surveyId, 's1');
  });

  test('refuses a reading after roaming to another AP', () {
    final capture = FloorMeasurementAccumulator(sample(1));

    expect(capture.add(sample(2, link: 'cc:dd')), isFalse);
    expect(capture.length, 1);
  });
}
