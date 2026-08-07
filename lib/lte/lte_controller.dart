import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/app_failure.dart';
import 'lte_diagnostics.dart';
import 'lte_history_store.dart';
import 'lte_service.dart';
import 'lte_signal.dart';

enum LteMonitorState { idle, connecting, connected, error }

class LteController extends ChangeNotifier {
  static const liveHistoryLimit = 600;
  static const diagnosticHistoryLimit = 60;

  final LteService _service = LteService();
  final LteHistoryStore recordings = LteHistoryStore();
  Timer? _timer;
  bool _refreshing = false;
  int _generation = 0;
  int? _recordingSessionId;

  LteMonitorState state = LteMonitorState.idle;
  AppFailure? failure;
  LteConnection? _lastConnection;
  LteSignal? signal;
  Map<String, String>? routerResource;
  final List<LteSignal> history = [];
  DateTime? lastUpdated;
  Duration pollInterval = const Duration(seconds: 3);
  int recordedSampleCount = 0;
  String? recordingError;

  String? get interfaceName => _service.interfaceName;
  String? get transportKind => _service.transportKind;
  bool get isLive => _timer != null;
  bool get recording => _recordingSessionId != null;
  int? get recordingSessionId => _recordingSessionId;
  LteDiagnosticReport get diagnosis =>
      LteDiagnostics.evaluate(signal, history: _recentHistory);

  List<LteSignal> get _recentHistory {
    if (history.length <= diagnosticHistoryLimit) return history;
    return history.sublist(history.length - diagnosticHistoryLimit);
  }

  String? get routerBoard => routerResource?['board-name'];
  String? get routerVersion => routerResource?['version'];
  int? get cpuLoad {
    final raw = routerResource?['cpu-load'];
    if (raw == null) return null;
    return int.tryParse(RegExp(r'\d+').firstMatch(raw)?.group(0) ?? '');
  }

  Future<bool> connect(LteConnection connection) async {
    await stopRecording(notify: false);
    _generation++;
    final generation = _generation;
    stopLive(notify: false);
    state = LteMonitorState.connecting;
    failure = null;
    signal = null;
    routerResource = null;
    history.clear();
    recordedSampleCount = 0;
    recordingError = null;
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
      if (history.length > liveHistoryLimit) history.removeAt(0);
      await _recordIfNeeded(next);
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
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    notifyListeners();
  }

  void setPollInterval(Duration value) {
    final milliseconds = value.inMilliseconds.clamp(1000, 30000);
    final next = Duration(milliseconds: milliseconds);
    if (next == pollInterval) return;
    pollInterval = next;
    if (isLive) startLive();
  }

  void stopLive({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    if (notify) notifyListeners();
  }

  Future<bool> startRecording({String? routerLabel}) async {
    if (recording || state != LteMonitorState.connected || signal == null) {
      return false;
    }
    final current = signal!;
    final now = DateTime.now();
    final router = routerBoard ?? routerLabel;
    final titleParts = <String>[
      if (router != null && router.trim().isNotEmpty) router.trim(),
      current.interfaceName,
      _shortDate(now),
    ];
    try {
      _recordingSessionId = await recordings.startSession(
        startedMs: now.millisecondsSinceEpoch,
        title: titleParts.join(' · '),
        router: router,
        interfaceName: current.interfaceName,
        operatorName: current.operatorName,
        technology: current.technology,
      );
      recordedSampleCount = 0;
      recordingError = null;
      await _recordIfNeeded(current);
      notifyListeners();
      return recording;
    } catch (error) {
      _recordingSessionId = null;
      recordingError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> stopRecording({bool notify = true}) async {
    final id = _recordingSessionId;
    _recordingSessionId = null;
    if (id != null) {
      try {
        await recordings.finishSession(
            id, DateTime.now().millisecondsSinceEpoch);
      } catch (error) {
        recordingError = error.toString();
      }
    }
    if (notify) notifyListeners();
  }

  Future<void> _recordIfNeeded(LteSignal next) async {
    final id = _recordingSessionId;
    if (id == null) return;
    try {
      await recordings.addSample(id, LteRecordedSample.fromSignal(next));
      recordedSampleCount++;
      recordingError = null;
    } catch (error) {
      _recordingSessionId = null;
      recordingError = error.toString();
      try {
        await recordings.finishSession(
          id,
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        // Preserve the original write error for the UI.
      }
    }
  }

  String _shortDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> disconnect() async {
    _generation++;
    stopLive(notify: false);
    await stopRecording(notify: false);
    await _service.close();
    state = LteMonitorState.idle;
    failure = null;
    signal = null;
    routerResource = null;
    history.clear();
    recordedSampleCount = 0;
    notifyListeners();
  }

  ({double min, double average, double max})? stats(
    double? Function(LteSignal) value,
  ) {
    final values = _recentHistory.map(value).whereType<double>().toList();
    if (values.isEmpty) return null;
    values.sort();
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (min: values.first, average: avg, max: values.last);
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    unawaited(() async {
      await stopRecording(notify: false);
      await recordings.close();
    }());
    unawaited(_service.close());
    super.dispose();
  }
}
