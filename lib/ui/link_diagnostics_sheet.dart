import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../diagnostics/link_diagnostics.dart';
import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import 'theme.dart';

const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);
const _red = Color(0xFFF85149);
const _muted = Color(0xFF7D8590);

void showLinkDiagnostics(
  BuildContext context,
  LinkDiagnosticReport report,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LinkDiagnosticsSheet(report: report),
  );
}

/// Compact dashboard verdict. The detail sheet explains every observation and
/// deliberately calls causes "likely" because the app does not inspect or
/// modify traffic/configuration to prove them.
class LinkDiagnosticsCard extends StatelessWidget {
  final LinkDiagnosticReport report;
  final LinkDiagnosticPhase phase;
  final int? waitSeconds;
  final String? apName;
  final DateTime? completedAt;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const LinkDiagnosticsCard({
    super.key,
    required this.report,
    required this.phase,
    required this.canStart,
    required this.onStart,
    required this.onCancel,
    this.waitSeconds,
    this.apName,
    this.completedAt,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final primary = report.primary;
    final complete = phase == LinkDiagnosticPhase.complete && report.ready;
    final healthy = complete && report.healthy;
    final color = switch (phase) {
      LinkDiagnosticPhase.complete when healthy => _green,
      LinkDiagnosticPhase.complete
          when primary?.severity == LinkIssueSeverity.critical =>
        _red,
      LinkDiagnosticPhase.complete => _amber,
      _ => AppTheme.accent,
    };
    final title = switch (phase) {
      LinkDiagnosticPhase.idle =>
        l.t('Connection diagnosis', 'Диагностика соединения'),
      LinkDiagnosticPhase.waiting =>
        l.t('Waiting for the link to settle', 'Ждём стабилизации соединения'),
      LinkDiagnosticPhase.collecting =>
        l.t('Analyzing connection…', 'Анализируем соединение…'),
      LinkDiagnosticPhase.complete when healthy => l.t(
          'Signal matches link quality',
          'Качество связи соответствует сигналу'),
      LinkDiagnosticPhase.complete => _copy(primary!.kind, l).title,
    };
    final subtitle = switch (phase) {
      LinkDiagnosticPhase.idle => l.t(
          'Run a focused six-measurement check for the current access point.',
          'Запусти отдельную проверку из шести замеров для текущей точки.'),
      LinkDiagnosticPhase.waiting => l.t(
          'Automatic measurement starts in ${waitSeconds ?? 0} sec. You can run it now.',
          'Автозамер начнётся через ${waitSeconds ?? 0} сек. Можно запустить сейчас.'),
      LinkDiagnosticPhase.collecting => l.t(
          '${report.sampleCount}/${report.requiredSamples} measurements — keep the phone in the test position',
          '${report.sampleCount}/${report.requiredSamples} замеров — удерживай телефон в точке проверки'),
      LinkDiagnosticPhase.complete when healthy => l.t(
          'No stable signal/quality mismatch was found.',
          'Устойчивого расхождения между сигналом и качеством не найдено.'),
      LinkDiagnosticPhase.complete => _copy(primary!.kind, l).short,
    };
    final facts = _compactFacts(report.summary, l);
    final metadata = <String>[
      if (complete && facts.isNotEmpty) facts,
      if (apName != null && apName!.trim().isNotEmpty) apName!.trim(),
      if (complete && completedAt != null) _clock(completedAt!),
    ].join(' • ');
    final actionLabel = switch (phase) {
      LinkDiagnosticPhase.idle => l.t('Run diagnosis', 'Запустить диагностику'),
      LinkDiagnosticPhase.waiting => l.t('Run now', 'Запустить сейчас'),
      LinkDiagnosticPhase.collecting => l.t('Cancel', 'Отменить'),
      LinkDiagnosticPhase.complete => l.t('Repeat', 'Повторить'),
    };
    final actionIcon = phase == LinkDiagnosticPhase.collecting
        ? Icons.close
        : Icons.play_arrow_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: complete ? () => showLinkDiagnostics(context, report) : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (phase) {
                    LinkDiagnosticPhase.idle => Icons.query_stats,
                    LinkDiagnosticPhase.waiting => Icons.timer_outlined,
                    LinkDiagnosticPhase.collecting => Icons.query_stats,
                    LinkDiagnosticPhase.complete when healthy =>
                      Icons.check_circle_outline,
                    LinkDiagnosticPhase.complete =>
                      Icons.monitor_heart_outlined,
                  },
                  size: 21,
                  color: color,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: color)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(fontSize: 12, height: 1.35)),
                      if (metadata.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          metadata,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: _muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (complete) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 20, color: color),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: color,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: phase == LinkDiagnosticPhase.collecting
                  ? onCancel
                  : canStart
                      ? onStart
                      : null,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }

  String _clock(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class _LinkDiagnosticsSheet extends StatelessWidget {
  final LinkDiagnosticReport report;

  const _LinkDiagnosticsSheet({required this.report});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final primary = report.primary;
    final healthy = report.healthy;
    final color = healthy
        ? _green
        : primary?.severity == LinkIssueSeverity.critical
            ? _red
            : _amber;
    final title = healthy
        ? l.t('Signal matches link quality',
            'Качество связи соответствует сигналу')
        : _copy(primary!.kind, l).title;

    final advice = <String>[];
    for (final finding in report.findings) {
      for (final item in _copy(finding.kind, l).advice) {
        if (!advice.contains(item)) advice.add(item);
      }
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('Connection diagnosis', 'Диагностика соединения'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                l.t(
                    '${report.sampleCount} measurements over about '
                        '${report.windowSeconds} seconds',
                    '${report.sampleCount} замеров примерно за '
                        '${report.windowSeconds} секунд'),
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        healthy
                            ? Icons.check_circle_outline
                            : Icons.monitor_heart_outlined,
                        color: color,
                        size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                            healthy
                                ? l.t(
                                    'The measured quality is consistent with '
                                        'the current signal. This is not an '
                                        'internet speed test.',
                                    'Измеренное качество соответствует текущему '
                                        'сигналу. Это не тест скорости интернета.')
                                : _copy(primary!.kind, l).short,
                            style: const TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _section(l.t('OBSERVED', 'ЧТО ВИДИМ')),
              const SizedBox(height: 10),
              _Facts(summary: report.summary),
              if (report.findings.isNotEmpty) ...[
                const SizedBox(height: 22),
                _section(l.t('LIKELY MEANING', 'ЧТО ЭТО МОЖЕТ ЗНАЧИТЬ')),
                const SizedBox(height: 11),
                for (final finding in report.findings) _findingRow(finding, l),
                const SizedBox(height: 18),
                _section(l.t('WHAT TO CHECK', 'ЧТО ПРОВЕРИТЬ')),
                const SizedBox(height: 11),
                for (final item in advice) _adviceRow(item),
              ],
              const Divider(height: 28, color: Color(0xFF232B36)),
              Text(
                l.t(
                    'The app correlates read-only measurements and reports '
                        'likely causes. It does not change MikroTik or Android '
                        'settings and cannot prove interference without a '
                        'spectrum analysis.',
                    'Приложение сопоставляет измерения только для чтения и '
                        'показывает вероятные причины. Оно не меняет настройки '
                        'MikroTik или Android и не может доказать наличие помех '
                        'без анализа спектра.'),
                style:
                    const TextStyle(fontSize: 11, color: _muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _findingRow(LinkDiagnosticFinding finding, L10n l) {
    final copy = _copy(finding.kind, l);
    final color =
        finding.severity == LinkIssueSeverity.critical ? _red : _amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(copy.icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(copy.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(copy.explanation,
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adviceRow(String item) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.arrow_right, size: 18, color: AppTheme.accent),
            const SizedBox(width: 7),
            Expanded(
              child: Text(item,
                  style: const TextStyle(fontSize: 12.5, height: 1.4)),
            ),
          ],
        ),
      );
}

class _Facts extends StatelessWidget {
  final LinkDiagnosticSummary summary;

  const _Facts({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final facts = <(String, String)>[
      if (summary.phoneRssi != null)
        (l.t('Phone RSSI', 'RSSI телефона'), '${summary.phoneRssi} dBm'),
      if (summary.apSignal != null)
        (l.t('AP RSSI', 'RSSI точки'), '${summary.apSignal} dBm'),
      if (summary.phoneSnr != null)
        (
          summary.phoneSnrEstimated ? 'Phone SNR ~' : 'Phone SNR',
          '${summary.phoneSnr} dB'
        ),
      if (summary.apSnr != null)
        (summary.apSnrEstimated ? 'AP SNR ~' : 'AP SNR', '${summary.apSnr} dB'),
      if (summary.txCcq != null) ('TX CCQ', '${summary.txCcq}%'),
      if (summary.rxCcq != null) ('RX CCQ', '${summary.rxCcq}%'),
      if (summary.phoneRateMbps != null)
        (l.t('Phone rate', 'Линк телефона'), _rate(summary.phoneRateMbps!)),
      if (summary.apTxRateMbps != null)
        ('AP TX rate', _rate(summary.apTxRateMbps!)),
      if (summary.apRxRateMbps != null)
        ('AP RX rate', _rate(summary.apRxRateMbps!)),
      if (summary.pThroughputKbps != null)
        (
          'p-throughput',
          '${(summary.pThroughputKbps! / 1000).toStringAsFixed(1)} Mbps'
        ),
      if (summary.pingAvgMs != null)
        (l.t('Gateway ping', 'Пинг шлюза'), '${summary.pingAvgMs} ms'),
      if (summary.pingLossPct != null && summary.pingSamples > 0)
        (l.t('Ping loss', 'Потери ping'), '${summary.pingLossPct}%'),
      if (summary.cpuLoad != null) ('CPU', '${summary.cpuLoad}%'),
      if (summary.delta != null) ('Δ AP−phone', '${summary.delta} dB'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final fact in facts) _FactPill(fact.$1, fact.$2)],
    );
  }
}

class _FactPill extends StatelessWidget {
  final String label;
  final String value;

  const _FactPill(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9.5, color: _muted)),
            const SizedBox(height: 1),
            Text(value,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _IssueCopy {
  final IconData icon;
  final String title;
  final String short;
  final String explanation;
  final List<String> advice;

  const _IssueCopy({
    required this.icon,
    required this.title,
    required this.short,
    required this.explanation,
    required this.advice,
  });
}

_IssueCopy _copy(LinkIssueKind kind, L10n l) => switch (kind) {
      LinkIssueKind.routerLoad => _IssueCopy(
          icon: Icons.memory,
          title: l.t('Strong signal, router under load',
              'Сигнал сильный, роутер под нагрузкой'),
          short: l.t(
              'High CPU coincides with degraded gateway ping. The radio may '
                  'not be the bottleneck.',
              'Высокая загрузка CPU совпала с плохим ping до шлюза. Возможно, '
                  'узкое место не в радиоканале.'),
          explanation: l.t(
              'The signal is strong, while router CPU and latency/loss are high '
                  'at the same time. This correlation points beyond coverage.',
              'Сигнал сильный, а CPU роутера и задержка или потери одновременно '
                  'высоки. Это указывает на проблему не только с покрытием.'),
          advice: [
            l.t('Check CPU Profile and active services on the MikroTik.',
                'Проверь CPU Profile и активные сервисы на MikroTik.'),
            l.t('Repeat the measurement when the router load is lower.',
                'Повтори замер, когда нагрузка на роутер снизится.'),
          ],
        ),
      LinkIssueKind.packetLoss => _IssueCopy(
          icon: Icons.signal_wifi_statusbar_connected_no_internet_4,
          title: l.t('Strong signal with packet loss',
              'Сильный сигнал, но есть потери'),
          short: l.t(
              'Gateway ping is being lost despite good RSSI. Likely interference '
                  'or unstable radio delivery.',
              'Ping до шлюза теряется при хорошем RSSI. Вероятны помехи или '
                  'нестабильная передача по радио.'),
          explanation: l.t(
              'Packets fail to reach the local gateway, so this is not explained '
                  'by the internet provider. RSSI alone does not show retries.',
              'Пакеты не доходят уже до локального шлюза, поэтому это не '
                  'объясняется провайдером. RSSI не показывает ретрансмиты.'),
          advice: [
            l.t('Check neighbouring networks and channel utilisation.',
                'Проверь соседние сети и занятость канала.'),
            l.t('On 2.4 GHz, compare with a 20 MHz channel 1, 6 or 11.',
                'В 2,4 ГГц сравни с каналом 1, 6 или 11 шириной 20 МГц.'),
          ],
        ),
      LinkIssueKind.lowCcq => _IssueCopy(
          icon: Icons.replay,
          title: l.t('Strong signal, low CCQ', 'Сигнал сильный, CCQ низкий'),
          short: l.t(
              'The client is heard well, but frames are delivered inefficiently. '
                  'Interference or retransmissions are likely.',
              'Клиент слышен хорошо, но кадры передаются неэффективно. Вероятны '
                  'помехи или ретрансмиты.'),
          explanation: l.t(
              'Low CCQ with strong RSSI means much of the airtime is not turning '
                  'into useful data. Noise, collisions and compatibility issues '
                  'are common causes.',
              'Низкий CCQ при сильном RSSI означает, что эфирное время плохо '
                  'превращается в полезные данные. Частые причины — шум, коллизии '
                  'и совместимость.'),
          advice: [
            l.t('Compare another channel and a narrower channel width.',
                'Сравни другой канал и меньшую ширину канала.'),
            l.t(
                'Test another client to separate AP and device compatibility.',
                'Проверь другой клиент, чтобы отделить проблему точки от '
                    'совместимости устройства.'),
          ],
        ),
      LinkIssueKind.strongSignalLowSnr => _IssueCopy(
          icon: Icons.graphic_eq,
          title: l.t('Signal is strong, but noise is high',
              'Сигнал сильный, но шум высокий'),
          short: l.t(
              'Low SNR explains why a strong-looking RSSI can still produce an '
                  'unstable link.',
              'Низкий SNR объясняет, почему хороший RSSI всё равно даёт '
                  'нестабильную связь.'),
          explanation: l.t(
              'RSSI includes the useful signal, while SNR shows its margin above '
                  'the noise floor. A small margin limits modulation and raises '
                  'the retry probability.',
              'RSSI показывает уровень полезного сигнала, а SNR — его запас над '
                  'шумом. Малый запас ограничивает модуляцию и повышает '
                  'вероятность повторов.'),
          advice: [
            l.t('Try another channel and inspect non-Wi-Fi interference.',
                'Попробуй другой канал и проверь не-Wi-Fi помехи.'),
            l.t('Reduce channel width and compare SNR again.',
                'Уменьши ширину канала и снова сравни SNR.'),
          ],
        ),
      LinkIssueKind.lowRate => _IssueCopy(
          icon: Icons.speed,
          title: l.t('Strong signal, unexpectedly low rate',
              'Сигнал сильный, но rate неожиданно низкий'),
          short: l.t(
              'The negotiated rate or MikroTik throughput estimate is low for '
                  'the measured signal.',
              'Согласованная rate или оценка пропускной способности MikroTik '
                  'низкая для такого сигнала.'),
          explanation: l.t(
              'A strong signal with a very low PHY rate can indicate retries, '
                  'legacy mode, narrow width or a client/AP compatibility issue.',
              'Сильный сигнал при очень низкой PHY-rate может означать повторы, '
                  'legacy-режим, малую ширину или проблему совместимости клиента '
                  'и точки.'),
          advice: [
            l.t('Check the client Wi-Fi generation, channel width and rates.',
                'Проверь поколение Wi-Fi клиента, ширину канала и rates.'),
            l.t('Compare with another device at the same location.',
                'Сравни с другим устройством в той же точке.'),
          ],
        ),
      LinkIssueKind.uplinkAsymmetry => _IssueCopy(
          icon: Icons.upload,
          title: l.t('Weak uplink despite a good downlink',
              'Слабый uplink при хорошем downlink'),
          short: l.t(
              'The phone hears the AP much better than the AP hears the phone.',
              'Телефон слышит точку значительно лучше, чем точка слышит телефон.'),
          explanation: l.t(
              'The AP-to-phone direction looks strong, but the client cannot '
                  'answer at the same level. Excessive AP TX power or an '
                  'obstruction near the client is likely.',
              'Направление точка→телефон выглядит сильным, но клиент не может '
                  'ответить на том же уровне. Вероятны завышенная мощность точки '
                  'или препятствие рядом с клиентом.'),
          advice: [
            l.t('Check AP TX power; more power does not improve the phone uplink.',
                'Проверь мощность точки: её увеличение не улучшает uplink телефона.'),
            l.t('Move closer or add an AP for this area.',
                'Подойди ближе или добавь точку для этой зоны.'),
          ],
        ),
      LinkIssueKind.downlinkAsymmetry => _IssueCopy(
          icon: Icons.download,
          title: l.t(
              'Unusual downlink asymmetry', 'Необычная асимметрия downlink'),
          short: l.t(
              'The AP hears the phone much better than the phone hears the AP.',
              'Точка слышит телефон значительно лучше, чем телефон слышит точку.'),
          explanation: l.t(
              'This may occur with antenna-pattern differences, local '
                  'obstructions or unequal radio conditions in each direction.',
              'Такое возможно из-за диаграммы антенн, локальных препятствий или '
                  'разных условий приёма в двух направлениях.'),
          advice: [
            l.t('Repeat the test with another device and orientation.',
                'Повтори тест с другим устройством и ориентацией.'),
            l.t('Check AP antenna placement and reported TX power.',
                'Проверь размещение антенны точки и её TX power.'),
          ],
        ),
      LinkIssueKind.highLatency => _IssueCopy(
          icon: Icons.timer_outlined,
          title: l.t('Strong signal, high local latency',
              'Сигнал сильный, но локальная задержка высокая'),
          short: l.t(
              'Gateway ping is slow despite strong signal. Airtime contention or '
                  'router processing may be involved.',
              'Ping до шлюза высокий при сильном сигнале. Возможны конкуренция '
                  'за эфир или обработка на роутере.'),
          explanation: l.t(
              'Latency to the gateway covers the Wi-Fi hop and local router, not '
                  'the provider. Persistent delay means the link waits somewhere '
                  'before reaching the internet.',
              'Задержка до шлюза включает Wi-Fi и локальный роутер, но не '
                  'провайдера. Устойчивый рост означает ожидание ещё до выхода в '
                  'интернет.'),
          advice: [
            l.t('Check channel utilisation and the number of active clients.',
                'Проверь занятость канала и количество активных клиентов.'),
            l.t('Compare latency near another AP or when the network is idle.',
                'Сравни задержку у другой точки или во время простоя сети.'),
          ],
        ),
      LinkIssueKind.weakCoverage => _IssueCopy(
          icon: Icons.signal_wifi_bad,
          title: l.t('Link is limited by weak coverage',
              'Связь ограничена слабым покрытием'),
          short: l.t(
              'At least one direction is weak enough to reduce rates and '
                  'increase retries.',
              'Хотя бы одно направление достаточно слабое, чтобы снижать rates '
                  'и увеличивать повторы.'),
          explanation: l.t(
              'This is a coverage problem rather than a strong-signal mismatch. '
                  'The weaker direction defines the usable edge of the cell.',
              'Это проблема покрытия, а не расхождение при сильном сигнале. '
                  'Более слабое направление определяет полезную границу соты.'),
          advice: [
            l.t('Move closer, reposition the AP or add coverage for this area.',
                'Подойди ближе, переставь точку или добавь покрытие в этой зоне.'),
          ],
        ),
    };

Widget _section(String text) => Text(
      text,
      style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.1,
          color: _muted,
          fontWeight: FontWeight.w600),
    );

String _rate(double value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text Mbps';
}

String _compactFacts(LinkDiagnosticSummary s, L10n l) {
  final facts = <String>[
    if (s.phoneRssi != null) 'RSSI ${s.phoneRssi} dBm',
    if (s.apSignal != null) 'AP ${s.apSignal} dBm',
    if (s.lowestCcq != null) 'CCQ ${s.lowestCcq}%',
    if (s.pingAvgMs != null) '${l.t('Ping', 'Пинг')} ${s.pingAvgMs} ms',
    if ((s.pingLossPct ?? 0) > 0) '${l.t('loss', 'потери')} ${s.pingLossPct}%',
  ];
  return facts.join(' · ');
}
