import 'package:flutter/services.dart';

class PickedFloorPlanImage {
  final String name;
  final Uint8List bytes;

  const PickedFloorPlanImage({required this.name, required this.bytes});
}

class PickedFloorPlanProject {
  final String name;
  final Uint8List bytes;

  const PickedFloorPlanProject({required this.name, required this.bytes});
}

abstract interface class FloorPlanImagePicker {
  Future<PickedFloorPlanImage?> pick();
}

abstract interface class FloorPlanProjectPicker {
  Future<PickedFloorPlanProject?> pickProject();
}

/// Opens the platform document picker. It deliberately has no API for browsing
/// arbitrary storage: native code returns only the image chosen by the user.
class NativeFloorPlanImagePicker
    implements FloorPlanImagePicker, FloorPlanProjectPicker {
  static const _channel = MethodChannel('wifi_apk/floor_plan_picker');

  @override
  Future<PickedFloorPlanImage?> pick() async {
    final result = await _pick('pickImage');
    if (result == null) return null;
    final name = result['name'] as String? ?? 'floor-plan.jpg';
    final bytes = result['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw const FormatException('The selected image is empty');
    }
    return PickedFloorPlanImage(name: name, bytes: bytes);
  }

  @override
  Future<PickedFloorPlanProject?> pickProject() async {
    final result = await _pick('pickProject');
    if (result == null) return null;
    final name = result['name'] as String? ?? 'floor-map.wifimap';
    final bytes = result['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw const FormatException('The selected floor-map package is empty');
    }
    return PickedFloorPlanProject(name: name, bytes: bytes);
  }

  Future<Map<String, Object?>?> _pick(String method) => _channel
      .invokeMapMethod<String, Object?>(method)
      .timeout(const Duration(minutes: 2));
}
