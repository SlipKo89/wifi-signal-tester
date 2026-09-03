import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../history/history_store.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import '../zabbix/zabbix_binding.dart';
import 'widgets/app_safe_area.dart';
import 'widgets/synchronized_timeline.dart';
import 'widgets/zabbix_session_context.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late HistoryStore _store;
  late Future<List<SessionInfo>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = context.read<MonitorController>().history;
    _future = _store.sessions();
  }

  void _reload() => setState(() => _future = _store.sessions());

  Future<void> _export(SessionInfo s) async {
    final csv = await _store.exportCsv(s.id);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/wifi-session-${s.id}.csv');
    await f.writeAsString(csv);
    await Share.shareXFiles([XFile(f.path)], text: 'Wi-Fi survey session');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Recorded sessions', 'Записанные сессии')),
        actions: [
          IconButton(
            tooltip: l.t('Clear all', 'Очистить всё'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await _store.clearAll();
              _reload();
            },
          ),
        ],
      ),
      body: AppSafeArea(
        child: FutureBuilder<List<SessionInfo>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sessions = snap.data!;
            if (sessions.isEmpty) {
              return Center(
                child: Text(
                  l.t('No recordings yet.\nTap ● Record on the dashboard.',
                      'Записей пока нет.\nНажми ● Record на дашборде.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF7D8590)),
                ),
              );
            }
            return ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFF232B36)),
              itemBuilder: (context, i) {
                final s = sessions[i];
                final dt = DateTime.fromMillisecondsSinceEpoch(s.startedMs);
                return ListTile(
                  onTap: s.sampleCount == 0
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => WifiSessionScreen(
                                store: _store,
                                session: s,
                              ),
                            ),
                          ),
                  leading: const Icon(Icons.timeline),
                  title: Text(_fmt(dt)),
                  subtitle:
                      Text('${s.sampleCount} ${l.t('samples', 'замеров')}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l.t('Export CSV', 'Экспорт CSV'),
                        icon: const Icon(Icons.ios_share),
                        onPressed: s.sampleCount == 0 ? null : () => _export(s),
                      ),
                      IconButton(
                        tooltip: l.t('Delete', 'Удалить'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _store.deleteSession(s.id);
                          _reload();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

class WifiSessionScreen extends StatelessWidget {
  final HistoryStore store;
  final SessionInfo session;

  const WifiSessionScreen({
    super.key,
    required this.store,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Wi-Fi session', 'Wi-Fi-сессия')),
      ),
      body: AppSafeArea(
        child: FutureBuilder<List<Sample>>(
          future: store.samplesFor(session.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final samples = snapshot.data!;
            final tracks = _wifiTracks(samples, l.ru);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sessionDate(session.startedMs),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('${session.sampleCount} '
                            '${l.t('samples', 'замеров')} · '
                            '${_duration(session.duration, l.ru)}'),
                        if (session.routerHost != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${l.t('Router', 'Роутер')}: '
                            '${session.routerHost}',
                            style: const TextStyle(color: Color(0xFF9DA7B3)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.t('Local Wi-Fi history', 'Локальная история Wi-Fi'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        SynchronizedTimeline(
                          startedMs: session.startedMs,
                          endedMs: session.endedMs,
                          tracks: tracks,
                          ru: l.ru,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ZabbixSessionContext(
                  scope: ZabbixBindingScope.wifi,
                  subjectKey: session.routerHost == null
                      ? 'session:${session.id}'
                      : 'router:${session.routerHost!.trim().toLowerCase()}',
                  subjectLabel: session.routerHost ??
                      l.t('Wi-Fi session ${session.id}',
                          'Wi-Fi-сессия ${session.id}'),
                  startedMs: session.startedMs,
                  endedMs: session.endedMs,
                  exportName: 'wifi-session-${session.id}',
                  localTracks: tracks,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

List<SessionTimelineTrack> _wifiTracks(List<Sample> samples, bool ru) => [
      SessionTimelineTrack(
        key: 'wifi_signal',
        title: ru ? 'Сигнал Wi-Fi' : 'Wi-Fi signal',
        unit: 'dBm',
        series: [
          SessionTimelineSeries(
            label: ru ? 'Телефон' : 'Phone',
            source: 'local',
            color: const Color(0xFF3FB950),
            points: [
              for (final sample in samples)
                if (sample.phoneRssi != null)
                  SessionTimelinePoint(
                    sample.tsMs,
                    sample.phoneRssi!.toDouble(),
                  ),
            ],
          ),
          SessionTimelineSeries(
            label: ru ? 'Точка' : 'AP',
            source: 'local',
            color: const Color(0xFFE3B341),
            points: [
              for (final sample in samples)
                if (sample.apSignal != null)
                  SessionTimelinePoint(
                    sample.tsMs,
                    sample.apSignal!.toDouble(),
                  ),
            ],
          ),
        ],
      ),
      SessionTimelineTrack(
        key: 'wifi_snr',
        title: 'Wi-Fi SNR',
        unit: 'dB',
        series: [
          SessionTimelineSeries(
            label: ru ? 'Точка' : 'AP',
            source: 'local',
            color: const Color(0xFFD2A8FF),
            points: [
              for (final sample in samples)
                if (sample.apSnr != null)
                  SessionTimelinePoint(sample.tsMs, sample.apSnr!.toDouble()),
            ],
          ),
        ],
      ),
      SessionTimelineTrack(
        key: 'local_throughput',
        title: ru ? 'Трафик клиента' : 'Client traffic',
        unit: 'Kbps',
        series: [
          SessionTimelineSeries(
            label: ru ? 'Приём' : 'Down',
            source: 'local',
            color: const Color(0xFF58A6FF),
            points: [
              for (final sample in samples)
                if (sample.downKbps != null)
                  SessionTimelinePoint(
                    sample.tsMs,
                    sample.downKbps!.toDouble(),
                  ),
            ],
          ),
          SessionTimelineSeries(
            label: ru ? 'Отдача' : 'Up',
            source: 'local',
            color: const Color(0xFFF778BA),
            points: [
              for (final sample in samples)
                if (sample.upKbps != null)
                  SessionTimelinePoint(
                    sample.tsMs,
                    sample.upKbps!.toDouble(),
                  ),
            ],
          ),
        ],
      ),
    ];

String _sessionDate(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}  '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _duration(Duration value, bool ru) {
  final seconds = value.inSeconds;
  if (seconds < 60) return '$seconds ${ru ? 'с' : 's'}';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes ${ru ? 'мин' : 'min'} $rest ${ru ? 'с' : 's'}';
}
