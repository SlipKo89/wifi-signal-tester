import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'wifi_floor_plan.dart';

class ImportedFloorPlanBundle {
  final WifiFloorPlan plan;
  final Uint8List? backgroundBytes;
  final String? backgroundExtension;
  final bool gpsIncluded;

  const ImportedFloorPlanBundle({
    required this.plan,
    required this.backgroundBytes,
    required this.backgroundExtension,
    required this.gpsIncluded,
  });
}

/// Portable, versioned map package shared between mobile and desktop builds.
/// Credentials and connection profiles are outside the floor-plan model and
/// therefore cannot enter this archive.
class WifiFloorPlanBundle {
  static const mimeType = 'application/vnd.wifi-signal-tester.floor-map';
  static const extension = 'wifimap';
  static const _schema = 'wifi-signal-tester.floor-map';
  static const _formatVersion = 1;
  static const maxBundleBytes = 35 * 1024 * 1024;
  static const _maxManifestBytes = 2 * 1024 * 1024;
  static const _maxEntries = 3;

  static Future<Uint8List> exportBytes(
    WifiFloorPlan plan, {
    bool includeBackground = true,
    bool includeMeasurements = true,
    bool includeGps = false,
  }) async {
    final measurements = includeMeasurements
        ? plan.measurements
            .map((sample) => _copySample(sample, includeGps: includeGps))
            .toList(growable: false)
        : const <FloorMeasurement>[];
    final portablePlan = plan.copyWith(
      clearBackground: true,
      surveys: includeMeasurements ? plan.surveys : const [],
      measurements: measurements,
    );

    Uint8List? background;
    String? backgroundName;
    final sourcePath = plan.backgroundImagePath;
    if (includeBackground && sourcePath != null && sourcePath.isNotEmpty) {
      final file = File(sourcePath);
      if (await file.exists()) {
        final length = await file.length();
        if (length > maxBundleBytes) {
          throw const FormatException(
              'Floor-plan image is too large to export');
        }
        background = await file.readAsBytes();
        final imageExtension = _imageExtension(p.extension(sourcePath));
        backgroundName = 'background.$imageExtension';
      }
    }

    final manifest = const JsonEncoder.withIndent('  ').convert({
      'schema': _schema,
      'format_version': _formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'privacy': {
        'measurements_included': includeMeasurements,
        'gps_included': includeMeasurements && includeGps,
        'credentials_included': false,
        'connection_profiles_included': false,
      },
      'background_file': backgroundName,
      'plan': portablePlan.toJson(),
    });
    if (utf8.encode(manifest).length > _maxManifestBytes) {
      throw const FormatException('Floor-map project contains too much data');
    }

    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', manifest));
    if (background != null && backgroundName != null) {
      archive.addFile(ArchiveFile.bytes(backgroundName, background));
    }
    final result = ZipEncoder().encodeBytes(archive);
    if (result.length > maxBundleBytes) {
      throw const FormatException('Floor-map package exceeds 35 MB');
    }
    return result;
  }

  static ImportedFloorPlanBundle importBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBundleBytes) {
      throw const FormatException(
          'Floor-map package must be between 1 byte and 35 MB');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final files = archive.files.where((file) => file.isFile).toList();
    if (files.isEmpty || files.length > _maxEntries) {
      throw const FormatException('Unexpected floor-map package contents');
    }
    for (final file in files) {
      if (file.name.contains('/') || file.name.contains('\\')) {
        throw const FormatException(
            'Nested paths are not allowed in a floor-map package');
      }
    }
    final manifestFile =
        files.where((file) => file.name == 'manifest.json').toList();
    if (manifestFile.length != 1 ||
        manifestFile.single.size > _maxManifestBytes) {
      throw const FormatException('Missing or oversized floor-map manifest');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.single.content));
    if (manifest is! Map ||
        manifest['schema'] != _schema ||
        manifest['format_version'] != _formatVersion ||
        manifest['plan'] is! Map) {
      throw const FormatException('Unsupported floor-map package format');
    }

    final plan = WifiFloorPlan.fromJson(
      Map<String, dynamic>.from(manifest['plan'] as Map),
    );
    _validatePlan(plan);
    final privacy = manifest['privacy'];
    final gpsIncluded = privacy is Map && privacy['gps_included'] == true;

    Uint8List? background;
    String? imageExtension;
    final backgroundName = manifest['background_file'];
    if (backgroundName != null) {
      if (backgroundName is! String ||
          !RegExp(r'^background\.(png|jpe?g|webp)$')
              .hasMatch(backgroundName.toLowerCase())) {
        throw const FormatException('Invalid background image entry');
      }
      final matches =
          files.where((file) => file.name == backgroundName).toList();
      if (matches.length != 1 || matches.single.size > 25 * 1024 * 1024) {
        throw const FormatException('Missing or oversized background image');
      }
      background = Uint8List.fromList(matches.single.content);
      imageExtension = _imageExtension(p.extension(backgroundName));
    }

    final allowedNames = {
      'manifest.json',
      if (backgroundName is String) backgroundName
    };
    if (files.any((file) => !allowedNames.contains(file.name))) {
      throw const FormatException('Unexpected file in floor-map package');
    }
    return ImportedFloorPlanBundle(
      plan: plan,
      backgroundBytes: background,
      backgroundExtension: imageExtension,
      gpsIncluded: gpsIncluded,
    );
  }

  static Future<File> writeTemporary(
    WifiFloorPlan plan, {
    bool includeBackground = true,
    bool includeMeasurements = true,
    bool includeGps = false,
  }) async {
    final directory = await getTemporaryDirectory();
    final safeName = plan.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9_-]+', caseSensitive: false), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final file = File(p.join(
      directory.path,
      '${safeName.isEmpty ? 'wifi-map' : safeName}.$extension',
    ));
    return file.writeAsBytes(
      await exportBytes(
        plan,
        includeBackground: includeBackground,
        includeMeasurements: includeMeasurements,
        includeGps: includeGps,
      ),
      flush: true,
    );
  }

  static FloorMeasurement _copySample(
    FloorMeasurement sample, {
    required bool includeGps,
  }) =>
      FloorMeasurement(
        id: sample.id,
        surveyId: sample.surveyId,
        position: sample.position,
        timestampMs: sample.timestampMs,
        phoneRssi: sample.phoneRssi,
        apRssi: sample.apRssi,
        phoneSnr: sample.phoneSnr,
        apSnr: sample.apSnr,
        phoneRssiMin: sample.phoneRssiMin,
        phoneRssiMax: sample.phoneRssiMax,
        apRssiMin: sample.apRssiMin,
        apRssiMax: sample.apRssiMax,
        phoneSnrMin: sample.phoneSnrMin,
        phoneSnrMax: sample.phoneSnrMax,
        apSnrMin: sample.apSnrMin,
        apSnrMax: sample.apSnrMax,
        phoneSnrEstimated: sample.phoneSnrEstimated,
        apSnrEstimated: sample.apSnrEstimated,
        sampleCount: sample.sampleCount,
        durationMs: sample.durationMs,
        apName: sample.apName,
        geo: includeGps ? sample.geo : null,
      );

  static void _validatePlan(WifiFloorPlan plan) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(plan.id) ||
        plan.name.trim().isEmpty ||
        plan.name.length > 120 ||
        !_bounded(plan.widthMeters, 0.1, 500) ||
        !_bounded(plan.heightMeters, 0.1, 500) ||
        !_bounded(plan.cellSizeMeters, 0.1, 10) ||
        plan.walls.length > 10000 ||
        plan.surveys.length > 10000 ||
        plan.measurements.length > 100000) {
      throw const FormatException('Invalid floor-map project values');
    }
    bool pointOk(FloorPoint point) =>
        point.xMeters.isFinite &&
        point.yMeters.isFinite &&
        point.xMeters >= 0 &&
        point.yMeters >= 0 &&
        point.xMeters <= plan.widthMeters &&
        point.yMeters <= plan.heightMeters;
    if (plan.walls.any((wall) => !pointOk(wall.start) || !pointOk(wall.end)) ||
        plan.measurements.any((sample) => !pointOk(sample.position))) {
      throw const FormatException('Floor-map object lies outside the plan');
    }
    final surveyIds = <String>{};
    for (final survey in plan.surveys) {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(survey.id) ||
          survey.name.trim().isEmpty ||
          survey.name.length > 160 ||
          !surveyIds.add(survey.id)) {
        throw const FormatException('Invalid floor-map survey session');
      }
    }
    for (final sample in plan.measurements) {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(sample.id) ||
          !surveyIds.contains(sample.surveyId) ||
          sample.sampleCount < 1 ||
          sample.sampleCount > 1000 ||
          sample.durationMs < 0 ||
          sample.durationMs > const Duration(hours: 1).inMilliseconds) {
        throw const FormatException('Invalid floor-map measurement');
      }
      final geo = sample.geo;
      if (geo == null) continue;
      if (!_bounded(geo.latitude, -90, 90) ||
          !_bounded(geo.longitude, -180, 180) ||
          !geo.accuracyMeters.isFinite ||
          geo.accuracyMeters < 0 ||
          (geo.altitudeMeters != null && !geo.altitudeMeters!.isFinite)) {
        throw const FormatException('Invalid GPS context in floor-map package');
      }
    }
  }

  static bool _bounded(double value, double min, double max) =>
      value.isFinite && value >= min && value <= max;

  static String _imageExtension(String value) {
    final extension = value.toLowerCase().replaceFirst('.', '');
    if (!const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
      throw const FormatException('Unsupported floor-plan image type');
    }
    return extension;
  }
}
