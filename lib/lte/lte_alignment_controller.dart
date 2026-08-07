import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lte_alignment.dart';
import 'lte_controller.dart';
import 'lte_signal.dart';

enum LteAlignmentCapturePhase { idle, settling, collecting, ready, error }

/// Orchestrates stable capture windows while [LteAlignmentSession] keeps the
/// pure comparison/grid-search state.
class LteAlignmentController extends ChangeNotifier {
  static const int requiredSamples = 6;
  static const int settlingSeconds = 4;
  static const Duration alignmentPollInterval = Duration(seconds: 2);

  final LteController monitor;
  final LteAlignmentSession session;
  late final bool _monitorWasLive;
  late final Duration _previousPollInterval;

  Timer? _settleTimer;
  Timer? _captureTimeout;
  final List<LteSignal> _captureSamples = [];
  DateTime? _lastAcceptedAt;
  DateTime? _collectingStartedAt;
  LteAlignmentTarget? _captureTarget;

  LteAlignmentCapturePhase phase = LteAlignmentCapturePhase.idle;
  LteAlignmentTarget? selectedTarget;
  int settleRemaining = 0;
  String? error;

  LteAlignmentController({
    required this.monitor,
    required this.session,
  }) {
    _monitorWasLive = monitor.isLive;
    _previousPollInterval = monitor.pollInterval;
    monitor.addListener(_onMonitorChanged);
    monitor.setPollInterval(alignmentPollInterval);
    if (!monitor.isLive) monitor.startLive();
    if (session.points.isNotEmpty) {
      phase = LteAlignmentCapturePhase.ready;
      selectedTarget = session.nextTarget();
    }
  }

  List<LteSignal> get liveHistory => monitor.history;
  List<LteSignal> get captureSamples => List.unmodifiable(_captureSamples);
  int get captureProgress => _captureSamples.length;
  LteAlignmentPoint? get best => session.best;
  LteAlignmentPoint? get latest => session.latest;
  bool get hasSession => session.points.isNotEmpty;
  bool get localOptimum => hasSession && selectedTarget == null;

  void startBaseline() {
    session.reset();
    selectedTarget = session.baselineTarget;
    _startCapture(selectedTarget!);
  }

  void selectDirection(LteAlignmentDirection direction) {
    if (phase != LteAlignmentCapturePhase.ready) return;
    selectedTarget = session.targetFromCurrent(direction);
    notifyListeners();
  }

  void confirmMovedAndMeasure() {
    final target = selectedTarget;
    if (target == null || phase != LteAlignmentCapturePhase.ready) return;
    _startCapture(target);
  }

  void startFineRound() {
    if (!localOptimum) return;
    session.startFineRound();
    selectedTarget = session.baselineTarget;
    _startCapture(selectedTarget!);
  }

  void retryCapture() {
    final target = _captureTarget ?? selectedTarget ?? session.baselineTarget;
    _startCapture(target);
  }

  void cancelCapture() {
    _cancelTimers();
    _captureSamples.clear();
    error = null;
    phase = session.points.isEmpty
        ? LteAlignmentCapturePhase.idle
        : LteAlignmentCapturePhase.ready;
    selectedTarget = session.nextTarget();
    notifyListeners();
  }

  void _startCapture(LteAlignmentTarget target) {
    _cancelTimers();
    _captureTarget = target;
    _captureSamples.clear();
    _lastAcceptedAt = null;
    _collectingStartedAt = null;
    error = null;
    settleRemaining = settlingSeconds;
    phase = LteAlignmentCapturePhase.settling;
    _settleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      settleRemaining--;
      if (settleRemaining <= 0) {
        timer.cancel();
        _settleTimer = null;
        _beginCollecting();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _beginCollecting() {
    phase = LteAlignmentCapturePhase.collecting;
    _collectingStartedAt = DateTime.now();
    _captureTimeout = Timer(const Duration(seconds: 40), () {
      if (phase != LteAlignmentCapturePhase.collecting) return;
      phase = LteAlignmentCapturePhase.error;
      error = 'capture-timeout';
      notifyListeners();
    });
    monitor.refresh();
  }

  void _onMonitorChanged() {
    if (phase != LteAlignmentCapturePhase.collecting) {
      notifyListeners();
      return;
    }
    final sample = monitor.signal;
    final started = _collectingStartedAt;
    if (sample == null ||
        started == null ||
        sample.sampledAt.isBefore(started) ||
        sample.sampledAt == _lastAcceptedAt) {
      notifyListeners();
      return;
    }
    _lastAcceptedAt = sample.sampledAt;
    _captureSamples.add(sample);
    if (_captureSamples.length >= requiredSamples) {
      _captureTimeout?.cancel();
      _captureTimeout = null;
      final registered =
          _captureSamples.where((sample) => sample.registered).length * 2 >=
              _captureSamples.length;
      if (!registered) {
        phase = LteAlignmentCapturePhase.error;
        error = 'not-registered';
      } else if (_captureSamples.every((sample) => !sample.hasRadioMetrics)) {
        phase = LteAlignmentCapturePhase.error;
        error = 'radio-metrics-unavailable';
      } else {
        session.add(_captureTarget!, List.of(_captureSamples));
        phase = LteAlignmentCapturePhase.ready;
        selectedTarget = session.nextTarget();
        _captureTarget = null;
      }
    }
    notifyListeners();
  }

  void _cancelTimers() {
    _settleTimer?.cancel();
    _captureTimeout?.cancel();
    _settleTimer = null;
    _captureTimeout = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    monitor.removeListener(_onMonitorChanged);
    monitor.setPollInterval(_previousPollInterval);
    if (!_monitorWasLive) monitor.stopLive(notify: false);
    super.dispose();
  }
}
