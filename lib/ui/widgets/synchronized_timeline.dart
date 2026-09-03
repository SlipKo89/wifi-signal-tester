import 'dart:math' as math;

import 'package:flutter/material.dart';

class SessionTimelinePoint {
  final int timestampMs;
  final double value;

  const SessionTimelinePoint(this.timestampMs, this.value);
}

class SessionTimelineSeries {
  final String label;
  final String source;
  final Color color;
  final List<SessionTimelinePoint> points;

  const SessionTimelineSeries({
    required this.label,
    required this.source,
    required this.color,
    required this.points,
  });
}

class SessionTimelineTrack {
  final String key;
  final String title;
  final String unit;
  final List<SessionTimelineSeries> series;

  const SessionTimelineTrack({
    required this.key,
    required this.title,
    required this.unit,
    required this.series,
  });

  SessionTimelineTrack withSeries(List<SessionTimelineSeries> value) =>
      SessionTimelineTrack(
        key: key,
        title: title,
        unit: unit,
        series: value,
      );
}

/// Compact stacked charts sharing one time range and one movable cursor.
/// Each metric keeps its own Y scale so dBm, milliseconds and percentages are
/// never mixed onto a misleading common axis.
class SynchronizedTimeline extends StatefulWidget {
  final int startedMs;
  final int endedMs;
  final List<SessionTimelineTrack> tracks;
  final bool ru;

  const SynchronizedTimeline({
    super.key,
    required this.startedMs,
    required this.endedMs,
    required this.tracks,
    required this.ru,
  });

  @override
  State<SynchronizedTimeline> createState() => _SynchronizedTimelineState();
}

class _SynchronizedTimelineState extends State<SynchronizedTimeline> {
  double? _cursorRatio;

  void _move(Offset local, double width) {
    const left = 44.0;
    const right = 10.0;
    final plotWidth = math.max(1.0, width - left - right);
    setState(() {
      _cursorRatio = ((local.dx - left) / plotWidth).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.tracks
        .where(
            (track) => track.series.any((series) => series.points.isNotEmpty))
        .toList(growable: false);
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          widget.ru
              ? 'Нет точек за период сессии.'
              : 'No points in this session.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF7D8590)),
        ),
      );
    }
    final height = visible.length * 112.0 + 24;
    return LayoutBuilder(builder: (context, constraints) {
      final width =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _move(details.localPosition, width),
        onHorizontalDragStart: (details) => _move(details.localPosition, width),
        onHorizontalDragUpdate: (details) =>
            _move(details.localPosition, width),
        child: CustomPaint(
          size: Size(width, height),
          painter: _TimelinePainter(
            tracks: visible,
            startedMs: widget.startedMs,
            endedMs: math.max(widget.endedMs, widget.startedMs + 1000),
            cursorRatio: _cursorRatio,
            ru: widget.ru,
            textColor: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    });
  }
}

class _TimelinePainter extends CustomPainter {
  static const _left = 44.0;
  static const _right = 10.0;
  static const _trackHeight = 112.0;
  final List<SessionTimelineTrack> tracks;
  final int startedMs;
  final int endedMs;
  final double? cursorRatio;
  final bool ru;
  final Color textColor;

  _TimelinePainter({
    required this.tracks,
    required this.startedMs,
    required this.endedMs,
    required this.cursorRatio,
    required this.ru,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = math.max(1.0, size.width - _left - _right);
    for (var index = 0; index < tracks.length; index++) {
      final track = tracks[index];
      final top = index * _trackHeight;
      final plot = Rect.fromLTRB(
        _left,
        top + 28,
        size.width - _right,
        top + 92,
      );
      _paintTrack(canvas, track, plot, plotWidth, top);
    }
    final cursor = cursorRatio;
    if (cursor != null) {
      final x = _left + cursor * plotWidth;
      canvas.drawLine(
        Offset(x, 22),
        Offset(x, tracks.length * _trackHeight - 20),
        Paint()
          ..color = const Color(0xFFDBE7F5).withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
      final timestamp = startedMs + ((endedMs - startedMs) * cursor).round();
      _text(canvas, _clock(timestamp), Offset(x - 24, size.height - 18),
          const Color(0xFF9DA7B3), 10);
    } else {
      _text(
        canvas,
        ru ? 'Нажми или проведи по графику' : 'Tap or drag across the chart',
        Offset(_left, size.height - 18),
        const Color(0xFF7D8590),
        10,
      );
    }
  }

  void _paintTrack(
    Canvas canvas,
    SessionTimelineTrack track,
    Rect plot,
    double plotWidth,
    double top,
  ) {
    final values = track.series
        .expand((series) => series.points)
        .map((point) => point.value)
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (values.isEmpty) return;
    var minimum = values.reduce(math.min);
    var maximum = values.reduce(math.max);
    if ((maximum - minimum).abs() < 0.001) {
      minimum -= 1;
      maximum += 1;
    } else {
      final padding = (maximum - minimum) * 0.08;
      minimum -= padding;
      maximum += padding;
    }
    _text(canvas, track.title, Offset(0, top + 3), textColor, 12,
        weight: FontWeight.w600, maxWidth: 145);
    var legendX = 150.0;
    for (final series in track.series) {
      if (series.points.isEmpty || legendX > plot.right - 28) continue;
      canvas.drawCircle(
          Offset(legendX, top + 11), 3, Paint()..color = series.color);
      final value = cursorRatio == null
          ? series.points.last.value
          : _nearest(series.points,
                  startedMs + ((endedMs - startedMs) * cursorRatio!).round())
              .value;
      final label =
          '${_number(value)}${track.unit.isEmpty ? '' : ' ${track.unit}'}';
      _text(canvas, label, Offset(legendX + 6, top + 3), series.color, 10,
          maxWidth: 84);
      legendX += 94;
    }
    final grid = Paint()
      ..color = const Color(0xFF7D8590).withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = plot.top + plot.height * i / 2;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    _text(canvas, _number(maximum), Offset(0, plot.top - 6),
        const Color(0xFF7D8590), 9,
        maxWidth: _left - 3);
    _text(canvas, _number(minimum), Offset(0, plot.bottom - 7),
        const Color(0xFF7D8590), 9,
        maxWidth: _left - 3);
    for (final series in track.series) {
      final points = series.points
          .where((point) => point.value.isFinite)
          .toList(growable: false);
      if (points.isEmpty) continue;
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final point = points[index];
        final ratio =
            ((point.timestampMs - startedMs) / math.max(1, endedMs - startedMs))
                .clamp(0.0, 1.0);
        final x = plot.left + ratio * plotWidth;
        final y = plot.bottom -
            ((point.value - minimum) / (maximum - minimum)) * plot.height;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = series.color
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  SessionTimelinePoint _nearest(List<SessionTimelinePoint> points, int target) {
    var best = points.first;
    var distance = (best.timestampMs - target).abs();
    for (final point in points.skip(1)) {
      final current = (point.timestampMs - target).abs();
      if (current < distance) {
        best = point;
        distance = current;
      }
    }
    return best;
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    Color color,
    double size, {
    FontWeight weight = FontWeight.normal,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(canvas, offset);
  }

  String _clock(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _number(double value) {
    if (value.abs() >= 1000) return value.toStringAsFixed(0);
    if ((value - value.round()).abs() < 0.05) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.cursorRatio != cursorRatio ||
      oldDelegate.tracks != tracks ||
      oldDelegate.startedMs != startedMs ||
      oldDelegate.endedMs != endedMs ||
      oldDelegate.textColor != textColor;
}
