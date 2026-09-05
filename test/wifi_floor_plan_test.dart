import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan_store.dart';

void main() {
  late Directory temporary;
  late WifiFloorPlanStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wifi-floor-map-test-');
    store = WifiFloorPlanStore(directoryProvider: () async => temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('floor-plan JSON preserves metric geometry and future signal pins', () {
    const plan = WifiFloorPlan(
      id: 'office',
      name: 'Office',
      widthMeters: 12.5,
      heightMeters: 8,
      cellSizeMeters: 0.5,
      createdAtMs: 10,
      updatedAtMs: 20,
      captureGps: true,
      surveys: [
        FloorSurveySession(
          id: 'survey-1',
          name: 'Before tuning',
          startedAtMs: 25,
          updatedAtMs: 30,
        ),
      ],
      walls: [
        FloorWall(
          start: FloorPoint(0, 0),
          end: FloorPoint(4.5, 0),
          kind: FloorBarrierKind.window,
          material: FloorMaterial.glass,
        ),
      ],
      measurements: [
        FloorMeasurement(
          id: 'sample-1',
          surveyId: 'survey-1',
          position: FloorPoint(2.5, 3),
          timestampMs: 30,
          phoneRssi: -61,
          apRssi: -65,
          phoneSnr: 34,
          apSnr: 30,
          phoneRssiMin: -64,
          phoneRssiMax: -59,
          sampleCount: 5,
          durationMs: 8000,
          apName: 'hall-ap',
          geo: FloorGeoFix(
            latitude: 55.75,
            longitude: 37.62,
            accuracyMeters: 12,
          ),
        ),
      ],
      calibration: FloorPlanCalibration(
        start: FloorPoint(1, 1),
        end: FloorPoint(5, 1),
        referenceDistanceMeters: 4,
        source: FloorCalibrationSource.manual,
        timestampMs: 21,
      ),
    );

    final restored = WifiFloorPlan.fromJson(plan.toJson());

    expect(restored.widthMeters, 12.5);
    expect(restored.cellSizeMeters, 0.5);
    expect(restored.walls.single.end.xMeters, 4.5);
    expect(restored.walls.single.kind, FloorBarrierKind.window);
    expect(restored.walls.single.material, FloorMaterial.glass);
    expect(restored.measurements.single.phoneRssi, -61);
    expect(restored.measurements.single.sampleCount, 5);
    expect(restored.measurements.single.phoneRssiMin, -64);
    expect(restored.measurements.single.surveyId, 'survey-1');
    expect(restored.surveys.single.name, 'Before tuning');
    expect(restored.captureGps, isTrue);
    expect(restored.measurements.single.position.yMeters, 3);
    expect(restored.measurements.single.geo?.accuracyMeters, 12);
    expect(restored.calibration?.referenceDistanceMeters, 4);
    expect(restored.calibration?.source, FloorCalibrationSource.manual);
  });

  test('two-point calibration rescales all geometry but not the grid', () {
    const plan = WifiFloorPlan(
      id: 'calibration',
      name: 'Calibration',
      widthMeters: 10,
      heightMeters: 5,
      cellSizeMeters: 0.5,
      createdAtMs: 1,
      updatedAtMs: 1,
      walls: [
        FloorWall(start: FloorPoint(1, 1), end: FloorPoint(4, 1)),
      ],
      measurements: [
        FloorMeasurement(
          id: 'point-1',
          position: FloorPoint(2, 3),
          timestampMs: 2,
        ),
      ],
    );

    final calibrated = plan.recalibrated(
      start: const FloorPoint(1, 1),
      end: const FloorPoint(3, 1),
      referenceDistanceMeters: 4,
      timestampMs: 50,
    );

    expect(calibrated.widthMeters, 20);
    expect(calibrated.heightMeters, 10);
    expect(calibrated.cellSizeMeters, 0.5);
    expect(calibrated.walls.single.start.xMeters, 2);
    expect(calibrated.walls.single.end.xMeters, 8);
    expect(calibrated.measurements.single.position.xMeters, 4);
    expect(calibrated.measurements.single.position.yMeters, 6);
    expect(calibrated.measurements.single.timestampMs, 2);
    expect(calibrated.calibration?.start.xMeters, 2);
    expect(calibrated.calibration?.end.xMeters, 6);
    expect(calibrated.calibration?.referenceDistanceMeters, 4);
    expect(calibrated.updatedAtMs, 50);
  });

  test('two-point calibration rejects unusable scales', () {
    const plan = WifiFloorPlan(
      id: 'calibration',
      name: 'Calibration',
      widthMeters: 100,
      heightMeters: 20,
      cellSizeMeters: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    expect(
      () => plan.recalibrated(
        start: const FloorPoint(1, 1),
        end: const FloorPoint(1, 1),
        referenceDistanceMeters: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => plan.recalibrated(
        start: const FloorPoint(0, 0),
        end: const FloorPoint(1, 0),
        referenceDistanceMeters: 10,
      ),
      throwsArgumentError,
    );
  });

  test('legacy measurement JSON gains a survey session', () {
    final restored = WifiFloorPlan.fromJson({
      'id': 'legacy-map',
      'name': 'Legacy',
      'widthMeters': 10,
      'heightMeters': 10,
      'cellSizeMeters': 1,
      'measurements': [
        {
          'id': 'old-point',
          'position': {'x': 1, 'y': 2},
          'timestamp': 42,
          'phoneRssi': -55,
        },
      ],
    });

    expect(restored.surveys.single.id, 'legacy');
    expect(restored.measurements.single.surveyId, 'legacy');
  });

  test('older wall records migrate to a safe unknown-material wall', () {
    final wall = FloorWall.fromJson({
      'start': {'x': 1, 'y': 2},
      'end': {'x': 3, 'y': 4},
    });

    expect(wall.kind, FloorBarrierKind.wall);
    expect(wall.material, FloorMaterial.unknown);
  });

  test('stores maps and imported images only below app-owned directory',
      () async {
    final imagePath = await store.saveBackground(
      planId: 'warehouse',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      extension: '.png',
    );
    final plan = WifiFloorPlan(
      id: 'warehouse',
      name: 'Warehouse',
      widthMeters: 40,
      heightMeters: 20,
      cellSizeMeters: 1,
      backgroundImagePath: imagePath,
      createdAtMs: 1,
      updatedAtMs: 2,
    );

    await store.save(plan);
    final restored = await store.loadAll();

    expect(restored.single.name, 'Warehouse');
    expect(File(imagePath).existsSync(), isTrue);

    await store.delete('warehouse');
    expect(await store.loadAll(), isEmpty);
    expect(File(imagePath).existsSync(), isFalse);
  });

  test('never deletes a background path outside its own map directory',
      () async {
    final external = File('${temporary.path}/user-original.png');
    await external.writeAsBytes([7, 8, 9]);
    await store.save(WifiFloorPlan(
      id: 'external',
      name: 'External',
      widthMeters: 10,
      heightMeters: 10,
      cellSizeMeters: 1,
      backgroundImagePath: external.path,
      createdAtMs: 1,
      updatedAtMs: 1,
    ));

    await store.delete('external');

    expect(external.existsSync(), isTrue);
  });

  test('rejects an oversized imported image before writing it', () async {
    final bytes = Uint8List(WifiFloorPlanStore.maxImageBytes + 1);

    await expectLater(
      store.saveBackground(
        planId: 'huge',
        bytes: bytes,
        extension: 'png',
      ),
      throwsFormatException,
    );
  });
}
