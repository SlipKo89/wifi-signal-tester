import 'dart:io';

import 'package:flutter/services.dart';

/// Reads a small, non-secret device/app snapshot for a support report.
/// No hardware identifiers (serial, IMEI, Android ID) are requested.
class DeviceInfoService {
  static const _channel = MethodChannel('wifi_apk/phone');

  Future<Map<String, Object?>> read() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'deviceInfo',
      );
      if (raw != null) return Map<String, Object?>.from(raw);
    } catch (_) {
      // Method channels are unavailable in unit tests and on future platforms.
    }
    return {
      'platform': Platform.operatingSystem,
      'platform_version': Platform.operatingSystemVersion,
    };
  }
}
