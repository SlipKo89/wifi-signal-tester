import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'wifi_floor_plan.dart';

typedef FloorMapDirectoryProvider = Future<Directory> Function();

/// Local storage for floor plans and user-selected image copies.
///
/// Nothing is uploaded. Deleting a map removes only files previously copied
/// into this app-owned directory.
class WifiFloorPlanStore {
  static const _operationTimeout = Duration(seconds: 8);
  static const maxImageBytes = 25 * 1024 * 1024;

  final FloorMapDirectoryProvider _directoryProvider;

  WifiFloorPlanStore({FloorMapDirectoryProvider? directoryProvider})
      : _directoryProvider =
            directoryProvider ?? getApplicationDocumentsDirectory;

  Future<Directory> _root() async {
    final documents = await _directoryProvider().timeout(_operationTimeout);
    final root = Directory(p.join(documents.path, 'wifi_floor_maps'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  Future<File> _index() async =>
      File(p.join((await _root()).path, 'maps.json'));

  Future<List<WifiFloorPlan>> loadAll() async {
    final file = await _index();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path).timeout(_operationTimeout);
    }
    if (!await file.exists()) return [];
    final raw = await file.readAsString().timeout(_operationTimeout);
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Floor map index is not a list');
    }
    final plans = decoded
        .whereType<Map>()
        .map((json) => WifiFloorPlan.fromJson(Map<String, dynamic>.from(json)))
        .where((plan) => plan.id.isNotEmpty && plan.name.isNotEmpty)
        .toList();
    plans.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return plans;
  }

  Future<void> save(WifiFloorPlan plan) async {
    final plans = await loadAll();
    final index = plans.indexWhere((item) => item.id == plan.id);
    if (index < 0) {
      plans.add(plan);
    } else {
      plans[index] = plan;
    }
    await _writeIndex(plans);
  }

  Future<void> _writeIndex(List<WifiFloorPlan> plans) async {
    final target = await _index();
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    final json = jsonEncode(plans.map((plan) => plan.toJson()).toList());
    await temporary.writeAsString(json, flush: true).timeout(_operationTimeout);
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    try {
      await temporary.rename(target.path).timeout(_operationTimeout);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<String> saveBackground({
    required String planId,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(planId)) {
      throw const FormatException('Invalid floor-map image identifier');
    }
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const FormatException('Image must be between 1 byte and 25 MB');
    }
    final safeExtension = _safeExtension(extension);
    final directory = Directory(p.join((await _root()).path, 'images'));
    if (!await directory.exists()) await directory.create(recursive: true);
    final file = File(p.join(directory.path, '$planId.$safeExtension'));
    await file.writeAsBytes(bytes, flush: true).timeout(_operationTimeout);
    return file.path;
  }

  Future<void> delete(String id) async {
    final plans = await loadAll();
    final removed = plans.where((plan) => plan.id == id).toList();
    plans.removeWhere((plan) => plan.id == id);
    await _writeIndex(plans);
    for (final plan in removed) {
      await deleteOwnedBackground(plan.backgroundImagePath);
    }
  }

  Future<void> deleteOwnedBackground(String? path) async {
    if (path == null || path.isEmpty) return;
    final root = p.normalize((await _root()).path);
    final normalized = p.normalize(path);
    if (!p.isWithin(root, normalized)) return;
    final file = File(normalized);
    if (await file.exists()) await file.delete();
  }

  String _safeExtension(String value) {
    final extension = value.toLowerCase().replaceFirst('.', '');
    return const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
        ? extension
        : 'jpg';
  }
}
