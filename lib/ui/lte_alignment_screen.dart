import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../lte/lte_alignment.dart';
import '../lte/lte_alignment_controller.dart';
import '../lte/lte_controller.dart';
import '../lte/lte_signal.dart';
import '../settings/settings_controller.dart';

const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);
const _red = Color(0xFFF85149);
const _blue = Color(0xFF58A6FF);
const _muted = Color(0xFF7D8590);

class LteAlignmentScreen extends StatefulWidget {
  final LteController monitor;
  final LteAlignmentSession session;

  const LteAlignmentScreen({
    super.key,
    required this.monitor,
    required this.session,
  });

  @override
  State<LteAlignmentScreen> createState() => _LteAlignmentScreenState();
}

class _LteAlignmentScreenState extends State<LteAlignmentScreen> {
  late final LteAlignmentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LteAlignmentController(
      monitor: widget.monitor,
      session: widget.session,
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _restart(L10n l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.t('Start a new alignment?', 'Начать юстировку заново?')),
        content: Text(l.t(
          'The current checkpoints will be cleared. Keep the dish at the new starting position.',
          'Текущие контрольные точки будут очищены. Оставь тарелку в новой исходной позиции.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.t('Cancel', 'Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.t('Start over', 'Начать заново')),
          ),
        ],
      ),
    );
    if (confirmed == true) _controller.startBaseline();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('LTE alignment assistant', 'Мастер юстировки LTE')),
            Text(
              '${widget.monitor.interfaceName ?? 'LTE'} · ${widget.monitor.transportKind ?? 'RouterOS'}',
              style: const TextStyle(
                fontSize: 10,
                color: _muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          if (_controller.hasSession)
            IconButton(
              tooltip: l.t('Start over', 'Начать заново'),
              onPressed: switch (_controller.phase) {
                LteAlignmentCapturePhase.settling ||
                LteAlignmentCapturePhase.collecting =>
                  null,
                _ => () => _restart(l),
              },
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _IntroCard(l: l),
            const SizedBox(height: 12),
            _LiveHistoryCard(controller: _controller, l: l),
            const SizedBox(height: 12),
            _ControlCard(controller: _controller, l: l),
            if (_controller.best != null) ...[
              const SizedBox(height: 12),
              _BestPointCard(controller: _controller, l: l),
            ],
            if (_controller.session.points.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CheckpointHistoryCard(controller: _controller, l: l),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final L10n l;
  const _IntroCard({required this.l});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _blue.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _blue.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.explore_outlined, color: _blue, size: 22),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                l.t(
                  'Choose one repeatable physical step. The assistant compares stable checkpoints and guides relative moves; coordinates are steps, not degrees.',
                  'Выбери один повторяемый физический шаг. Мастер сравнивает устойчивые точки и ведёт относительными перемещениями; координаты — шаги, а не градусы.',
                ),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _LiveHistoryCard extends StatelessWidget {
  final LteAlignmentController controller;
  final L10n l;
  const _LiveHistoryCard({required this.controller, required this.l});

  @override
  Widget build(BuildContext context) {
    final history = controller.liveHistory.length <= 30
        ? controller.liveHistory
        : controller.liveHistory.sublist(controller.liveHistory.length - 30);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
                Icons.show_chart, l.t('Live radio history', 'История эфира')),
            const SizedBox(height: 12),
            _MetricChart(
              label: 'RSRP',
              unit: 'dBm',
              color: _green,
              samples: history,
              value: (sample) => sample.rsrp,
            ),
            const SizedBox(height: 10),
            _MetricChart(
              label: 'RSRQ',
              unit: 'dB',
              color: _blue,
              samples: history,
              value: (sample) => sample.rsrq,
            ),
            const SizedBox(height: 10),
            _MetricChart(
              label: 'SINR',
              unit: 'dB',
              color: _amber,
              samples: history,
              value: (sample) => sample.sinr,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChart extends StatelessWidget {
  final String label;
  final String unit;
  final Color color;
  final List<LteSignal> samples;
  final double? Function(LteSignal sample) value;

  const _MetricChart({
    required this.label,
    required this.unit,
    required this.color,
    required this.samples,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final values = samples.map(value).whereType<double>().toList();
    final latest = values.isEmpty ? null : values.last;
    if (values.length < 2) {
      return SizedBox(
        height: 50,
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
            Text(latest == null ? '—' : '${_n(latest)} $unit'),
          ],
        ),
      );
    }
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final padding = math.max(1.5, (high - low) * 0.18);
    final spots = [
      for (var index = 0; index < values.length; index++)
        FlSpot(index.toDouble(), values[index]),
    ];
    return Column(
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_n(latest!)} $unit',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('${_n(low)}…${_n(high)}',
                style: const TextStyle(fontSize: 10, color: _muted)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 58,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (values.length - 1).toDouble(),
              minY: low - padding,
              maxY: high + padding,
              clipData: const FlClipData.all(),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.22,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlCard extends StatelessWidget {
  final LteAlignmentController controller;
  final L10n l;
  const _ControlCard({required this.controller, required this.l});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(Icons.assistant_navigation,
                  l.t('Alignment guide', 'Помощник движения')),
              const SizedBox(height: 14),
              switch (controller.phase) {
                LteAlignmentCapturePhase.idle => _idle(),
                LteAlignmentCapturePhase.settling => _settling(),
                LteAlignmentCapturePhase.collecting => _collecting(),
                LteAlignmentCapturePhase.error => _error(),
                LteAlignmentCapturePhase.ready => _ready(),
              },
            ],
          ),
        ),
      );

  Widget _idle() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.t(
              'Do not move the dish during the baseline. The app waits 4 seconds, then takes 6 fresh samples.',
              'Не двигай тарелку во время базового замера. Приложение ждёт 4 секунды, затем собирает 6 свежих значений.',
            ),
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: controller.startBaseline,
            icon: const Icon(Icons.flag_outlined),
            label:
                Text(l.t('Capture baseline', 'Зафиксировать исходную точку')),
          ),
        ],
      );

  Widget _settling() => _progress(
        icon: Icons.hourglass_top,
        title: l.t('Letting the radio settle', 'Ждём стабилизации эфира'),
        subtitle: l.t(
          '${controller.settleRemaining} sec — keep the dish still',
          '${controller.settleRemaining} сек — не двигай тарелку',
        ),
        progress: (LteAlignmentController.settlingSeconds -
                controller.settleRemaining) /
            LteAlignmentController.settlingSeconds,
      );

  Widget _collecting() => _progress(
        icon: Icons.sensors,
        title:
            l.t('Capturing a stable checkpoint', 'Фиксируем устойчивую точку'),
        subtitle: l.t(
          '${controller.captureProgress}/${LteAlignmentController.requiredSamples} samples',
          '${controller.captureProgress}/${LteAlignmentController.requiredSamples} замеров',
        ),
        progress:
            controller.captureProgress / LteAlignmentController.requiredSamples,
      );

  Widget _progress({
    required IconData icon,
    required String title,
    required String subtitle,
    required double progress,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.cancelCapture,
              child: Text(l.t('Cancel', 'Отменить')),
            ),
          ),
        ],
      );

  Widget _error() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            switch (controller.error) {
              'not-registered' => l.t(
                  'The modem lost LTE registration during this checkpoint. Keep the dish still, wait for registration and retry.',
                  'Во время замера модем потерял регистрацию в LTE. Не двигай тарелку, дождись регистрации и повтори точку.',
                ),
              'radio-metrics-unavailable' => l.t(
                  'The modem returned fresh samples without RSRP, RSRQ or SINR. Wait for radio metrics and retry.',
                  'Модем вернул свежие замеры без RSRP, RSRQ и SINR. Дождись появления радиометрик и повтори точку.',
                ),
              _ => l.t(
                  'Not enough fresh LTE samples arrived. Check the connection and try this point again.',
                  'Не удалось получить достаточно свежих LTE-замеров. Проверь подключение и повтори эту точку.',
                ),
            },
            style: const TextStyle(color: _red, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: controller.retryCapture,
            icon: const Icon(Icons.refresh),
            label: Text(l.t('Retry checkpoint', 'Повторить точку')),
          ),
        ],
      );

  Widget _ready() {
    final target = controller.selectedTarget;
    if (target == null) return _localOptimum();
    final movement = controller.session.movementTo(target);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.latest != null) ...[
          _OutcomeBanner(point: controller.latest!, l: l),
          const SizedBox(height: 14),
        ],
        Text(l.t('NEXT PROBE', 'СЛЕДУЮЩАЯ ПРОБА'),
            style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: _muted,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          _movementText(movement.dx, movement.dy, l),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          l.t(
            'Use the same small physical step, then press the measurement button.',
            'Сделай тот же небольшой физический шаг и нажми кнопку замера.',
          ),
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _direction(Icons.arrow_left, LteAlignmentDirection.left,
                l.t('Left', 'Влево')),
            _direction(Icons.arrow_right, LteAlignmentDirection.right,
                l.t('Right', 'Вправо')),
            _direction(Icons.arrow_upward, LteAlignmentDirection.up,
                l.t('Up', 'Вверх')),
            _direction(Icons.arrow_downward, LteAlignmentDirection.down,
                l.t('Down', 'Вниз')),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: controller.confirmMovedAndMeasure,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(l.t('I moved — measure', 'Переместил — измерить')),
        ),
      ],
    );
  }

  Widget _direction(
    IconData icon,
    LteAlignmentDirection direction,
    String tooltip,
  ) =>
      IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: () => controller.selectDirection(direction),
        icon: Icon(icon),
      );

  Widget _localOptimum() {
    final move = controller.session.movementToBest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.latest != null) ...[
          _OutcomeBanner(point: controller.latest!, l: l),
          const SizedBox(height: 14),
        ],
        const Icon(Icons.my_location, color: _green, size: 34),
        const SizedBox(height: 8),
        Text(
          l.t('Local optimum found', 'Локальный оптимум найден'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          move.dx == 0 && move.dy == 0
              ? l.t(
                  'You are at the best checkpoint. Reduce the physical step and run a fine pass.',
                  'Ты находишься в лучшей точке. Уменьши физический шаг и запусти точный проход.')
              : l.t(
                  'Return to the best checkpoint: ${_movementText(move.dx, move.dy, l)}. Then halve the physical step.',
                  'Вернись в лучшую точку: ${_movementText(move.dx, move.dy, l)}. Затем уменьши физический шаг вдвое.'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: controller.startFineRound,
          icon: const Icon(Icons.center_focus_strong),
          label: Text(l.t(
            'At the best point — start fine pass',
            'Я в лучшей точке — точный проход',
          )),
        ),
      ],
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  final LteAlignmentPoint point;
  final L10n l;
  const _OutcomeBanner({required this.point, required this.l});

  @override
  Widget build(BuildContext context) {
    final color = switch (point.outcome) {
      LteAlignmentOutcome.better => _green,
      LteAlignmentOutcome.worse => _red,
      LteAlignmentOutcome.similar => _amber,
      LteAlignmentOutcome.radioChanged => _blue,
      LteAlignmentOutcome.first => _blue,
    };
    final text = switch (point.outcome) {
      LteAlignmentOutcome.better => l.t(
          'Better than the previous best (${_signed(point.deltaFromPreviousBest)} points)',
          'Лучше предыдущей точки (${_signed(point.deltaFromPreviousBest)} балла)'),
      LteAlignmentOutcome.worse => l.t(
          'Worse than the best (${_signed(point.deltaFromPreviousBest)} points)',
          'Хуже лучшей (${_signed(point.deltaFromPreviousBest)} балла)'),
      LteAlignmentOutcome.similar => l.t(
          'Difference is inside normal radio fluctuation',
          'Разница укладывается в обычные колебания эфира'),
      LteAlignmentOutcome.radioChanged => l.t(
          'Band or serving cell changed — the improvement may be caused by the handoff',
          'Сменился диапазон или сектор — улучшение могло произойти из-за переключения'),
      LteAlignmentOutcome.first =>
        l.t('Baseline captured', 'Исходная точка зафиксирована'),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _BestPointCard extends StatelessWidget {
  final LteAlignmentController controller;
  final L10n l;
  const _BestPointCard({required this.controller, required this.l});

  @override
  Widget build(BuildContext context) {
    final best = controller.best!;
    final move = controller.session.movementToBest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(Icons.emoji_events_outlined,
                l.t('Best checkpoint', 'Лучшая точка')),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(best.score.round().toString(),
                    style: const TextStyle(
                        color: _green,
                        fontSize: 38,
                        height: 0.9,
                        fontWeight: FontWeight.w900)),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 2),
                  child: Text('/ 100', style: TextStyle(color: _muted)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'X ${best.x >= 0 ? '+' : ''}${best.x} · Y ${best.y >= 0 ? '+' : ''}${best.y}',
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 7,
              children: [
                _fact('RSRP', best.rsrp, 'dBm'),
                _fact('RSRQ', best.rsrq, 'dB'),
                _fact('SINR', best.sinr, 'dB'),
                if (best.cqi != null) _fact('CQI', best.cqi?.toDouble(), ''),
                if (best.band != null)
                  Text(best.band!,
                      style: const TextStyle(fontSize: 12, color: _blue)),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              l.t(
                'Confidence ${(best.confidence * 100).round()}%. Score prioritises SINR/RSRQ once RSRP is usable and penalises unstable peaks.',
                'Достоверность ${(best.confidence * 100).round()}%. После достижения рабочего RSRP рейтинг отдаёт приоритет SINR/RSRQ и штрафует нестабильные пики.',
              ),
              style: const TextStyle(fontSize: 11, color: _muted, height: 1.35),
            ),
            if (move.dx != 0 || move.dy != 0) ...[
              const SizedBox(height: 9),
              Text(
                '${l.t('Return to best', 'Вернуться к лучшей')}: ${_movementText(move.dx, move.dy, l)}',
                style:
                    const TextStyle(color: _green, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, double? value, String unit) => Text(
        '$label ${_n(value)}${unit.isEmpty ? '' : ' $unit'}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      );
}

class _CheckpointHistoryCard extends StatelessWidget {
  final LteAlignmentController controller;
  final L10n l;
  const _CheckpointHistoryCard({required this.controller, required this.l});

  @override
  Widget build(BuildContext context) {
    final points = controller.session.points;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(Icons.route_outlined,
                '${l.t('Checkpoints', 'Контрольные точки')} · ${points.length}'),
            if (points.length >= 2) ...[
              const SizedBox(height: 12),
              SizedBox(height: 100, child: _ScoreChart(points: points)),
            ],
            const SizedBox(height: 8),
            for (final point in points.reversed.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor:
                          _outcomeColor(point.outcome).withValues(alpha: 0.14),
                      child: Text('${point.id}',
                          style: TextStyle(
                              color: _outcomeColor(point.outcome),
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l.t('round', 'проход')} ${point.round + 1} · X ${point.x} · Y ${point.y}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'RSRP ${_n(point.rsrp)} · RSRQ ${_n(point.rsrq)} · SINR ${_n(point.sinr)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 10.5, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    Text(point.score.round().toString(),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreChart extends StatelessWidget {
  final List<LteAlignmentPoint> points;
  const _ScoreChart({required this.points});

  @override
  Widget build(BuildContext context) => LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: math.max(0, points.map((p) => p.score).reduce(math.min) - 8),
          maxY: math.min(100, points.map((p) => p.score).reduce(math.max) + 8),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF252C35), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var index = 0; index < points.length; index++)
                  FlSpot(index.toDouble(), points[index].score),
              ],
              color: _green,
              barWidth: 2,
              isCurved: false,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: _green.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      );
}

Widget _title(IconData icon, String text) => Row(
      children: [
        Icon(icon, size: 19, color: _amber),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ],
    );

String _movementText(int dx, int dy, L10n l) {
  if (dx == 0 && dy == 0) {
    return l.t('stay at the current point', 'оставайся в текущей точке');
  }
  final parts = <String>[];
  if (dx != 0) {
    parts.add(l.t(
      '${dx.abs()} ${_stepsEn(dx.abs())} ${dx > 0 ? 'right' : 'left'}',
      '${dx.abs()} ${_stepsRu(dx.abs())} ${dx > 0 ? 'вправо' : 'влево'}',
    ));
  }
  if (dy != 0) {
    parts.add(l.t(
      '${dy.abs()} ${_stepsEn(dy.abs())} ${dy > 0 ? 'up' : 'down'}',
      '${dy.abs()} ${_stepsRu(dy.abs())} ${dy > 0 ? 'вверх' : 'вниз'}',
    ));
  }
  return parts.join(l.t(', then ', ', затем '));
}

String _stepsEn(int value) => value == 1 ? 'step' : 'steps';
String _stepsRu(int value) {
  final last = value % 10;
  final lastTwo = value % 100;
  if (last == 1 && lastTwo != 11) return 'шаг';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return 'шага';
  return 'шагов';
}

String _n(num? value) {
  if (value == null) return '—';
  final rounded = value.toStringAsFixed(1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}

String _signed(double? value) {
  if (value == null) return '—';
  final text = _n(value);
  return value > 0 ? '+$text' : text;
}

Color _outcomeColor(LteAlignmentOutcome outcome) => switch (outcome) {
      LteAlignmentOutcome.better => _green,
      LteAlignmentOutcome.worse => _red,
      LteAlignmentOutcome.similar => _amber,
      LteAlignmentOutcome.radioChanged || LteAlignmentOutcome.first => _blue,
    };
