import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import '../wifi_logs/wifi_log_analysis.dart';
import 'theme.dart';

class WifiLogScreen extends StatefulWidget {
  final String? targetMac;
  final String? targetLabel;
  final String? targetInterface;

  const WifiLogScreen({
    super.key,
    this.targetMac,
    this.targetLabel,
    this.targetInterface,
  });

  @override
  State<WifiLogScreen> createState() => _WifiLogScreenState();
}

class _WifiLogScreenState extends State<WifiLogScreen> {
  late Future<WifiLogReport> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WifiLogReport> _load() =>
      context.read<MonitorController>().analyzeWifiLogs(
            targetMac: widget.targetMac,
            targetLabel: widget.targetLabel,
            targetInterface: widget.targetInterface,
          );

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Wi-Fi events', 'События Wi-Fi')),
        actions: [
          IconButton(
            tooltip: l.t('Read logs again', 'Прочитать журнал снова'),
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<WifiLogReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(
                    l.t(
                      'Reading the latest RouterOS log window…',
                      'Читаем последние события RouterOS…',
                    ),
                    style: const TextStyle(color: Color(0xFF7D8590)),
                  ),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _ErrorState(l: l, error: snapshot.error, onRetry: _reload);
          }
          return _ReportView(report: snapshot.data!, l: l);
        },
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final WifiLogReport report;
  final L10n l;

  const _ReportView({required this.report, required this.l});

  @override
  Widget build(BuildContext context) {
    final title = report.targetLabel ?? l.t('This device', 'Это устройство');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _PrivacyNote(l: l),
        const SizedBox(height: 12),
        _VerdictCard(report: report, l: l, title: title),
        if (report.handoffs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _HandoffCard(handoffs: report.handoffs, l: l),
        ],
        if (!report.hasDebug) ...[
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.manage_search,
            color: AppTheme.apAccent,
            title: l.t(
              'Detailed wireless debug logging was not detected',
              'Подробное debug-журналирование Wi-Fi не найдено',
            ),
            text: l.t(
              'Standard connect/disconnect events are still analyzed. For a difficult case, enable wireless/caps debug logging manually on the MikroTik, reproduce the issue, then refresh this screen. The app never changes logging settings itself.',
              'Обычные подключения и отключения всё равно анализируются. Для сложного случая вручную включи wireless/caps debug на MikroTik, воспроизведи проблему и обнови этот экран. Приложение само настройки журналирования не меняет.',
            ),
          ),
        ],
        if (report.sources.any((source) => source.truncated)) ...[
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.filter_alt_outlined,
            color: AppTheme.accent,
            title: l.t('Recent window only', 'Только недавний фрагмент'),
            text: l.t(
              'A large router log was limited to the newest 2,000 rows per router before analysis.',
              'Большой журнал ограничен последними 2000 строками каждого роутера.',
            ),
          ),
        ],
        const SizedBox(height: 20),
        _SectionTitle(
          title: l.t('LOG SOURCES', 'ИСТОЧНИКИ ЖУРНАЛА'),
          trailing: l.t(
            '${report.rowsScanned} rows',
            '${report.rowsScanned} строк',
          ),
        ),
        const SizedBox(height: 8),
        for (final source in report.sources) _SourceRow(source: source, l: l),
        const SizedBox(height: 20),
        _SectionTitle(
          title: l.t('NORMALIZED EVENTS', 'РАСПОЗНАННЫЕ СОБЫТИЯ'),
          trailing: '${report.events.length}',
        ),
        const SizedBox(height: 8),
        if (report.events.isEmpty)
          _EmptyEvents(l: l)
        else
          for (final event in report.events) _EventCard(event: event, l: l),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  final L10n l;
  const _PrivacyNote({required this.l});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_outlined,
              size: 16, color: Color(0xFF7D8590)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.t(
                'Read-only. Only the selected MAC and a strict set of AP/CAPsMAN infrastructure events are analyzed. Raw logs and other client MACs are not retained.',
                'Только чтение. Анализируется лишь выбранный MAC и ограниченный набор инфраструктурных событий AP/CAPsMAN. Сырые логи и MAC других клиентов не сохраняются.',
              ),
              style: const TextStyle(
                height: 1.35,
                fontSize: 11,
                color: Color(0xFF7D8590),
              ),
            ),
          ),
        ],
      );
}

class _VerdictCard extends StatelessWidget {
  final WifiLogReport report;
  final L10n l;
  final String title;
  const _VerdictCard({
    required this.report,
    required this.l,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(report.severity);
    final verdict = l.ru ? report.verdictRu : report.verdictEn;
    final detail = l.ru ? report.detailRu : report.detailEn;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_severityIcon(report.severity), color: color, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF7D8590))),
                const SizedBox(height: 2),
                Text(verdict,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(height: 5),
                Text(detail,
                    style: const TextStyle(
                        height: 1.35, fontSize: 12, color: Color(0xFFC9D1D9))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HandoffCard extends StatelessWidget {
  final List<WifiHandoff> handoffs;
  final L10n l;
  const _HandoffCard({required this.handoffs, required this.l});

  @override
  Widget build(BuildContext context) {
    final latest = handoffs.first;
    final color = _severityColor(latest.severity);
    final route =
        '${latest.fromInterface ?? '—'} → ${latest.toInterface ?? '—'}';
    final gap = latest.gap == null
        ? l.t('duration unavailable', 'длительность неизвестна')
        : _duration(latest.gap!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.swap_horiz, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latest.roam
                        ? l.t('Latest measured roam', 'Последний роуминг')
                        : l.t('Latest reconnect', 'Последнее переподключение'),
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
                  ),
                  Text(route,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(gap,
                style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final WifiLogSourceSummary source;
  final L10n l;
  const _SourceRow({required this.source, required this.l});

  @override
  Widget build(BuildContext context) {
    final ok = source.error == null;
    final subtitle = ok
        ? [
            source.transport,
            l.t('${source.rowsScanned} recent rows',
                '${source.rowsScanned} недавних строк'),
            source.debugLogging ? 'debug' : 'info',
          ].join(' · ')
        : source.error!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(ok ? Icons.router_outlined : Icons.error_outline,
            color: ok ? AppTheme.accent : const Color(0xFFF85149)),
        title: Text(source.host, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final WifiLogEvent event;
  final L10n l;
  const _EventCard({required this.event, required this.l});

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(event.severity);
    final title = l.ru ? event.titleRu : event.titleEn;
    final detail = l.ru ? event.detailRu : event.detailEn;
    final time = _eventTime(event);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      Text(time,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF7D8590))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(detail,
                      style: const TextStyle(
                          height: 1.3, fontSize: 11, color: Color(0xFFAAB2BD))),
                  const SizedBox(height: 6),
                  Text(
                    '${event.host} · ${event.transport} · ${_confidence(l, event.confidence)}',
                    style:
                        const TextStyle(fontSize: 10, color: Color(0xFF7D8590)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 3),
                  Text(text,
                      style: const TextStyle(
                          height: 1.35,
                          fontSize: 11,
                          color: Color(0xFFAAB2BD))),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String trailing;
  const _SectionTitle({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7D8590))),
          ),
          Text(trailing,
              style: const TextStyle(fontSize: 10, color: Color(0xFF7D8590))),
        ],
      );
}

class _EmptyEvents extends StatelessWidget {
  final L10n l;
  const _EmptyEvents({required this.l});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(Icons.event_available,
                size: 34, color: Color(0xFF7D8590)),
            const SizedBox(height: 8),
            Text(
              l.t(
                'No matching events in the recent log window.',
                'В недавнем фрагменте подходящих событий нет.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF7D8590)),
            ),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final L10n l;
  final Object? error;
  final VoidCallback onRetry;
  const _ErrorState(
      {required this.l, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: Color(0xFFF85149)),
              const SizedBox(height: 12),
              Text(l.t('Could not analyze Wi-Fi logs',
                  'Не удалось проанализировать журнал Wi-Fi')),
              const SizedBox(height: 6),
              Text(error.toString(),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF7D8590))),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l.t('Try again', 'Повторить')),
              ),
            ],
          ),
        ),
      );
}

Color _severityColor(WifiLogSeverity severity) => switch (severity) {
      WifiLogSeverity.ok => const Color(0xFF3FB950),
      WifiLogSeverity.info => AppTheme.accent,
      WifiLogSeverity.warning => AppTheme.apAccent,
      WifiLogSeverity.critical => const Color(0xFFF85149),
    };

IconData _severityIcon(WifiLogSeverity severity) => switch (severity) {
      WifiLogSeverity.ok => Icons.check_circle_outline,
      WifiLogSeverity.info => Icons.info_outline,
      WifiLogSeverity.warning => Icons.warning_amber_rounded,
      WifiLogSeverity.critical => Icons.error_outline,
    };

String _confidence(L10n l, WifiLogConfidence confidence) =>
    switch (confidence) {
      WifiLogConfidence.confirmed => l.t('confirmed', 'подтверждено'),
      WifiLogConfidence.likely => l.t('likely', 'вероятно'),
      WifiLogConfidence.context => l.t('context', 'контекст'),
    };

String _eventTime(WifiLogEvent event) {
  final time = event.timestamp;
  if (time == null) return event.rawTime.isEmpty ? '—' : event.rawTime;
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  final millis = time.millisecond == 0 ? '' : '.${three(time.millisecond)}';
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}$millis';
}

String _duration(Duration duration) {
  if (duration.inMilliseconds < 1000) return '${duration.inMilliseconds} ms';
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
}
