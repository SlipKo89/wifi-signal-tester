import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'zabbix_binding.dart';

/// Non-secret links between an app measurement source and Zabbix items.
/// API tokens remain exclusively in [ZabbixCredentialsStore].
class ZabbixBindingStore {
  static const _key = 'zabbix_session_bindings_v1';

  Future<List<ZabbixBinding>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => ZabbixBinding.fromJson(
                value.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((binding) =>
              binding.subjectKey.isNotEmpty &&
              binding.profileUrl.isNotEmpty &&
              binding.hostId.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<ZabbixBinding?> load(
    ZabbixBindingScope scope,
    String subjectKey,
  ) async {
    final target = '${scope.name}:$subjectKey';
    for (final binding in await loadAll()) {
      if (binding.storageKey == target) return binding;
    }
    return null;
  }

  Future<void> save(ZabbixBinding binding) async {
    final bindings = (await loadAll()).toList();
    bindings.removeWhere((saved) => saved.storageKey == binding.storageKey);
    bindings.insert(0, binding);
    await _write(bindings);
  }

  Future<void> remove(ZabbixBindingScope scope, String subjectKey) async {
    final target = '${scope.name}:$subjectKey';
    final bindings = (await loadAll()).toList()
      ..removeWhere((binding) => binding.storageKey == target);
    await _write(bindings);
  }

  Future<void> _write(List<ZabbixBinding> bindings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(bindings.map((binding) => binding.toJson()).toList()),
    );
  }
}
