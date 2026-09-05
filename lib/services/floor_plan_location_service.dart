import 'package:flutter/services.dart';

import '../wifi_map/wifi_floor_plan.dart';

class FloorPlanLocationService {
  static const _channel = MethodChannel('wifi_apk/phone');

  /// Best-effort foreground location context. It does not start tracking or
  /// request background access; an unavailable fix simply returns null.
  Future<FloorGeoFix?> lastKnown() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('lastKnownLocation')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return null;
      final latitude = (raw['latitude'] as num?)?.toDouble();
      final longitude = (raw['longitude'] as num?)?.toDouble();
      final accuracy = (raw['accuracy'] as num?)?.toDouble();
      if (latitude == null || longitude == null || accuracy == null) {
        return null;
      }
      return FloorGeoFix(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracy,
        altitudeMeters: (raw['altitude'] as num?)?.toDouble(),
      );
    } on Object {
      return null;
    }
  }
}
