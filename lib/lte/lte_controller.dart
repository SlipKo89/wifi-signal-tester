import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/app_failure.dart';
import '../mikrotik/ssh_host_key_store.dart';
import '../routeros_updates/routeros_security.dart';
import '../audit/audit.dart';
import 'lte_audit.dart';
import 'lte_diagnostics.dart';
import 'lte_history_store.dart';
import 'lte_service.dart';
import 'lte_signal.dart';

enum LteMonitorState { idle, connecting, connected, error }

class LteController extends ChangeNotifier {
  static const liveHistoryLimit = 600;
  static const diagnosticHistoryLimit = 60;
  static const _cleanupTimeout = Duration(seconds: 3);
  static const _activeOperationShutdownTimeout = Duration(seconds: 12);

  final LteService _service;
  final LteHistoryStore recordings;
  final RouterOsSecurityService _routerOsSecurity;
  Timer? _timer;
  bool _refreshing = false;
  Completer<void>? _refreshDone;
  Completer<void>? _connectDone;
  bool _shuttingDown = false;
  Future<void>? _shutdownFuture;
  int _generation = 0;
  int? _recordingSessionId;

  LteMonitorState state = LteMonitorState.idle;
  AppFailure? failure;
  SshHostKeyChangedException? _pendingSshHostKeyChange;
  LteConnection? _lastConnection;
  LteSignal? signal;
  Map<String, String>? routerResource;
  RouterOsSecurityStatus? routerOsSecurityWarning;
  bool routerOsSecurityChecking = false;
  final List<LteSignal> history = [];
  DateTime? lastUpdated;
  Duration pollInterval = const Duration(seconds: 3);
  int recordedSampleCount = 0;
  String? recordingError;
  bool waitingForFirstSample = false;
  int firstSampleAttempts = 0;

  LteController({
    LteService? service,
    LteHistoryStore? historyStore,
    RouterOsSecurityService? routerOsSecurityService,
  })  : _service = service ?? LteService(),
        recordings = historyStore ?? LteHistoryStore(),
        _routerOsSecurity =
            routerOsSecurityService ?? RouterOsSecurityService.instance;

  String? get interfaceName => _service.interfaceName;
  String? get transportKind => _service.transportKind;
  bool get isLive => _timer != null;
  bool get recording => _recordingSessionId != null;
  int? get recordingSessionId => _recordingSessionId;
  bool get firstSampleTakingLong =>
      waitingForFirstSample && firstSampleAttempts >= 3;
  LteDiagnosticReport get diagnosis =>
      LteDiagnostics.evaluate(signal, history: _recentHistory);

  Future<List<Finding>> runAudit(LteAuditRole role) =>
      LteAuditEngine().run(_service, role: role, signal: signal);

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

  Future<bool> connect(LteConnection connection) {
    if (_shuttingDown) return Future.value(false);
    final done = Completer<void>();
    _connectDone = done;
    return _connectTracked(connection, done);
  }

  Future<bool> _connectTracked(
    LteConnection connection,
    Completer<void> done,
  ) async {
    try {
      return await _connectInternal(connection);
    } finally {
      if (!done.isCompleted) done.complete();
      if (identical(_connectDone, done)) _connectDone = null;
    }
  }

  Future<bool> _connectInternal(LteConnection connection) async {
    _generation++;
    final generation = _generation;
    await stopRecording(notify: false);
    if (_shuttingDown || generation != _generation) return false;
    stopLive(notify: false);
    state = LteMonitorState.connecting;
    failure = null;
    _pendingSshHostKeyChange = null;
    signal = null;
    routerResource = null;
    routerOsSecurityWarning = null;
    routerOsSecurityChecking = false;
    history.clear();
    lastUpdated = null;
    recordedSampleCount = 0;
    recordingError = null;
    waitingForFirstSample = false;
    firstSampleAttempts = 0;
    _lastConnection = connection;
    notifyListeners();

    try {
      await _service.connect(connection);
      if (_shuttingDown || generation != _generation) {
        await _ignoreCleanup(_service.close);
        return false;
      }
      routerResource = await _service.readResource();
      if (_shuttingDown || generation != _generation) {
        await _ignoreCleanup(_service.close);
        return false;
      }
      state = LteMonitorState.connected;
      waitingForFirstSample = true;
      notifyListeners();
      unawaited(_refreshRouterOsSecurity(generation, connection.host));
      startLive();
      await refresh();
      if (_shuttingDown || generation != _generation) return false;
      return true;
    } catch (e) {
      if (_shuttingDown || generation != _generation) {
        await _ignoreCleanup(_service.close);
        return false;
      }
      if (e is SshHostKeyChangedException) {
        _pendingSshHostKeyChange = e;
      }
      state = LteMonitorState.error;
      failure = AppFailure.classify(e);
      notifyListeners();
      await _ignoreCleanup(_service.close);
      return false;
    }
  }

  Future<void> _refreshRouterOsSecurity(int generation, String host) async {
    final version = routerResource?['version'];
    if (version == null || version.trim().isEmpty) return;
    routerOsSecurityChecking = true;
    notifyListeners();
    try {
      final cached = await _routerOsSecurity.catalog(allowNetwork: false);
      if (_shuttingDown || generation != _generation) return;
      routerOsSecurityWarning = _routerOsSecurity.evaluate(
        host: host,
        installedVersion: version,
        catalog: cached,
      );
      notifyListeners();
      final current = await _routerOsSecurity.catalog();
      if (_shuttingDown || generation != _generation) return;
      routerOsSecurityWarning = _routerOsSecurity.evaluate(
        host: host,
        installedVersion: version,
        catalog: current,
      );
    } finally {
      if (!_shuttingDown && generation == _generation) {
        routerOsSecurityChecking = false;
        notifyListeners();
      }
    }
  }

  Future<void> retry() async {
    if (_shuttingDown) return;
    final connection = _lastConnection;
    if (connection == null) return;
    if (state == LteMonitorState.connected) {
      await refresh();
    } else {
      await connect(connection);
    }
  }

  Future<void> trustNewSshHostKey() async {
    if (_shuttingDown) return;
    final change = _pendingSshHostKeyChange;
    if (change == null) return;
    await trustChangedSshHostKey(change);
    _pendingSshHostKeyChange = null;
    await retry();
  }

  Future<void> refresh() async {
    if (_refreshing || _shuttingDown || state != LteMonitorState.connected) {
      return;
    }
    _refreshing = true;
    final done = Completer<void>();
    _refreshDone = done;
    final generation = _generation;
    if (waitingForFirstSample) firstSampleAttempts++;
    try {
      final next = await _service.readSignal();
      if (generation != _generation) return;
      if (!next.hasUsableRadioMetrics && !next.hasDefinitiveRegistrationState) {
        // Keep polling: some RouterOS SSH sessions initially return a complete
        // looking row whose radio values are all zero. Do not grade or persist
        // that placeholder as a real measurement.
        failure = null;
        return;
      }
      signal = next;
      waitingForFirstSample = false;
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
      if (!done.isCompleted) done.complete();
      if (identical(_refreshDone, done)) _refreshDone = null;
      if (!_shuttingDown && generation == _generation) notifyListeners();
    }
  }

  void startLive() {
    if (_shuttingDown) return;
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
    if (notify && !_shuttingDown) notifyListeners();
  }

  Future<bool> startRecording({String? routerLabel}) async {
    if (_shuttingDown ||
        recording ||
        state != LteMonitorState.connected ||
        signal == null) {
      return false;
    }
    final current = signal!;
    final now = DateTime.now();
    final router = routerBoard ?? routerLabel;
    final routerHost = routerLabel?.trim();
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
        routerHost:
            routerHost == null || routerHost.isEmpty ? null : routerHost,
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
    if (_shuttingDown) {
      await shutdown();
      return;
    }
    _generation++;
    stopLive(notify: false);
    final serviceClose = _ignoreCleanup(_service.close);
    final refresh = _refreshDone?.future;
    if (refresh != null) await refresh;
    await stopRecording(notify: false);
    await serviceClose;
    state = LteMonitorState.idle;
    failure = null;
    _pendingSshHostKeyChange = null;
    signal = null;
    routerResource = null;
    routerOsSecurityWarning = null;
    routerOsSecurityChecking = false;
    history.clear();
    lastUpdated = null;
    recordedSampleCount = 0;
    waitingForFirstSample = false;
    firstSampleAttempts = 0;
    notifyListeners();
  }

  /// Terminal, idempotent cleanup for the controller's timer, current
  /// operation, RouterOS transport and SQLite history.
  Future<void> shutdown() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;
    _shuttingDown = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    final future = _shutdownResources();
    _shutdownFuture = future;
    return future;
  }

  Future<void> _shutdownResources() async {
    final connect = _connectDone?.future;
    final refresh = _refreshDone?.future;
    if (connect != null || refresh != null) {
      try {
        await Future.wait([
          if (connect != null) connect,
          if (refresh != null) refresh,
        ]).timeout(_activeOperationShutdownTimeout);
      } catch (_) {
        // Continue with bounded resource cleanup even if a transport call is
        // stuck beyond its own normal timeout.
      }
    }
    await _ignoreCleanup(() => stopRecording(notify: false));
    await Future.wait([
      _ignoreCleanup(_service.close),
      _ignoreCleanup(recordings.close),
    ]);
  }

  Future<void> _ignoreCleanup(Future<void> Function() action) async {
    try {
      await action().timeout(_cleanupTimeout);
    } catch (_) {
      // Cleanup is best-effort, but its Future is always observed.
    }
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
    unawaited(shutdown());
    super.dispose();
  }
}
