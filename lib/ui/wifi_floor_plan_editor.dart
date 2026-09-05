import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/floor_plan_location_service.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import '../wifi_map/floor_measurement_capture.dart';
import '../wifi_map/wifi_floor_plan.dart';
import '../wifi_map/wifi_floor_plan_store.dart';
import 'theme.dart';
import 'widgets/app_safe_area.dart';

enum _MapTool { move, measure, wall, calibrate, erase }

enum _HeatmapMetric { phoneRssi, apRssi, phoneSnr, apSnr }

class WifiFloorPlanEditor extends StatefulWidget {
  final WifiFloorPlan plan;
  final WifiFloorPlanStore store;
  final MonitorController? monitor;
  final FloorPlanLocationService? locationService;

  const WifiFloorPlanEditor({
    super.key,
    required this.plan,
    required this.store,
    this.monitor,
    this.locationService,
  });

  @override
  State<WifiFloorPlanEditor> createState() => _WifiFloorPlanEditorState();
}

class _WifiFloorPlanEditorState extends State<WifiFloorPlanEditor> {
  late WifiFloorPlan _plan;
  final _transform = TransformationController();
  final List<List<FloorWall>> _undo = [];
  _MapTool _tool = _MapTool.move;
  FloorPoint? _draftStart;
  FloorPoint? _draftEnd;
  FloorPoint? _calibrationStart;
  FloorPoint? _calibrationEnd;
  FloorBarrierKind _barrierKind = FloorBarrierKind.wall;
  FloorMaterial _barrierMaterial = FloorMaterial.unknown;
  _HeatmapMetric _heatmapMetric = _HeatmapMetric.phoneRssi;
  String? _selectedSurveyId;
  Future<void> _saveTail = Future.value();
  bool _saving = false;
  String? _saveError;
  FloorMeasurementAccumulator? _capture;
  FloorPoint? _capturePosition;
  DateTime? _lastCapturePoll;
  Timer? _captureTimeout;
  bool _captureFinishing = false;
  static const _targetSamples = 5;

  double get _pixelsPerMeter {
    final longest = math.max(_plan.widthMeters, _plan.heightMeters);
    return math.min(72, math.max(12, 2200 / longest));
  }

  Size get _canvasSize => Size(
        _plan.widthMeters * _pixelsPerMeter,
        _plan.heightMeters * _pixelsPerMeter,
      );

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    if (_plan.surveys.isNotEmpty) {
      _selectedSurveyId = _plan.surveys.last.id;
    }
    widget.monitor?.addListener(_onMonitorUpdate);
  }

  @override
  void dispose() {
    _captureTimeout?.cancel();
    widget.monitor?.removeListener(_onMonitorUpdate);
    _transform.dispose();
    super.dispose();
  }

  void _queueSave() {
    final snapshot = _plan.copyWith(
      walls: List.unmodifiable(_plan.walls),
      surveys: List.unmodifiable(_plan.surveys),
      measurements: List.unmodifiable(_plan.measurements),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _plan = snapshot;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    _saveTail = _saveTail.then((_) => widget.store.save(snapshot)).then((_) {
      if (mounted) setState(() => _saving = false);
    }).catchError((Object error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = error.toString();
        });
      }
    });
  }

  FloorSurveySession? get _selectedSurvey {
    final id = _selectedSurveyId;
    if (id == null) return null;
    for (final survey in _plan.surveys) {
      if (survey.id == id) return survey;
    }
    return null;
  }

  List<FloorMeasurement> get _visibleMeasurements {
    final id = _selectedSurveyId;
    if (id == null) return const [];
    return _plan.measurements
        .where((sample) => sample.surveyId == id)
        .toList(growable: false);
  }

  FloorSignalSnapshot? _currentSnapshot() {
    final monitor = widget.monitor;
    final poll = monitor?.lastSuccessfulPoll;
    final phoneRssi = monitor?.phoneSignal?.rssiDbm;
    final apRssi = monitor?.stationSignal?.signalDbm;
    final phoneSnr = monitor?.phoneSnr;
    final apSnr = monitor?.apSnr;
    if (monitor == null ||
        monitor.state != MonitorState.connected ||
        !monitor.isLive ||
        poll == null ||
        phoneRssi == null ||
        apRssi == null ||
        phoneSnr == null ||
        apSnr == null) {
      return null;
    }
    final linkKey = monitor.phoneSignal?.bssid ??
        monitor.stationSignal?.interfaceName ??
        monitor.phoneSignal?.ssid;
    if (linkKey == null || linkKey.isEmpty) return null;
    return FloorSignalSnapshot(
      capturedAt: poll,
      linkKey: linkKey,
      phoneRssi: phoneRssi,
      apRssi: apRssi,
      phoneSnr: phoneSnr,
      apSnr: apSnr,
      phoneSnrEstimated: monitor.phoneSnrIsEstimate,
      apSnrEstimated: monitor.apSnrIsEstimate,
      apName: monitor.stationSignal?.interfaceName ?? monitor.connectedApName,
    );
  }

  void _onMonitorUpdate() {
    final capture = _capture;
    if (capture == null || _captureFinishing || !mounted) return;
    final snapshot = _currentSnapshot();
    if (snapshot == null || snapshot.capturedAt == _lastCapturePoll) return;
    if (!capture.accepts(snapshot)) {
      _cancelCapture(showRoamMessage: true);
      return;
    }
    capture.add(snapshot);
    _lastCapturePoll = snapshot.capturedAt;
    setState(() {});
    if (capture.length >= _targetSamples) _finishCapture();
  }

  Future<void> _measure(TapUpDetails details) async {
    if (_tool != _MapTool.measure || _capture != null) return;
    final position = _point(details.localPosition);
    if (_selectedSurvey == null) {
      final created = await _createSurvey();
      if (!created || !mounted) return;
    }
    final snapshot = _currentSnapshot();
    if (snapshot == null) {
      _message(context.read<SettingsController>().l.t(
            'Start live MikroTik monitoring and wait for both RSSI/SNR sides before placing a point.',
            'Запусти живой мониторинг MikroTik и дождись RSSI/SNR обеих сторон перед постановкой точки.',
          ));
      return;
    }
    setState(() {
      _capture = FloorMeasurementAccumulator(snapshot);
      _capturePosition = position;
      _lastCapturePoll = snapshot.capturedAt;
    });
    _captureTimeout?.cancel();
    final pollSeconds = context.read<SettingsController>().pollSeconds;
    final timeoutSeconds = math.max(35, pollSeconds * 7);
    _captureTimeout = Timer(Duration(seconds: timeoutSeconds), () {
      if (!mounted || _capture == null) return;
      if (_capture!.length >= 3) {
        _finishCapture();
      } else {
        _cancelCapture(showTimeoutMessage: true);
      }
    });
  }

  Future<void> _finishCapture() async {
    final capture = _capture;
    final position = _capturePosition;
    final survey = _selectedSurvey;
    if (capture == null ||
        position == null ||
        survey == null ||
        _captureFinishing) {
      return;
    }
    _captureFinishing = true;
    _captureTimeout?.cancel();
    FloorGeoFix? geo;
    if (_plan.captureGps) {
      geo = await (widget.locationService ?? FloorPlanLocationService())
          .lastKnown();
    }
    if (!mounted || _capture != capture) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sample = capture.build(
      id: 'point-${DateTime.now().microsecondsSinceEpoch}',
      surveyId: survey.id,
      position: position,
      geo: geo,
    );
    final surveys = _plan.surveys
        .map((item) =>
            item.id == survey.id ? item.copyWith(updatedAtMs: now) : item)
        .toList(growable: false);
    setState(() {
      _plan = _plan.copyWith(
        surveys: surveys,
        measurements: [..._plan.measurements, sample],
      );
      _capture = null;
      _capturePosition = null;
      _lastCapturePoll = null;
      _captureFinishing = false;
    });
    _queueSave();
    if (_plan.captureGps && geo == null) {
      _message(context.read<SettingsController>().l.t(
            'Point saved; GPS context was unavailable.',
            'Точка сохранена; GPS-контекст был недоступен.',
          ));
    }
  }

  void _cancelCapture({
    bool showRoamMessage = false,
    bool showTimeoutMessage = false,
  }) {
    _captureTimeout?.cancel();
    if (mounted) {
      setState(() {
        _capture = null;
        _capturePosition = null;
        _lastCapturePoll = null;
        _captureFinishing = false;
      });
      final l = context.read<SettingsController>().l;
      if (showRoamMessage) {
        _message(l.t(
          'Measurement cancelled: the device roamed to another access point.',
          'Замер отменён: устройство перешло на другую точку доступа.',
        ));
      } else if (showTimeoutMessage) {
        _message(l.t(
          'Not enough fresh two-sided readings. Check the connection and try again.',
          'Недостаточно свежих двусторонних отсчётов. Проверь подключение и повтори.',
        ));
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  FloorPoint _rawPoint(Offset local) {
    final rawX = (local.dx / _pixelsPerMeter).clamp(0.0, _plan.widthMeters);
    final rawY = (local.dy / _pixelsPerMeter).clamp(0.0, _plan.heightMeters);
    return FloorPoint(rawX, rawY);
  }

  FloorPoint _point(Offset local) {
    final raw = _rawPoint(local);
    final cell = _plan.cellSizeMeters;
    return FloorPoint(
      (raw.xMeters / cell).round() * cell,
      (raw.yMeters / cell).round() * cell,
    );
  }

  Future<void> _calibrate(TapUpDetails details) async {
    if (_tool != _MapTool.calibrate) return;
    final point = _rawPoint(details.localPosition);
    if (_calibrationStart == null) {
      setState(() {
        _calibrationStart = point;
        _calibrationEnd = null;
      });
      return;
    }
    final start = _calibrationStart!;
    final dx = point.xMeters - start.xMeters;
    final dy = point.yMeters - start.yMeters;
    final currentDistance = math.sqrt(dx * dx + dy * dy);
    if (currentDistance < 0.01) {
      _message(context.read<SettingsController>().l.t(
            'Choose a second point farther from the first one.',
            'Выбери вторую точку дальше от первой.',
          ));
      return;
    }
    setState(() => _calibrationEnd = point);
    final referenceDistance = await showDialog<double>(
      context: context,
      builder: (_) => _CalibrationDialog(
        plan: _plan,
        currentDistance: currentDistance,
      ),
    );
    if (!mounted) return;
    if (referenceDistance == null) {
      setState(() {
        _calibrationStart = null;
        _calibrationEnd = null;
      });
      return;
    }
    try {
      final calibrated = _plan.recalibrated(
        start: start,
        end: point,
        referenceDistanceMeters: referenceDistance,
      );
      setState(() {
        _plan = calibrated;
        _calibrationStart = null;
        _calibrationEnd = null;
      });
      _queueSave();
      _message(context.read<SettingsController>().l.t(
            'Scale saved: ${_number(referenceDistance)} m.',
            'Масштаб сохранён: ${_number(referenceDistance)} м.',
          ));
    } on ArgumentError {
      setState(() {
        _calibrationStart = null;
        _calibrationEnd = null;
      });
      _message(context.read<SettingsController>().l.t(
            'This scale would make the plan smaller than 0.1 m or larger than 500 m.',
            'При таком масштабе план станет меньше 0,1 м или больше 500 м.',
          ));
    }
  }

  void _startWall(DragStartDetails details) {
    if (_tool != _MapTool.wall) return;
    final point = _point(details.localPosition);
    setState(() {
      _draftStart = point;
      _draftEnd = point;
    });
  }

  void _updateWall(DragUpdateDetails details) {
    if (_tool != _MapTool.wall || _draftStart == null) return;
    setState(() => _draftEnd = _point(details.localPosition));
  }

  void _finishWall(DragEndDetails details) {
    final start = _draftStart;
    final end = _draftEnd;
    if (_tool != _MapTool.wall || start == null || end == null) return;
    var changed = false;
    setState(() {
      _draftStart = null;
      _draftEnd = null;
      if ((start.xMeters - end.xMeters).abs() < 0.01 &&
          (start.yMeters - end.yMeters).abs() < 0.01) {
        return;
      }
      _rememberWalls();
      _plan = _plan.copyWith(walls: [
        ..._plan.walls,
        FloorWall(
          start: start,
          end: end,
          kind: _barrierKind,
          material: _barrierMaterial,
        ),
      ]);
      changed = true;
    });
    if (changed) _queueSave();
  }

  void _erase(TapUpDetails details) {
    if (_tool != _MapTool.erase) return;
    final point = Offset(
      details.localPosition.dx / _pixelsPerMeter,
      details.localPosition.dy / _pixelsPerMeter,
    );
    var nearestIndex = -1;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _plan.walls.length; i++) {
      final wall = _plan.walls[i];
      final distance = _segmentDistance(
        point,
        Offset(wall.start.xMeters, wall.start.yMeters),
        Offset(wall.end.xMeters, wall.end.yMeters),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }
    var measurementIndex = -1;
    var measurementDistance = double.infinity;
    for (var i = 0; i < _plan.measurements.length; i++) {
      final sample = _plan.measurements[i];
      if (sample.surveyId != _selectedSurveyId) continue;
      final distance =
          (point - Offset(sample.position.xMeters, sample.position.yMeters))
              .distance;
      if (distance < measurementDistance) {
        measurementDistance = distance;
        measurementIndex = i;
      }
    }
    final eraseMeasurement = measurementIndex >= 0 &&
        measurementDistance < nearestDistance &&
        measurementDistance * _pixelsPerMeter <= 28;
    if (eraseMeasurement) {
      final measurements = [..._plan.measurements]..removeAt(measurementIndex);
      setState(() => _plan = _plan.copyWith(measurements: measurements));
    } else {
      if (nearestIndex < 0 || nearestDistance * _pixelsPerMeter > 22) return;
      _rememberWalls();
      final walls = [..._plan.walls]..removeAt(nearestIndex);
      setState(() => _plan = _plan.copyWith(walls: walls));
    }
    _queueSave();
  }

  void _inspectMeasurement(TapUpDetails details) {
    if (_tool != _MapTool.move) return;
    final sample = _nearestMeasurement(details.localPosition, 30);
    if (sample == null) return;
    final l = context.read<SettingsController>().l;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.t('Measurement point', 'Точка замера'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${_dateTime(DateTime.fromMillisecondsSinceEpoch(sample.timestampMs))}'
                '${sample.apName == null ? '' : ' · ${sample.apName}'}',
                style: const TextStyle(color: Color(0xFF8B949E)),
              ),
              const SizedBox(height: 16),
              _sampleRow(l.t('Phone RSSI', 'RSSI телефона'), sample.phoneRssi,
                  sample.phoneRssiMin, sample.phoneRssiMax, 'dBm'),
              _sampleRow(l.t('AP RSSI', 'RSSI точки'), sample.apRssi,
                  sample.apRssiMin, sample.apRssiMax, 'dBm'),
              _sampleRow(
                  sample.phoneSnrEstimated
                      ? l.t('Phone SNR (estimated)', 'SNR телефона (оценка)')
                      : l.t('Phone SNR', 'SNR телефона'),
                  sample.phoneSnr,
                  sample.phoneSnrMin,
                  sample.phoneSnrMax,
                  'dB'),
              _sampleRow(
                  sample.apSnrEstimated
                      ? l.t('AP SNR (estimated)', 'SNR точки (оценка)')
                      : l.t('AP SNR', 'SNR точки'),
                  sample.apSnr,
                  sample.apSnrMin,
                  sample.apSnrMax,
                  'dB'),
              const SizedBox(height: 8),
              Text(l.t(
                '${sample.sampleCount} readings over ${(sample.durationMs / 1000).toStringAsFixed(1)} s · position ${_number(sample.position.xMeters)}, ${_number(sample.position.yMeters)} m',
                '${sample.sampleCount} отсчётов за ${(sample.durationMs / 1000).toStringAsFixed(1)} с · позиция ${_number(sample.position.xMeters)}, ${_number(sample.position.yMeters)} м',
              )),
              if (sample.geo != null) ...[
                const SizedBox(height: 8),
                Text(
                  l.t(
                    'GPS attached · accuracy ±${_number(sample.geo!.accuracyMeters)} m',
                    'GPS приложен · точность ±${_number(sample.geo!.accuracyMeters)} м',
                  ),
                  style: const TextStyle(color: Color(0xFF8B949E)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  FloorMeasurement? _nearestMeasurement(Offset local, double maxPixels) {
    final point = Offset(
      local.dx / _pixelsPerMeter,
      local.dy / _pixelsPerMeter,
    );
    FloorMeasurement? nearest;
    var distance = double.infinity;
    for (final sample in _visibleMeasurements) {
      final candidate =
          (point - Offset(sample.position.xMeters, sample.position.yMeters))
              .distance;
      if (candidate < distance) {
        nearest = sample;
        distance = candidate;
      }
    }
    return distance * _pixelsPerMeter <= maxPixels ? nearest : null;
  }

  Widget _sampleRow(
    String label,
    int? average,
    int? minimum,
    int? maximum,
    String unit,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(
            average == null ? '—' : '$average $unit',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          Text(
            minimum == null || maximum == null ? '' : '$minimum…$maximum',
            style: const TextStyle(color: Color(0xFF8B949E)),
          ),
        ]),
      );

  void _rememberWalls() {
    _undo.add(List.unmodifiable(_plan.walls));
    if (_undo.length > 30) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() => _plan = _plan.copyWith(walls: _undo.removeLast()));
    _queueSave();
  }

  Future<bool> _createSurvey() async {
    final l = context.read<SettingsController>().l;
    final now = DateTime.now();
    final suggested = l.t(
      'Survey ${_dateTime(now)}',
      'Замер ${_dateTime(now)}',
    );
    final name = await _askName(
      title: l.t('New survey session', 'Новая сессия обследования'),
      initial: suggested,
    );
    if (name == null || !mounted) return false;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final survey = FloorSurveySession(
      id: 'survey-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      startedAtMs: timestamp,
      updatedAtMs: timestamp,
    );
    setState(() {
      _plan = _plan.copyWith(surveys: [..._plan.surveys, survey]);
      _selectedSurveyId = survey.id;
    });
    _queueSave();
    return true;
  }

  Future<String?> _askName({
    required String title,
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final l = context.read<SettingsController>().l;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: InputDecoration(labelText: l.t('Name', 'Название')),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('Cancel', 'Отмена')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text(l.t('Save', 'Сохранить')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _manageSelectedSurvey() async {
    final survey = _selectedSurvey;
    if (survey == null) return;
    final l = context.read<SettingsController>().l;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            title: Text(survey.name),
            subtitle: Text(l.t(
              '${_visibleMeasurements.length} measurement points',
              '${_visibleMeasurements.length} точек замера',
            )),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l.t('Rename session', 'Переименовать сессию')),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFF85149)),
            title: Text(l.t(
              'Delete session and its points',
              'Удалить сессию и её точки',
            )),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await _askName(
        title: l.t('Rename survey session', 'Переименовать сессию'),
        initial: survey.name,
      );
      if (name == null || !mounted) return;
      setState(() {
        _plan = _plan.copyWith(
          surveys: _plan.surveys
              .map((item) => item.id == survey.id
                  ? item.copyWith(
                      name: name,
                      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
                    )
                  : item)
              .toList(growable: false),
        );
      });
      _queueSave();
      return;
    }
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t('Delete survey?', 'Удалить обследование?')),
            content: Text(l.t(
              'Only this session and its ${_visibleMeasurements.length} app-owned measurement points will be deleted.',
              'Будут удалены только эта сессия и её ${_visibleMeasurements.length} точек, сохранённых приложением.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.t('Delete', 'Удалить')),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    final remaining = _plan.surveys
        .where((item) => item.id != survey.id)
        .toList(growable: false);
    setState(() {
      _plan = _plan.copyWith(
        surveys: remaining,
        measurements: _plan.measurements
            .where((sample) => sample.surveyId != survey.id)
            .toList(growable: false),
      );
      _selectedSurveyId = remaining.isEmpty ? null : remaining.last.id;
    });
    _queueSave();
  }

  Future<void> _editParameters() async {
    final result = await showDialog<_MapParameters>(
      context: context,
      builder: (_) => _MapParametersDialog(plan: _plan),
    );
    if (result == null || !mounted) return;
    final walls = _plan.walls
        .map((wall) => FloorWall(
              start: _clampPoint(wall.start, result.width, result.height),
              end: _clampPoint(wall.end, result.width, result.height),
              kind: wall.kind,
              material: wall.material,
            ))
        .toList();
    final measurements = _plan.measurements
        .map((sample) => FloorMeasurement(
              id: sample.id,
              surveyId: sample.surveyId,
              position:
                  _clampPoint(sample.position, result.width, result.height),
              timestampMs: sample.timestampMs,
              phoneRssi: sample.phoneRssi,
              apRssi: sample.apRssi,
              phoneSnr: sample.phoneSnr,
              apSnr: sample.apSnr,
              phoneRssiMin: sample.phoneRssiMin,
              phoneRssiMax: sample.phoneRssiMax,
              apRssiMin: sample.apRssiMin,
              apRssiMax: sample.apRssiMax,
              phoneSnrMin: sample.phoneSnrMin,
              phoneSnrMax: sample.phoneSnrMax,
              apSnrMin: sample.apSnrMin,
              apSnrMax: sample.apSnrMax,
              phoneSnrEstimated: sample.phoneSnrEstimated,
              apSnrEstimated: sample.apSnrEstimated,
              sampleCount: sample.sampleCount,
              durationMs: sample.durationMs,
              apName: sample.apName,
              geo: sample.geo,
            ))
        .toList(growable: false);
    setState(() {
      _rememberWalls();
      final dimensionsChanged = result.width != _plan.widthMeters ||
          result.height != _plan.heightMeters;
      _plan = _plan.copyWith(
        name: result.name,
        widthMeters: result.width,
        heightMeters: result.height,
        cellSizeMeters: result.cell,
        backgroundOpacity: result.opacity,
        captureGps: result.captureGps,
        walls: walls,
        measurements: measurements,
        clearCalibration: dimensionsChanged,
      );
    });
    _queueSave();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final imagePath = _plan.backgroundImagePath;
    final hasImage = imagePath != null && File(imagePath).existsSync();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_plan.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              _saving
                  ? l.t('Saving…', 'Сохранение…')
                  : _saveError == null
                      ? l.t('Saved locally', 'Сохранено локально')
                      : l.t('Save failed', 'Ошибка сохранения'),
              style: TextStyle(
                fontSize: 11,
                color: _saveError == null
                    ? const Color(0xFF8B949E)
                    : const Color(0xFFF85149),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.t('Undo', 'Отменить'),
            onPressed: _undo.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: l.t('Map parameters', 'Параметры карты'),
            onPressed: _editParameters,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: AppSafeArea(
        child: Column(
          children: [
            if (hasImage)
              MaterialBanner(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                content: Text(l.t(
                  'The image is a tracing layer. Select Wall and trace its contours; the result remains editable.',
                  'Изображение служит подложкой. Выбери «Стена» и обведи контуры — результат останется редактируемым.',
                )),
                actions: [
                  TextButton(
                    onPressed: _editParameters,
                    child: Text(l.t('OPACITY', 'ПРОЗРАЧНОСТЬ')),
                  ),
                ],
              ),
            if (_saveError != null)
              MaterialBanner(
                backgroundColor: const Color(0xFF3A1F24),
                content: Text(l.t(
                  'The latest changes are visible but not saved.',
                  'Последние изменения видны, но не сохранены.',
                )),
                actions: [
                  TextButton(
                      onPressed: _queueSave,
                      child: Text(l.t('RETRY', 'ПОВТОРИТЬ'))),
                ],
              ),
            _surveyBar(l),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF090C10),
                child: InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.2,
                  maxScale: 6,
                  boundaryMargin: const EdgeInsets.all(300),
                  panEnabled: _tool == _MapTool.move,
                  scaleEnabled: _tool == _MapTool.move,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _tool == _MapTool.wall ? _startWall : null,
                    onPanUpdate: _tool == _MapTool.wall ? _updateWall : null,
                    onPanEnd: _tool == _MapTool.wall ? _finishWall : null,
                    onTapUp: switch (_tool) {
                      _MapTool.erase => _erase,
                      _MapTool.measure => _measure,
                      _MapTool.calibrate => _calibrate,
                      _MapTool.move => _inspectMeasurement,
                      _ => null,
                    },
                    child: SizedBox.fromSize(
                      size: _canvasSize,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFFF3F5F7)),
                          if (hasImage)
                            Opacity(
                              opacity: _plan.backgroundOpacity,
                              child: Image(
                                image: ResizeImage.resizeIfNeeded(
                                  4096,
                                  4096,
                                  FileImage(File(imagePath)),
                                ),
                                fit: BoxFit.fill,
                              ),
                            ),
                          CustomPaint(
                            painter: _FloorPlanPainter(
                              plan: _plan,
                              pixelsPerMeter: _pixelsPerMeter,
                              measurements: _visibleMeasurements,
                              heatmapMetric: _heatmapMetric,
                              draftStart: _draftStart,
                              draftEnd: _draftEnd,
                              calibrationStart: _calibrationStart,
                              calibrationEnd: _calibrationEnd,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_capture != null) _captureCard(l),
            _toolBar(l),
          ],
        ),
      ),
    );
  }

  Widget _surveyBar(L10n l) => Material(
        color: AppTheme.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(children: [
            Expanded(
              child: _plan.surveys.isEmpty
                  ? Text(
                      l.t(
                        'No survey session yet',
                        'Сессий обследования пока нет',
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isDense: true,
                        isExpanded: true,
                        value: _selectedSurveyId,
                        icon: const Icon(Icons.expand_more),
                        items: _plan.surveys
                            .map((survey) => DropdownMenuItem(
                                  value: survey.id,
                                  child: Text(
                                    '${survey.name} · ${_plan.measurements.where((sample) => sample.surveyId == survey.id).length}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: _capture == null
                            ? (value) =>
                                setState(() => _selectedSurveyId = value)
                            : null,
                      ),
                    ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l.t('New survey session', 'Новая сессия'),
              onPressed: _capture == null ? _createSurvey : null,
              icon: const Icon(Icons.add_chart_outlined),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l.t('Session actions', 'Действия с сессией'),
              onPressed: _selectedSurvey == null || _capture != null
                  ? null
                  : _manageSelectedSurvey,
              icon: const Icon(Icons.more_vert),
            ),
            PopupMenuButton<_HeatmapMetric>(
              tooltip: l.t('Heatmap layer', 'Слой тепловой карты'),
              initialValue: _heatmapMetric,
              icon: Icon(
                Icons.layers_outlined,
                color: _metricColor(_heatmapMetric, null),
              ),
              onSelected: (value) => setState(() => _heatmapMetric = value),
              itemBuilder: (_) => _HeatmapMetric.values
                  .map((value) => PopupMenuItem(
                        value: value,
                        child: Text(_metricName(l, value)),
                      ))
                  .toList(),
            ),
          ]),
        ),
      );

  Widget _captureCard(L10n l) => Material(
        color: const Color(0xFF13263D),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
          child: Row(children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l.t(
                'Averaging both sides: ${_capture!.length}/$_targetSamples fresh readings',
                'Усредняем обе стороны: ${_capture!.length}/$_targetSamples свежих отсчётов',
              )),
            ),
            TextButton(
              onPressed: _captureFinishing ? null : _cancelCapture,
              child: Text(l.t('Cancel', 'Отмена')),
            ),
          ]),
        ),
      );

  Widget _toolBar(L10n l) => Material(
        color: AppTheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<_MapTool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: _MapTool.move,
                            icon: const Icon(Icons.pan_tool_outlined),
                            label: Text(l.t('Move', 'Обзор')),
                          ),
                          ButtonSegment(
                            value: _MapTool.measure,
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: Text(l.t('Measure', 'Замер')),
                          ),
                          ButtonSegment(
                            value: _MapTool.wall,
                            icon: const Icon(Icons.polyline_outlined),
                            label: Text(l.t('Object', 'Объект')),
                          ),
                          ButtonSegment(
                            value: _MapTool.calibrate,
                            icon: const Icon(Icons.straighten_outlined),
                            label: Text(l.t('Scale', 'Масштаб')),
                          ),
                          ButtonSegment(
                            value: _MapTool.erase,
                            icon: const Icon(Icons.auto_fix_off_outlined),
                            label: Text(l.t('Erase', 'Стереть')),
                          ),
                        ],
                        selected: {_tool},
                        onSelectionChanged: _capture != null
                            ? null
                            : (selection) => setState(() {
                                  _tool = selection.single;
                                  _draftStart = null;
                                  _draftEnd = null;
                                  _calibrationStart = null;
                                  _calibrationEnd = null;
                                }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_number(_plan.cellSizeMeters)} m',
                    style: const TextStyle(color: Color(0xFF8B949E)),
                  ),
                ],
              ),
              if (_tool == _MapTool.wall) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: PopupMenuButton<FloorBarrierKind>(
                        tooltip: l.t('Object type', 'Тип объекта'),
                        onSelected: (value) =>
                            setState(() => _barrierKind = value),
                        itemBuilder: (_) => FloorBarrierKind.values
                            .map((value) => PopupMenuItem(
                                  value: value,
                                  child: Text(_kindName(l, value)),
                                ))
                            .toList(),
                        child: _choice(
                          _kindIcon(_barrierKind),
                          _kindName(l, _barrierKind),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PopupMenuButton<FloorMaterial>(
                        tooltip: l.t('Material', 'Материал'),
                        onSelected: (value) =>
                            setState(() => _barrierMaterial = value),
                        itemBuilder: (_) => FloorMaterial.values
                            .map((value) => PopupMenuItem(
                                  value: value,
                                  child: Text(_materialName(l, value)),
                                ))
                            .toList(),
                        child: _choice(
                          Icons.layers_outlined,
                          _materialName(l, _barrierMaterial),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_tool == _MapTool.measure) ...[
                const SizedBox(height: 7),
                Row(children: [
                  Icon(Icons.layers_outlined,
                      size: 18, color: _metricColor(_heatmapMetric, null)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      l.t(
                        'Tap the plan: 5 fresh monitor cycles will be averaged. Layer: ${_metricName(l, _heatmapMetric)}.',
                        'Нажми на план: усредним 5 свежих циклов мониторинга. Слой: ${_metricName(l, _heatmapMetric)}.',
                      ),
                      style: const TextStyle(
                        color: Color(0xFFB7C0CA),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ]),
              ] else if (_tool == _MapTool.calibrate) ...[
                const SizedBox(height: 7),
                Row(children: [
                  const Icon(Icons.straighten_outlined,
                      size: 18, color: Color(0xFF58A6FF)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _calibrationStart == null
                          ? l.t(
                              'Tap the first end of a known distance. Points are not snapped to the grid.',
                              'Нажми первый конец известного отрезка. Точки не привязываются к сетке.',
                            )
                          : l.t(
                              'Now tap the other end and enter the real distance.',
                              'Теперь нажми второй конец и введи реальное расстояние.',
                            ),
                      style: const TextStyle(
                        color: Color(0xFFB7C0CA),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      );

  Widget _choice(IconData icon, String label) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF303A46)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      );
}

class _FloorPlanPainter extends CustomPainter {
  final WifiFloorPlan plan;
  final double pixelsPerMeter;
  final List<FloorMeasurement> measurements;
  final _HeatmapMetric heatmapMetric;
  final FloorPoint? draftStart;
  final FloorPoint? draftEnd;
  final FloorPoint? calibrationStart;
  final FloorPoint? calibrationEnd;

  const _FloorPlanPainter({
    required this.plan,
    required this.pixelsPerMeter,
    required this.measurements,
    required this.heatmapMetric,
    this.draftStart,
    this.draftEnd,
    this.calibrationStart,
    this.calibrationEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var gridStep = plan.cellSizeMeters;
    final longestCells =
        math.max(plan.widthMeters, plan.heightMeters) / gridStep;
    if (longestCells > 500) gridStep *= (longestCells / 500).ceil();
    final minor = Paint()
      ..color = const Color(0xFFB7C0CA).withValues(alpha: 0.45)
      ..strokeWidth = 0.7;
    final major = Paint()
      ..color = const Color(0xFF78828E).withValues(alpha: 0.7)
      ..strokeWidth = 1.1;
    for (var x = 0.0, index = 0;
        x <= plan.widthMeters + 0.001;
        x += gridStep, index++) {
      canvas.drawLine(
        Offset(x * pixelsPerMeter, 0),
        Offset(x * pixelsPerMeter, size.height),
        index % 5 == 0 ? major : minor,
      );
    }
    for (var y = 0.0, index = 0;
        y <= plan.heightMeters + 0.001;
        y += gridStep, index++) {
      canvas.drawLine(
        Offset(0, y * pixelsPerMeter),
        Offset(size.width, y * pixelsPerMeter),
        index % 5 == 0 ? major : minor,
      );
    }

    _drawMeasurements(canvas);

    for (final wall in plan.walls) {
      final paint = Paint()
        ..color = _barrierColor(wall.kind)
        ..strokeWidth = wall.kind == FloorBarrierKind.wall ? 5 : 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(_offset(wall.start), _offset(wall.end), paint);
      if (wall.kind != FloorBarrierKind.wall) {
        canvas.drawCircle(_offset(wall.start), 4, paint);
        canvas.drawCircle(_offset(wall.end), 4, paint);
      }
    }
    if (draftStart != null && draftEnd != null) {
      canvas.drawLine(
        _offset(draftStart!),
        _offset(draftEnd!),
        Paint()
          ..color = const Color(0xFFD29922)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    final savedCalibration = plan.calibration;
    if (savedCalibration != null) {
      _drawCalibration(
        canvas,
        savedCalibration.start,
        savedCalibration.end,
        '${_number(savedCalibration.referenceDistanceMeters)} m',
        const Color(0xFF2EA043).withValues(alpha: 0.72),
      );
    }
    if (calibrationStart != null) {
      _drawCalibration(
        canvas,
        calibrationStart!,
        calibrationEnd ?? calibrationStart!,
        calibrationEnd == null ? '1' : '2',
        const Color(0xFF1F6FEB),
      );
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFF39414B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawMeasurements(Canvas canvas) {
    final radiusMeters = math.max(1.0, plan.cellSizeMeters * 1.8);
    final radius = radiusMeters * pixelsPerMeter;
    for (final sample in measurements) {
      final value = _measurementValue(sample, heatmapMetric);
      if (value == null) continue;
      final center = _offset(sample.position);
      final color = _metricColor(heatmapMetric, value);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.58),
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0),
          ], stops: const [
            0,
            0.55,
            1
          ]).createShader(
            Rect.fromCircle(center: center, radius: radius),
          ),
      );
    }
    for (final sample in measurements) {
      final value = _measurementValue(sample, heatmapMetric);
      if (value == null) continue;
      final center = _offset(sample.position);
      final color = _metricColor(heatmapMetric, value);
      canvas.drawCircle(
        center,
        8,
        Paint()..color = const Color(0xFFF3F5F7),
      );
      canvas.drawCircle(center, 6, Paint()..color = color);
      final suffix = heatmapMetric == _HeatmapMetric.phoneRssi ||
              heatmapMetric == _HeatmapMetric.apRssi
          ? ' dBm'
          : ' dB';
      final text = TextPainter(
        text: TextSpan(
          text: '$value$suffix',
          style: const TextStyle(
            color: Color(0xFF111820),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            backgroundColor: Color(0xDDF3F5F7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center + const Offset(10, -7));
    }
  }

  void _drawCalibration(
    Canvas canvas,
    FloorPoint start,
    FloorPoint end,
    String label,
    Color color,
  ) {
    final from = _offset(start);
    final to = _offset(end);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);
    canvas.drawCircle(from, 6, Paint()..color = const Color(0xFFF3F5F7));
    canvas.drawCircle(to, 6, Paint()..color = const Color(0xFFF3F5F7));
    canvas.drawCircle(from, 4, paint);
    canvas.drawCircle(to, 4, paint);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          backgroundColor: const Color(0xE8F3F5F7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
        canvas,
        Offset((from.dx + to.dx) / 2 + 7,
            (from.dy + to.dy) / 2 - text.height - 3));
  }

  Offset _offset(FloorPoint point) => Offset(
        point.xMeters * pixelsPerMeter,
        point.yMeters * pixelsPerMeter,
      );

  @override
  bool shouldRepaint(covariant _FloorPlanPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.measurements != measurements ||
      oldDelegate.heatmapMetric != heatmapMetric ||
      oldDelegate.draftStart != draftStart ||
      oldDelegate.draftEnd != draftEnd ||
      oldDelegate.calibrationStart != calibrationStart ||
      oldDelegate.calibrationEnd != calibrationEnd ||
      oldDelegate.pixelsPerMeter != pixelsPerMeter;
}

class _CalibrationDialog extends StatefulWidget {
  final WifiFloorPlan plan;
  final double currentDistance;

  const _CalibrationDialog({
    required this.plan,
    required this.currentDistance,
  });

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _distance;

  @override
  void initState() {
    super.initState();
    _distance = TextEditingController(text: _number(widget.currentDistance));
  }

  @override
  void dispose() {
    _distance.dispose();
    super.dispose();
  }

  double? get _value =>
      double.tryParse(_distance.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final value = _value;
    final factor = value == null ? null : value / widget.currentDistance;
    final newWidth = factor == null ? null : widget.plan.widthMeters * factor;
    final newHeight = factor == null ? null : widget.plan.heightMeters * factor;
    final objectCount =
        widget.plan.walls.length + widget.plan.measurements.length;
    return AlertDialog(
      title: Text(l.t('Calibrate plan scale', 'Калибровка масштаба')),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t(
                'The selected segment is currently ${_number(widget.currentDistance)} m on the plan.',
                'Сейчас выбранный отрезок равен ${_number(widget.currentDistance)} м на плане.',
              )),
              const SizedBox(height: 12),
              TextFormField(
                controller: _distance,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l.t('Real distance, m', 'Реальное расстояние, м'),
                ),
                onChanged: (_) => setState(() {}),
                validator: (_) {
                  if (value == null ||
                      !value.isFinite ||
                      value < 0.05 ||
                      value > 500) {
                    return l.t('Range: 0.05–500', 'Диапазон: 0,05–500');
                  }
                  final resultWidth =
                      widget.plan.widthMeters * value / widget.currentDistance;
                  final resultHeight =
                      widget.plan.heightMeters * value / widget.currentDistance;
                  if (resultWidth < 0.1 ||
                      resultWidth > 500 ||
                      resultHeight < 0.1 ||
                      resultHeight > 500) {
                    return l.t(
                      'Resulting plan must be 0.1–500 m',
                      'Итоговый план должен быть 0,1–500 м',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (newWidth != null && newHeight != null)
                Text(l.t(
                  'Plan: ${_number(widget.plan.widthMeters)} × ${_number(widget.plan.heightMeters)} m → ${_number(newWidth)} × ${_number(newHeight)} m',
                  'План: ${_number(widget.plan.widthMeters)} × ${_number(widget.plan.heightMeters)} м → ${_number(newWidth)} × ${_number(newHeight)} м',
                )),
              if (objectCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  l.t(
                    '$objectCount walls/points will be rescaled and will stay in the same visual positions.',
                    '$objectCount стен/точек будут пересчитаны и останутся на тех же местах изображения.',
                  ),
                  style: const TextStyle(color: Color(0xFFD29922)),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                l.t(
                  'The physical grid-cell size will not change.',
                  'Физический размер клетки не изменится.',
                ),
                style: const TextStyle(color: Color(0xFF8B949E)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Cancel', 'Отмена')),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _value);
          },
          child: Text(l.t('Calibrate', 'Калибровать')),
        ),
      ],
    );
  }
}

class _MapParameters {
  final String name;
  final double width;
  final double height;
  final double cell;
  final double opacity;
  final bool captureGps;

  const _MapParameters(this.name, this.width, this.height, this.cell,
      this.opacity, this.captureGps);
}

class _MapParametersDialog extends StatefulWidget {
  final WifiFloorPlan plan;

  const _MapParametersDialog({required this.plan});

  @override
  State<_MapParametersDialog> createState() => _MapParametersDialogState();
}

class _MapParametersDialogState extends State<_MapParametersDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _cell;
  late double _opacity;
  late bool _captureGps;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plan.name);
    _width = TextEditingController(text: _number(widget.plan.widthMeters));
    _height = TextEditingController(text: _number(widget.plan.heightMeters));
    _cell = TextEditingController(text: _number(widget.plan.cellSizeMeters));
    _opacity = widget.plan.backgroundOpacity;
    _captureGps = widget.plan.captureGps;
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _cell.dispose();
    super.dispose();
  }

  double? _parse(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    String? positive(String? raw, double min, double max) {
      final value = _parse(raw ?? '');
      return value == null || !value.isFinite || value < min || value > max
          ? l.t('Range: $min–$max', 'Диапазон: $min–$max')
          : null;
    }

    return AlertDialog(
      title: Text(l.t('Map parameters', 'Параметры карты')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration:
                      InputDecoration(labelText: l.t('Name', 'Название')),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l.t('Enter a name', 'Укажи название')
                      : null,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                    controller: _width,
                    decoration: InputDecoration(
                        labelText: l.t('Width, m', 'Ширина, м')),
                    validator: (value) => positive(value, 0.1, 500),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextFormField(
                    controller: _height,
                    decoration: InputDecoration(
                        labelText: l.t('Height, m', 'Высота, м')),
                    validator: (value) => positive(value, 0.1, 500),
                  )),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _cell,
                  decoration: InputDecoration(
                      labelText: l.t('Grid cell, m', 'Сторона клетки, м')),
                  validator: (value) => positive(value, 0.1, 10),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _captureGps,
                  onChanged: (value) => setState(() => _captureGps = value),
                  title: Text(l.t(
                    'Attach GPS context to new points',
                    'Добавлять GPS-контекст к новым точкам',
                  )),
                  subtitle: Text(l.t(
                    'Off by default. Indoor pins always remain tied to the plan; GPS is saved only when available.',
                    'По умолчанию выключено. Точка всегда привязана к плану; GPS сохраняется только если доступен.',
                  )),
                ),
                if (widget.plan.backgroundImagePath != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Text(l.t('Image opacity', 'Прозрачность подложки')),
                    Expanded(
                      child: Slider(
                        value: _opacity,
                        min: 0.1,
                        max: 1,
                        divisions: 9,
                        label: '${(_opacity * 100).round()}%',
                        onChanged: (value) => setState(() => _opacity = value),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('Cancel', 'Отмена'))),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
                context,
                _MapParameters(
                  _name.text.trim(),
                  _parse(_width.text)!,
                  _parse(_height.text)!,
                  _parse(_cell.text)!,
                  _opacity,
                  _captureGps,
                ));
          },
          child: Text(l.t('Apply', 'Применить')),
        ),
      ],
    );
  }
}

FloorPoint _clampPoint(FloorPoint point, double width, double height) =>
    FloorPoint(
      point.xMeters.clamp(0, width),
      point.yMeters.clamp(0, height),
    );

double _segmentDistance(Offset point, Offset start, Offset end) {
  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;
  if (dx == 0 && dy == 0) return (point - start).distance;
  final t = (((point.dx - start.dx) * dx + (point.dy - start.dy) * dy) /
          (dx * dx + dy * dy))
      .clamp(0.0, 1.0);
  return (point - Offset(start.dx + t * dx, start.dy + t * dy)).distance;
}

Color _barrierColor(FloorBarrierKind kind) => switch (kind) {
      FloorBarrierKind.wall => const Color(0xFF1F6FEB),
      FloorBarrierKind.door => const Color(0xFFD29922),
      FloorBarrierKind.window => const Color(0xFF00A6C8),
    };

IconData _kindIcon(FloorBarrierKind kind) => switch (kind) {
      FloorBarrierKind.wall => Icons.horizontal_rule,
      FloorBarrierKind.door => Icons.door_front_door_outlined,
      FloorBarrierKind.window => Icons.window_outlined,
    };

String _kindName(L10n l, FloorBarrierKind kind) => switch (kind) {
      FloorBarrierKind.wall => l.t('Wall', 'Стена'),
      FloorBarrierKind.door => l.t('Door', 'Дверь'),
      FloorBarrierKind.window => l.t('Window', 'Окно'),
    };

String _materialName(L10n l, FloorMaterial material) => switch (material) {
      FloorMaterial.unknown => l.t('Unknown material', 'Материал неизвестен'),
      FloorMaterial.drywall => l.t('Drywall', 'Гипсокартон'),
      FloorMaterial.wood => l.t('Wood', 'Дерево'),
      FloorMaterial.glass => l.t('Glass', 'Стекло'),
      FloorMaterial.brick => l.t('Brick', 'Кирпич'),
      FloorMaterial.concrete => l.t('Concrete', 'Бетон'),
      FloorMaterial.reinforcedConcrete =>
        l.t('Reinforced concrete', 'Железобетон'),
      FloorMaterial.metal => l.t('Metal', 'Металл'),
    };

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

int? _measurementValue(
  FloorMeasurement sample,
  _HeatmapMetric metric,
) =>
    switch (metric) {
      _HeatmapMetric.phoneRssi => sample.phoneRssi,
      _HeatmapMetric.apRssi => sample.apRssi,
      _HeatmapMetric.phoneSnr => sample.phoneSnr,
      _HeatmapMetric.apSnr => sample.apSnr,
    };

Color _metricColor(_HeatmapMetric metric, int? value) =>
    metric == _HeatmapMetric.phoneRssi || metric == _HeatmapMetric.apRssi
        ? AppTheme.signalColor(value)
        : AppTheme.snrColor(value);

String _metricName(L10n l, _HeatmapMetric metric) => switch (metric) {
      _HeatmapMetric.phoneRssi => l.t('Phone RSSI', 'RSSI телефона'),
      _HeatmapMetric.apRssi => l.t('AP RSSI', 'RSSI точки'),
      _HeatmapMetric.phoneSnr => l.t('Phone SNR', 'SNR телефона'),
      _HeatmapMetric.apSnr => l.t('AP SNR', 'SNR точки'),
    };

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
