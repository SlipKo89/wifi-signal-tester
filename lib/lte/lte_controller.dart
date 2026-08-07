import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/app_failure.dart';
import 'lte_diagnostics.dart';
import 'lte_service.dart';
import 'lte_signal.dart';

enum LteMonitorState { idle, connecting, connected, error }

class LteController extends ChangeNotifier {
  final LteService _service = LteService();
  Timer? _timer;
  bool _refreshing = false;
  int _generation = 0;

  LteMonitorState state = LteMonitorState.idle;
  AppFailure? failure;
  LteConnection? _lastConnection;
  LteSignal? signal;
  Map<String, String>? routerResource;
  final List<LteSignal> history = [];
  DateTime? lastUpdated;

  String? get interfaceName => _service.interfaceName;
  String? get transportKind => _service.transportKind;
  bool get isLive => _timer != null;
  LteDiagnosticReport get diagnosis =>
      LteDiagnostics.evaluate(signal, history: history);

  String? get routerBoard => routerResource?['board-name'];
  String? get routerVersion => routerResource?['version'];
  int? get cpuLoad {
    final raw = routerResource?['cpu-load'];
    if (raw == null) return null;
    return int.tryParse(RegExp(r'\d+').firstMatch(raw)?.group(0) ?? '');
  }

  Future<bool> connect(LteConnection connection) async {
    _generation++;
    final generation = _generation;
    stopLive(notify: false);
    state = LteMonitorState.connecting;
    failure = null;
    signal = null;
    routerResource = null;
    history.clear();
    _lastConnection = connection;
    notifyListeners();

    try {
      await _service.connect(connection);
      if (generation != _generation) return false;
      routerResource = await _service.readResource();
      if (generation != _generation) return false;
      state = LteMonitorState.connected;
      await refresh();
      if (signal == null) {
        state = LteMonitorState.error;
        notifyListeners();
        await _service.close();
        return false;
      }
      startLive();
      return true;
    } catch (e) {
      if (generation != _generation) return false;
      state = LteMonitorState.error;
      failure = AppFailure.classify(e);
      notifyListeners();
      await _service.close();
      return false;
    }
  }

  Future<void> retry() async {
    final connection = _lastConnection;
    if (connection == null) return;
    if (state == LteMonitorState.connected) {
      await refresh();
    } else {
      await connect(connection);
    }
  }

  Future<void> refresh() async {
    if (_refreshing || state != LteMonitorState.connected) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final next = await _service.readSignal();
      if (generation != _generation) return;
      signal = next;
      lastUpdated = next.sampledAt;
      failure = null;
      history.add(next);
      if (history.length > 60) history.removeAt(0);
    } catch (e) {
      if (generation != _generation) return;
      failure = AppFailure.classify(e);
    } finally {
      _refreshing = false;
      if (generation == _generation) notifyListeners();
    }
  }

  void startLive() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    notifyListeners();
  }

  void stopLive({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    if (notify) notifyListeners();
  }

  Future<void> disconnect() async {
    _generation++;
    stopLive(notify: false);
    await _service.close();
    state = LteMonitorState.idle;
    failure = null;
    signal = null;
    routerResource = null;
    history.clear();
    notifyListeners();
  }

  ({double min, double average, double max})? stats(
    double? Function(LteSignal) value,
  ) {
    final values = history.map(value).whereType<double>().toList();
    if (values.isEmpty) return null;
    values.sort();
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (min: values.first, average: avg, max: values.last);
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _service.close();
    super.dispose();
  }
}
