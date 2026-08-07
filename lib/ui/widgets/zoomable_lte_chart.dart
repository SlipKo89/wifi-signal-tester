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
  final double? quality;
  final double qualityConfidence;
  final bool radioChanged;

  const LteChartPoint({
    required this.sampledAt,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
    this.cqi,
    this.quality,
    this.qualityConfidence = 0,
    this.radioChanged = false,
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
  final bool showQuality;
  final bool technicalInitiallyExpanded;
  final bool ru;
  final String zoomHint;
  final String zoomInTooltip;
  final String zoomOutTooltip;
  final VoidCallback? onQualityHelp;

  const ZoomableLteChart({
    super.key,
    required this.datasets,
    this.autoFollow = false,
    this.initialZoom = 1,
    this.showRssiAndCqi = false,
    this.showQuality = false,
    this.technicalInitiallyExpanded = true,
    this.ru = false,
    this.zoomHint =
        '1× — complete session · pinch with two fingers or use the slider',
    this.zoomInTooltip = 'Zoom in',
    this.zoomOutTooltip = 'Zoom out',
    this.onQualityHelp,
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
  late bool _technicalExpanded;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom.clamp(1, 20);
    _technicalExpanded = widget.technicalInitiallyExpanded;
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
    final hasQuality = widget.datasets.any(
      (dataset) => dataset.points.any((point) => point.quality != null),
    );
    final metrics = <_Metric>[
      if (widget.showQuality && hasQuality)
        _Metric(
          widget.ru ? 'КАЧЕСТВО' : 'QUALITY',
          '',
          const Color(0xFF58A6FF),
          _MetricKind.quality,
        ),
      if (!widget.showQuality || _technicalExpanded || !hasQuality) ...[
        const _Metric('RSRP', 'dBm', Color(0xFF3FB950), _MetricKind.rsrp),
        const _Metric('RSRQ', 'dB', Color(0xFF58A6FF), _MetricKind.rsrq),
        const _Metric('SINR', 'dB', Color(0xFFD29922), _MetricKind.sinr),
        if (widget.showRssiAndCqi)
          const _Metric('RSSI', 'dBm', Color(0xFFA371F7), _MetricKind.rssi),
        if (widget.showRssiAndCqi)
          const _Metric('CQI', '', Color(0xFFDB61A2), _MetricKind.cqi),
      ],
    ].where(_hasMetric).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showQuality &&
            hasQuality &&
            widget.datasets.length == 1) ...[
          _QualitySummary(
            dataset: widget.datasets.first,
            ru: widget.ru,
            onHelp: widget.onQualityHelp,
          ),
          const SizedBox(height: 5),
        ],
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
        if (widget.showQuality && hasQuality)
          Text(
            widget.ru
                ? 'Индекс оценивает радиоканал, а не скорость Интернета. Выше — лучше.'
                : 'This score grades the radio link, not Internet speed. Higher is better.',
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
        if (widget.showQuality && hasQuality)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(
                () => _technicalExpanded = !_technicalExpanded,
              ),
              icon: Icon(
                _technicalExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(widget.ru
                  ? '${_technicalExpanded ? 'Скрыть' : 'Показать'} технические графики'
                  : '${_technicalExpanded ? 'Hide' : 'Show'} technical charts'),
            ),
          ),
      ],
    );
  }

  bool _hasMetric(_Metric metric) => widget.datasets.any(
        (dataset) => dataset.points.any((point) => metric.value(point) != null),
      );
}

class _QualitySummary extends StatelessWidget {
  final LteChartDataset dataset;
  final bool ru;
  final VoidCallback? onHelp;

  const _QualitySummary({
    required this.dataset,
    required this.ru,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    final scored = dataset.points
        .where((point) => point.quality != null)
        .toList(growable: false);
    if (scored.isEmpty) return const SizedBox.shrink();
    final currentPoint = scored.last;
    final current = currentPoint.quality!;
    final stable = scored
        .where((point) => point.qualityConfidence >= 0.5)
        .toList(growable: false);
    final bestSource = stable.isEmpty ? scored : stable;
    final best = bestSource.map((point) => point.quality!).reduce(math.max);
    final loss = best - current;
    final color = _scoreColor(current);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${current.round()}',
          style: TextStyle(
            color: color,
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Text('/100',
            style: TextStyle(fontSize: 14, color: Color(0xFF7D8590))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _scoreLabel(current, ru),
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              Text(
                currentPoint.qualityConfidence < 0.5
                    ? (scored.length < 3
                        ? (ru
                            ? 'Набираем данные для устойчивой оценки'
                            : 'Collecting data for a stable score')
                        : (ru
                            ? 'Низкая достоверность: сигнал скачет или не хватает метрик'
                            : 'Low confidence: unstable or incomplete metrics'))
                    : loss < 1
                        ? (ru
                            ? 'Сейчас — лучший результат'
                            : 'Current result is the best')
                        : (ru
                            ? 'На ${loss.round()} п. ниже лучшего · лучшее ${best.round()}'
                            : '${loss.round()} pts below best · best ${best.round()}'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
              ),
            ],
          ),
        ),
        if (onHelp != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: ru ? 'Как считается оценка' : 'How this score works',
            onPressed: onHelp,
            icon: const Icon(Icons.info_outline, size: 18),
          ),
      ],
    );
  }
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

enum _MetricKind { quality, rsrp, rsrq, sinr, rssi, cqi }

class _Metric {
  final String label;
  final String unit;
  final Color color;
  final _MetricKind kind;

  const _Metric(this.label, this.unit, this.color, this.kind);

  double? value(LteChartPoint point) => switch (kind) {
        _MetricKind.quality => point.quality,
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
    final barDatasets = <LteChartDataset>[];
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
      barDatasets.add(dataset);
      final color = multi ? dataset.color : metric.color;
      final stableSpots = spots
          .where(
              (spot) => dataset.points[spot.x.round()].qualityConfidence >= 0.5)
          .toList(growable: false);
      final best = (stableSpots.isEmpty ? spots : stableSpots)
          .map((spot) => spot.y)
          .reduce(math.max);
      final latestX = spots.last.x;
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: spots.length < 80,
        curveSmoothness: 0.18,
        color: color,
        barWidth: 2,
        dotData: metric.kind == _MetricKind.quality
            ? FlDotData(
                show: true,
                checkToShowDot: (spot, _) =>
                    spot.x == latestX || (spot.y - best).abs() < 0.01,
              )
            : const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: !multi,
          color: color.withValues(alpha: 0.08),
        ),
      ));
    }
    if (allValues.isEmpty) return const SizedBox.shrink();
    final low = allValues.reduce(math.min);
    final high = allValues.reduce(math.max);
    final quality = metric.kind == _MetricKind.quality;
    final padding = quality ? 0.0 : math.max(1.5, (high - low) * 0.18);
    final maxPoints = datasets.fold<int>(
      0,
      (largest, dataset) => math.max(largest, dataset.points.length),
    );

    return SizedBox(
      height: quality ? 118 : 82,
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
                  quality ? '100\n  0' : '${_number(high)}\n${_number(low)}',
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
              minY: quality ? 0 : low - padding,
              maxY: quality ? 100 : high + padding,
              clipData: const FlClipData.all(),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: const Color(0xFF232B36)),
              ),
              titlesData: const FlTitlesData(show: false),
              rangeAnnotations: quality
                  ? RangeAnnotations(
                      horizontalRangeAnnotations: [
                        HorizontalRangeAnnotation(
                          y1: 0,
                          y2: 40,
                          color:
                              const Color(0xFFF85149).withValues(alpha: 0.055),
                        ),
                        HorizontalRangeAnnotation(
                          y1: 40,
                          y2: 60,
                          color:
                              const Color(0xFFD29922).withValues(alpha: 0.055),
                        ),
                        HorizontalRangeAnnotation(
                          y1: 60,
                          y2: 80,
                          color:
                              const Color(0xFF3FB950).withValues(alpha: 0.045),
                        ),
                        HorizontalRangeAnnotation(
                          y1: 80,
                          y2: 100,
                          color:
                              const Color(0xFF3FB950).withValues(alpha: 0.085),
                        ),
                      ],
                      verticalRangeAnnotations: [
                        if (!multi)
                          for (var index = 0;
                              index < datasets.first.points.length;
                              index++)
                            if (datasets.first.points[index].radioChanged)
                              VerticalRangeAnnotation(
                                x1: index - 0.08,
                                x2: index + 0.08,
                                color: const Color(0xFF58A6FF)
                                    .withValues(alpha: 0.55),
                              ),
                      ],
                    )
                  : const RangeAnnotations(),
              extraLinesData: quality
                  ? ExtraLinesData(horizontalLines: [
                      for (final threshold in const [40.0, 60.0, 80.0])
                        HorizontalLine(
                          y: threshold,
                          color:
                              const Color(0xFF7D8590).withValues(alpha: 0.25),
                          strokeWidth: 0.7,
                        ),
                    ])
                  : const ExtraLinesData(),
              lineTouchData: quality
                  ? LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((spot) {
                          final dataset = barDatasets[spot.barIndex];
                          final index = spot.x.round().clamp(
                                0,
                                dataset.points.length - 1,
                              );
                          final point = dataset.points[index];
                          final facts = <String>[
                            '${spot.y.round()}/100',
                            if (point.rsrp != null)
                              'RSRP ${_number(point.rsrp!)}',
                            if (point.rsrq != null)
                              'RSRQ ${_number(point.rsrq!)}',
                            if (point.sinr != null)
                              'SINR ${_number(point.sinr!)}',
                          ];
                          return LineTooltipItem(
                            facts.join('\n'),
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  : const LineTouchData(enabled: false),
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

Color _scoreColor(double score) {
  if (score >= 80) return const Color(0xFF3FB950);
  if (score >= 60) return const Color(0xFF56D364);
  if (score >= 40) return const Color(0xFFD29922);
  return const Color(0xFFF85149);
}

String _scoreLabel(double score, bool ru) {
  if (score >= 80) return ru ? 'Отлично' : 'Excellent';
  if (score >= 60) return ru ? 'Хорошо' : 'Good';
  if (score >= 40) return ru ? 'Требует внимания' : 'Needs attention';
  return ru ? 'Плохо' : 'Poor';
}
