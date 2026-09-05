import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan_bundle.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wifimap-bundle-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  WifiFloorPlan plan({String? background}) => WifiFloorPlan(
        id: 'map-office-1',
        name: 'Office',
        widthMeters: 12,
        heightMeters: 8,
        cellSizeMeters: 0.5,
        backgroundImagePath: background,
        createdAtMs: 1,
        updatedAtMs: 2,
        surveys: const [
          FloorSurveySession(
            id: 'survey-1',
            name: 'Before tuning',
            startedAtMs: 2,
            updatedAtMs: 3,
          ),
        ],
        walls: const [
          FloorWall(
            start: FloorPoint(0, 0),
            end: FloorPoint(5, 0),
            kind: FloorBarrierKind.door,
            material: FloorMaterial.wood,
          ),
        ],
        measurements: const [
          FloorMeasurement(
            id: 'point-1',
            surveyId: 'survey-1',
            position: FloorPoint(2, 3),
            timestampMs: 3,
            phoneRssi: -62,
            apRssi: -67,
            sampleCount: 5,
            durationMs: 8000,
            geo: FloorGeoFix(
              latitude: 55.75,
              longitude: 37.62,
              accuracyMeters: 9,
            ),
          ),
        ],
      );

  test('portable project round-trip keeps geometry, samples and image',
      () async {
    final image = File('${temporary.path}/plan.png');
    await image.writeAsBytes([1, 2, 3, 4]);

    final bytes = await WifiFloorPlanBundle.exportBytes(
      plan(background: image.path),
      includeGps: true,
    );
    final imported = WifiFloorPlanBundle.importBytes(bytes);

    expect(imported.plan.id, 'map-office-1');
    expect(imported.plan.backgroundImagePath, isNull);
    expect(imported.plan.walls.single.kind, FloorBarrierKind.door);
    expect(imported.plan.walls.single.material, FloorMaterial.wood);
    expect(imported.plan.measurements.single.phoneRssi, -62);
    expect(imported.plan.measurements.single.sampleCount, 5);
    expect(imported.plan.surveys.single.name, 'Before tuning');
    expect(imported.plan.measurements.single.geo?.accuracyMeters, 9);
    expect(imported.backgroundExtension, 'png');
    expect(imported.backgroundBytes, [1, 2, 3, 4]);
  });

  test('GPS is stripped by default and credentials cannot enter manifest',
      () async {
    final bytes = await WifiFloorPlanBundle.exportBytes(plan());
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile =
        archive.files.singleWhere((file) => file.name == 'manifest.json');
    final text = utf8.decode(manifestFile.content);
    final imported = WifiFloorPlanBundle.importBytes(bytes);

    expect(imported.plan.measurements.single.geo, isNull);
    expect(text, contains('"gps_included": false'));
    expect(text, contains('"credentials_included": false'));
    expect(text, isNot(contains('password')));
    expect(text, isNot(contains('token')));
  });

  test('excluding measurements also excludes survey names and timestamps',
      () async {
    final bytes = await WifiFloorPlanBundle.exportBytes(
      plan(),
      includeMeasurements: false,
    );
    final imported = WifiFloorPlanBundle.importBytes(bytes);

    expect(imported.plan.measurements, isEmpty);
    expect(imported.plan.surveys, isEmpty);
  });

  test('rejects archive paths and projects with out-of-bounds geometry', () {
    final invalidPlan = plan().toJson()
      ..['walls'] = [
        {
          'start': {'x': 0, 'y': 0},
          'end': {'x': 999, 'y': 0},
        }
      ];
    final archive = Archive()
      ..addFile(ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'schema': 'wifi-signal-tester.floor-map',
          'format_version': 1,
          'plan': invalidPlan,
        }),
      ));
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

    expect(
      () => WifiFloorPlanBundle.importBytes(bytes),
      throwsFormatException,
    );

    final nested = Archive()
      ..addFile(ArchiveFile.string('../manifest.json', '{}'));
    expect(
      () => WifiFloorPlanBundle.importBytes(
        Uint8List.fromList(ZipEncoder().encodeBytes(nested)),
      ),
      throwsFormatException,
    );
  });
}
