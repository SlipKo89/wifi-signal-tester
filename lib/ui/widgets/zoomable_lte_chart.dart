import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class LteChartPoint {
  final DateTime sampledAt;
  final double? rsrp;
  final double? rsrq;
  final double? sinr;
  final double? rssi;
  final int? cqi;

  const LteChartPoint({
    required this.sampledAt,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
    this.cqi,
  });
}

class LteChartDataset {
  final String name;
  final Color color;
  final List<LteChartPoint> points;

  const LteChartDataset({
    required this.name,
    required this.color,
    required this.points,
  });
}

/// LTE radio history with 1x…20x horizontal zoom, buttons, slider and pinch.
/// At 1x the complete recording fits the viewport; zooming reveals individual
/// samples and enables horizontal panning.
class ZoomableLteChart extends StatefulWidget {
  final List<LteChartDataset> datasets;
  final bool autoFollow;
  final double initialZoom;
  final bool showRssiAndCqi;
  final String zoomHint;
  final String zoomInTooltip;
  final String zoomOutTooltip;

  const ZoomableLteChart({
    super.key,
    required this.datasets,
    this.autoFollow = false,
    this.initialZoom = 1,
    this.showRssiAndCqi = false,
    this.zoomHint =
        '1× — complete session · pinch with two fingers or use the slider',
    this.zoomInTooltip = 'Zoom in',
    this.zoomOutTooltip = 'Zoom out',
  });

  @override
  State<ZoomableLteChart> createState() => _ZoomableLteChartState();
}

class _ZoomableLteChartState extends State<ZoomableLteChart> {
  final _scroll = ScrollController();
  double _zoom = 1;
  double _gestureZoom = 1;
  double _gestureOffset = 0;
  double _gestureFocalX = 0;
  int _lastPointCount = 0;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom.clamp(1, 20);
    _lastPointCount = _pointCount;
  }

  int get _pointCount => widget.datasets.fold<int>(
        0,
        (largest, dataset) => math.max(largest, dataset.points.length),
      );

  @override
  void didUpdateWidget(covariant ZoomableLteChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = _pointCount;
    if (widget.autoFollow && count > _lastPointCount) _followLatest();
    _lastPointCount = count;
  }

  void _followLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _setZoom(double value, {bool follow = false}) {
    final next = value.clamp(1, 20).toDouble();
    if ((next - _zoom).abs() < 0.01) return;
    setState(() => _zoom = next);
    if (follow || widget.autoFollow) _followLatest();
  }

  void _scaleStart(ScaleStartDetails details) {
    _gestureZoom = _zoom;
    _gestureOffset = _scroll.hasClients ? _scroll.offset : 0;
    _gestureFocalX = details.localFocalPoint.dx;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      final next = (_gestureZoom * details.horizontalScale).clamp(1, 20);
      if ((next - _zoom).abs() < 0.01) return;
      final oldZoom = _zoom;
      setState(() => _zoom = next.toDouble());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final ratio = _zoom / oldZoom;
        final target =
            ((_scroll.offset + _gestureFocalX) * ratio) - _gestureFocalX;
        _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      });
      return;
    }
    if (_zoom <= 1 || !_scroll.hasClients) return;
    final target =
        _gestureOffset - (details.localFocalPoint.dx - _gestureFocalX);
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pointCount == 0) return const SizedBox.shrink();
    final metrics = <_Metric>[
      const _Metric('RSRP', 'dBm', Color(0xFF3FB950), _MetricKind.rsrp),
      const _Metric('RSRQ', 'dB', Color(0xFF58A6FF), _MetricKind.rsrq),
      const _Metric('SINR', 'dB', Color(0xFFD29922), _MetricKind.sinr),
      if (widget.showRssiAndCqi)
        const _Metric('RSSI', 'dBm', Color(0xFFA371F7), _MetricKind.rssi),
      if (widget.showRssiAndCqi)
        const _Metric('CQI', '', Color(0xFFDB61A2), _MetricKind.cqi),
    ].where(_hasMetric).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: widget.zoomOutTooltip,
              onPressed: _zoom <= 1 ? null : () => _setZoom(_zoom - 0.5),
              icon: const Icon(Icons.remove, size: 19),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${_zoom.toStringAsFixed(_zoom % 1 == 0 ? 0 : 1)}×',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Slider(
                value: _zoom,
                min: 1,
                max: 20,
                divisions: 38,
                onChanged: _setZoom,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: widget.zoomInTooltip,
              onPressed: _zoom >= 20 ? null : () => _setZoom(_zoom + 0.5),
              icon: const Icon(Icons.add, size: 19),
            ),
          ],
        ),
        if (widget.datasets.length > 1)
          Wrap(
            spacing: 14,
            runSpacing: 5,
            children: [
              for (final dataset in widget.datasets)
                _Legend(name: dataset.name, color: dataset.color),
            ],
          ),
        Text(
          widget.zoomHint,
          style: const TextStyle(fontSize: 10, color: Color(0xFF7D8590)),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(1.0, constraints.maxWidth * _zoom);
            return ClipRect(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _scaleStart,
                onScaleUpdate: _scaleUpdate,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < metrics.length;
                            index++) ...[
                          _MetricPlot(
                            metric: metrics[index],
                            datasets: widget.datasets,
                          ),
                          if (index != metrics.length - 1)
                            const SizedBox(height: 9),
                        ],
                        const SizedBox(height: 3),
                        _TimeAxis(datasets: widget.datasets),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  bool _hasMetric(_Metric metric) => widget.datasets.any(
        (dataset) => dataset.points.any((point) => metric.value(point) != null),
      );
}

class _TimeAxis extends StatelessWidget {
  final List<LteChartDataset> datasets;

  const _TimeAxis({required this.datasets});

  @override
  Widget build(BuildContext context) {
    final source = datasets.reduce(
      (a, b) => a.points.length >= b.points.length ? a : b,
    );
    if (source.points.isEmpty) return const SizedBox.shrink();
    final count = source.points.length;
    final labels = datasets.length > 1
        ? ['#1', '#${math.max(1, (count / 2).round())}', '#$count']
        : [
            '0:00',
            _elapsed(source.points.first.sampledAt,
                source.points[(count - 1) ~/ 2].sampledAt),
            _elapsed(
                source.points.first.sampledAt, source.points.last.sampledAt),
          ];
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final label in labels)
            Text(label,
                style: const TextStyle(fontSize: 9, color: Color(0xFF7D8590))),
        ],
      ),
    );
  }

  String _elapsed(DateTime start, DateTime end) {
    final total = math.max(0, end.difference(start).inSeconds);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${two(minutes)}:${two(seconds)}'
        : '$minutes:${two(seconds)}';
  }
}

enum _MetricKind { rsrp, rsrq, sinr, rssi, cqi }

class _Metric {
  final String label;
  final String unit;
  final Color color;
  final _MetricKind kind;

  const _Metric(this.label, this.unit, this.color, this.kind);

  double? value(LteChartPoint point) => switch (kind) {
        _MetricKind.rsrp => point.rsrp,
        _MetricKind.rsrq => point.rsrq,
        _MetricKind.sinr => point.sinr,
        _MetricKind.rssi => point.rssi,
        _MetricKind.cqi => point.cqi?.toDouble(),
      };
}

class _Legend extends StatelessWidget {
  final String name;
  final Color color;
  const _Legend({required this.name, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 5),
          Text(name, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _MetricPlot extends StatelessWidget {
  final _Metric metric;
  final List<LteChartDataset> datasets;
  const _MetricPlot({required this.metric, required this.datasets});

  @override
  Widget build(BuildContext context) {
    final allValues = <double>[];
    final bars = <LineChartBarData>[];
    final multi = datasets.length > 1;
    for (final dataset in datasets) {
      final spots = <FlSpot>[];
      for (var index = 0; index < dataset.points.length; index++) {
        final value = metric.value(dataset.points[index]);
        if (value == null) continue;
        allValues.add(value);
        spots.add(FlSpot(index.toDouble(), value));
      }
      if (spots.isEmpty) continue;
      final color = multi ? dataset.color : metric.color;
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: spots.length < 80,
        curveSmoothness: 0.18,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: !multi,
          color: color.withValues(alpha: 0.08),
        ),
      ));
    }
    if (allValues.isEmpty) return const SizedBox.shrink();
    final low = allValues.reduce(math.min);
    final high = allValues.reduce(math.max);
    final padding = math.max(1.5, (high - low) * 0.18);
    final maxPoints = datasets.fold<int>(
      0,
      (largest, dataset) => math.max(largest, dataset.points.length),
    );

    return SizedBox(
      height: 82,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: TextStyle(
                    color: metric.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${_number(high)}\n${_number(low)}',
                  style: const TextStyle(
                    fontSize: 9,
                    height: 2.7,
                    color: Color(0xFF7D8590),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LineChart(LineChartData(
              minX: 0,
              maxX: math.max(1, maxPoints - 1).toDouble(),
              minY: low - padding,
              maxY: high + padding,
              clipData: const FlClipData.all(),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: const Color(0xFF232B36)),
              ),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: bars,
            )),
          ),
        ],
      ),
    );
  }

  String _number(double value) => value.abs() >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}
