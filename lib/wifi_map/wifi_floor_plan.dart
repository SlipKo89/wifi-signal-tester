class FloorPoint {
  final double xMeters;
  final double yMeters;

  const FloorPoint(this.xMeters, this.yMeters);

  Map<String, Object> toJson() => {'x': xMeters, 'y': yMeters};

  factory FloorPoint.fromJson(Map<String, dynamic> json) => FloorPoint(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      );
}

enum FloorBarrierKind { wall, door, window }

enum FloorMaterial {
  unknown,
  drywall,
  wood,
  glass,
  brick,
  concrete,
  reinforcedConcrete,
  metal,
}

class FloorWall {
  final FloorPoint start;
  final FloorPoint end;
  final FloorBarrierKind kind;
  final FloorMaterial material;

  const FloorWall({
    required this.start,
    required this.end,
    this.kind = FloorBarrierKind.wall,
    this.material = FloorMaterial.unknown,
  });

  Map<String, Object> toJson() => {
        'start': start.toJson(),
        'end': end.toJson(),
        'kind': kind.name,
        'material': material.name,
      };

  factory FloorWall.fromJson(Map<String, dynamic> json) => FloorWall(
        start: FloorPoint.fromJson(_map(json['start'])),
        end: FloorPoint.fromJson(_map(json['end'])),
        kind: FloorBarrierKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => FloorBarrierKind.wall,
        ),
        material: FloorMaterial.values.firstWhere(
          (value) => value.name == json['material'],
          orElse: () => FloorMaterial.unknown,
        ),
      );
}

/// Optional context for one manually placed measurement. Indoor positioning
/// remains plan-relative; this fix never moves the pin and is retained only
/// when the user enables GPS capture for that map.
class FloorGeoFix {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? altitudeMeters;

  const FloorGeoFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.altitudeMeters,
  });

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'altitudeMeters': altitudeMeters,
      };

  factory FloorGeoFix.fromJson(Map<String, dynamic> json) => FloorGeoFix(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble() ?? 0,
        altitudeMeters: (json['altitudeMeters'] as num?)?.toDouble(),
      );
}

/// One named survey run. Separate sessions make a map useful for comparing
/// the same premises before/after a change or on different days.
class FloorSurveySession {
  final String id;
  final String name;
  final int startedAtMs;
  final int updatedAtMs;

  const FloorSurveySession({
    required this.id,
    required this.name,
    required this.startedAtMs,
    required this.updatedAtMs,
  });

  FloorSurveySession copyWith({String? name, int? updatedAtMs}) =>
      FloorSurveySession(
        id: id,
        name: name ?? this.name,
        startedAtMs: startedAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'startedAt': startedAtMs,
        'updatedAt': updatedAtMs,
      };

  factory FloorSurveySession.fromJson(Map<String, dynamic> json) =>
      FloorSurveySession(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        startedAtMs: (json['startedAt'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// One manually placed and short-window averaged two-sided measurement.
class FloorMeasurement {
  final String id;
  final String surveyId;
  final FloorPoint position;
  final int timestampMs;
  final int? phoneRssi;
  final int? apRssi;
  final int? phoneSnr;
  final int? apSnr;
  final int? phoneRssiMin;
  final int? phoneRssiMax;
  final int? apRssiMin;
  final int? apRssiMax;
  final int? phoneSnrMin;
  final int? phoneSnrMax;
  final int? apSnrMin;
  final int? apSnrMax;
  final bool phoneSnrEstimated;
  final bool apSnrEstimated;
  final int sampleCount;
  final int durationMs;
  final String? apName;
  final FloorGeoFix? geo;

  const FloorMeasurement({
    required this.id,
    this.surveyId = 'legacy',
    required this.position,
    required this.timestampMs,
    this.phoneRssi,
    this.apRssi,
    this.phoneSnr,
    this.apSnr,
    this.phoneRssiMin,
    this.phoneRssiMax,
    this.apRssiMin,
    this.apRssiMax,
    this.phoneSnrMin,
    this.phoneSnrMax,
    this.apSnrMin,
    this.apSnrMax,
    this.phoneSnrEstimated = false,
    this.apSnrEstimated = false,
    this.sampleCount = 1,
    this.durationMs = 0,
    this.apName,
    this.geo,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'surveyId': surveyId,
        'position': position.toJson(),
        'timestamp': timestampMs,
        'phoneRssi': phoneRssi,
        'apRssi': apRssi,
        'phoneSnr': phoneSnr,
        'apSnr': apSnr,
        'phoneRssiMin': phoneRssiMin,
        'phoneRssiMax': phoneRssiMax,
        'apRssiMin': apRssiMin,
        'apRssiMax': apRssiMax,
        'phoneSnrMin': phoneSnrMin,
        'phoneSnrMax': phoneSnrMax,
        'apSnrMin': apSnrMin,
        'apSnrMax': apSnrMax,
        'phoneSnrEstimated': phoneSnrEstimated,
        'apSnrEstimated': apSnrEstimated,
        'sampleCount': sampleCount,
        'durationMs': durationMs,
        'apName': apName,
        'geo': geo?.toJson(),
      };

  factory FloorMeasurement.fromJson(Map<String, dynamic> json) =>
      FloorMeasurement(
        id: json['id'] as String? ?? '',
        surveyId: json['surveyId'] as String? ?? 'legacy',
        position: FloorPoint.fromJson(_map(json['position'])),
        timestampMs: (json['timestamp'] as num?)?.toInt() ?? 0,
        phoneRssi: (json['phoneRssi'] as num?)?.toInt(),
        apRssi: (json['apRssi'] as num?)?.toInt(),
        phoneSnr: (json['phoneSnr'] as num?)?.toInt(),
        apSnr: (json['apSnr'] as num?)?.toInt(),
        phoneRssiMin: (json['phoneRssiMin'] as num?)?.toInt(),
        phoneRssiMax: (json['phoneRssiMax'] as num?)?.toInt(),
        apRssiMin: (json['apRssiMin'] as num?)?.toInt(),
        apRssiMax: (json['apRssiMax'] as num?)?.toInt(),
        phoneSnrMin: (json['phoneSnrMin'] as num?)?.toInt(),
        phoneSnrMax: (json['phoneSnrMax'] as num?)?.toInt(),
        apSnrMin: (json['apSnrMin'] as num?)?.toInt(),
        apSnrMax: (json['apSnrMax'] as num?)?.toInt(),
        phoneSnrEstimated: json['phoneSnrEstimated'] == true,
        apSnrEstimated: json['apSnrEstimated'] == true,
        sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 1,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        apName: json['apName'] as String?,
        geo:
            json['geo'] is Map ? FloorGeoFix.fromJson(_map(json['geo'])) : null,
      );
}

class WifiFloorPlan {
  static const formatVersion = 2;

  final String id;
  final String name;
  final double widthMeters;
  final double heightMeters;
  final double cellSizeMeters;
  final String? backgroundImagePath;
  final double backgroundOpacity;
  final bool captureGps;
  final List<FloorWall> walls;
  final List<FloorSurveySession> surveys;
  final List<FloorMeasurement> measurements;
  final int createdAtMs;
  final int updatedAtMs;

  const WifiFloorPlan({
    required this.id,
    required this.name,
    required this.widthMeters,
    required this.heightMeters,
    required this.cellSizeMeters,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.backgroundImagePath,
    this.backgroundOpacity = 0.55,
    this.captureGps = false,
    this.walls = const [],
    this.surveys = const [],
    this.measurements = const [],
  });

  WifiFloorPlan copyWith({
    String? name,
    double? widthMeters,
    double? heightMeters,
    double? cellSizeMeters,
    String? backgroundImagePath,
    bool clearBackground = false,
    double? backgroundOpacity,
    bool? captureGps,
    List<FloorWall>? walls,
    List<FloorSurveySession>? surveys,
    List<FloorMeasurement>? measurements,
    int? updatedAtMs,
  }) =>
      WifiFloorPlan(
        id: id,
        name: name ?? this.name,
        widthMeters: widthMeters ?? this.widthMeters,
        heightMeters: heightMeters ?? this.heightMeters,
        cellSizeMeters: cellSizeMeters ?? this.cellSizeMeters,
        backgroundImagePath: clearBackground
            ? null
            : backgroundImagePath ?? this.backgroundImagePath,
        backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
        captureGps: captureGps ?? this.captureGps,
        walls: walls ?? this.walls,
        surveys: surveys ?? this.surveys,
        measurements: measurements ?? this.measurements,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'id': id,
        'name': name,
        'widthMeters': widthMeters,
        'heightMeters': heightMeters,
        'cellSizeMeters': cellSizeMeters,
        'backgroundImagePath': backgroundImagePath,
        'backgroundOpacity': backgroundOpacity,
        'captureGps': captureGps,
        'walls': walls.map((wall) => wall.toJson()).toList(),
        'surveys': surveys.map((survey) => survey.toJson()).toList(),
        'measurements': measurements.map((sample) => sample.toJson()).toList(),
        'createdAt': createdAtMs,
        'updatedAt': updatedAtMs,
      };

  factory WifiFloorPlan.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final measurements = _list(json['measurements'])
        .map((item) => FloorMeasurement.fromJson(_map(item)))
        .where((sample) => sample.id.isNotEmpty)
        .toList(growable: false);
    var surveys = _list(json['surveys'])
        .map((item) => FloorSurveySession.fromJson(_map(item)))
        .where((survey) => survey.id.isNotEmpty && survey.name.isNotEmpty)
        .toList(growable: false);
    if (surveys.isEmpty && measurements.isNotEmpty) {
      final timestamps = measurements.map((sample) => sample.timestampMs);
      surveys = [
        FloorSurveySession(
          id: 'legacy',
          name: 'Imported measurements',
          startedAtMs: timestamps.reduce((a, b) => a < b ? a : b),
          updatedAtMs: timestamps.reduce((a, b) => a > b ? a : b),
        ),
      ];
    }
    return WifiFloorPlan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      widthMeters: _positive(json['widthMeters'], 10),
      heightMeters: _positive(json['heightMeters'], 10),
      cellSizeMeters: _positive(json['cellSizeMeters'], 1),
      backgroundImagePath: json['backgroundImagePath'] as String?,
      backgroundOpacity:
          ((json['backgroundOpacity'] as num?)?.toDouble() ?? 0.55)
              .clamp(0.1, 1),
      captureGps: json['captureGps'] == true,
      walls: _list(json['walls'])
          .map((item) => FloorWall.fromJson(_map(item)))
          .toList(growable: false),
      surveys: surveys,
      measurements: measurements,
      createdAtMs: (json['createdAt'] as num?)?.toInt() ?? now,
      updatedAtMs: (json['updatedAt'] as num?)?.toInt() ?? now,
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<Object?> _list(Object? value) => value is List ? value : const [];

double _positive(Object? value, double fallback) {
  final parsed = (value as num?)?.toDouble();
  return parsed != null && parsed.isFinite && parsed > 0 ? parsed : fallback;
}
