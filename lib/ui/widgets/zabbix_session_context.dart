import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../settings/settings_controller.dart';
import '../../zabbix/zabbix_binding.dart';
import '../../zabbix/zabbix_binding_store.dart';
import '../../zabbix/zabbix_context_service.dart';
import '../zabbix_binding_screen.dart';
import 'synchronized_timeline.dart';

class ZabbixSessionContext extends StatefulWidget {
  final ZabbixBindingScope scope;
  final String subjectKey;
  final String subjectLabel;
  final int startedMs;
  final int endedMs;
  final String exportName;
  final List<SessionTimelineTrack> localTracks;

  const ZabbixSessionContext({
    super.key,
    required this.scope,
    required this.subjectKey,
    required this.subjectLabel,
    required this.startedMs,
    required this.endedMs,
    required this.exportName,
    required this.localTracks,
  });

  @override
  State<ZabbixSessionContext> createState() => _ZabbixSessionContextState();
}

class _ZabbixSessionContextState extends State<ZabbixSessionContext> {
  final _bindings = ZabbixBindingStore();
  final _context = ZabbixContextService();
  ZabbixBinding? _binding;
  ZabbixContextResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _result = null;
      });
    }
    final binding = await _bindings.load(widget.scope, widget.subjectKey);
    if (!mounted) return;
    setState(() => _binding = binding);
    if (binding == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final result = await _context.load(
        binding,
        from: DateTime.fromMillisecondsSinceEpoch(widget.startedMs),
        till: DateTime.fromMillisecondsSinceEpoch(
          widget.endedMs > widget.startedMs
              ? widget.endedMs
              : widget.startedMs + 1000,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _configure() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ZabbixBindingScreen(
          scope: widget.scope,
          subjectKey: widget.subjectKey,
          subjectLabel: widget.subjectLabel,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  List<SessionTimelineTrack> _combined(bool ru) {
    final tracks = [for (final track in widget.localTracks) track];
    final result = _result;
    if (result == null) return tracks;
    const colors = [
      Color(0xFF58A6FF),
      Color(0xFFFFA657),
      Color(0xFFD2A8FF),
      Color(0xFFF778BA),
      Color(0xFF79C0FF),
      Color(0xFFE3B341),
    ];
    for (var index = 0; index < result.metrics.length; index++) {
      final metric = result.metrics[index];
      final points = metric.series.points
          .map((point) => SessionTimelinePoint(
                point.timestamp.millisecondsSinceEpoch,
                point.value,
              ))
          .toList(growable: false);
      final series = SessionTimelineSeries(
        label: 'Zabbix · ${metric.binding.name}',
        source: 'zabbix',
        color: colors[index % colors.length],
        points: points,
      );
      final key = metric.binding.kind.timelineKey;
      final existingIndex = tracks.indexWhere((track) =>
          track.key == key && _sameUnit(track.unit, metric.binding.units));
      if (existingIndex >= 0) {
        final old = tracks[existingIndex];
        tracks[existingIndex] = old.withSeries([...old.series, series]);
      } else {
        tracks.add(SessionTimelineTrack(
          key: '${key}_zabbix',
          title: metric.binding.kind.label(ru),
          unit: metric.binding.units,
          series: [series],
        ));
      }
    }
    return tracks;
  }

  Future<void> _export(bool ru) async {
    final tracks = _combined(ru);
    final csv = buildCombinedTimelineCsv(tracks);
    final dir = await getTemporaryDirectory();
    final safe = widget.exportName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    final file = File('${dir.path}/$safe-with-zabbix.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      text: ru
          ? 'Локальная сессия и контекст Zabbix'
          : 'Local session with Zabbix context',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final binding = _binding;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.t('Zabbix context', 'Контекст Zabbix'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (binding != null && !_loading)
                  IconButton(
                    tooltip: l.t('Reload', 'Обновить'),
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                IconButton(
                  tooltip: l.t('Configure link', 'Настроить привязку'),
                  onPressed: _configure,
                  icon: Icon(binding == null ? Icons.add_link : Icons.tune),
                ),
              ],
            ),
            if (binding == null && !_loading) ...[
              Text(l.t(
                'Link this measurement source to a Zabbix host to compare router metrics over exactly the same period.',
                'Привяжи этот источник замеров к узлу Zabbix, чтобы сравнить метрики роутера ровно за тот же период.',
              )),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _configure,
                icon: const Icon(Icons.add_link),
                label: Text(l.t('Link Zabbix', 'Привязать Zabbix')),
              ),
            ] else ...[
              if (binding != null)
                Text(
                  '${binding.hostName} · ${binding.metrics.length} '
                  '${l.t('metrics', 'метрик')}',
                  style: const TextStyle(color: Color(0xFF7D8590)),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  l.t(
                    'Could not load the linked Zabbix history. $_error',
                    'Не удалось загрузить привязанную историю Zabbix. $_error',
                  ),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 12),
                if (_result!.metrics
                    .every((metric) => metric.series.points.isEmpty))
                  Text(
                    l.t(
                      'Zabbix returned no points for this session period. Check item history retention and timestamps.',
                      'Zabbix не вернул точек за период сессии. Проверь хранение history у item и время на системах.',
                    ),
                    style: const TextStyle(color: Colors.orange),
                  ),
                if (_result!.metrics
                    .any((metric) => metric.series.possiblyTruncated))
                  Text(
                    l.t(
                      'At least one raw series reached the 1,500-point limit and may be partial.',
                      'Хотя бы одна исходная серия достигла лимита 1 500 точек и может быть неполной.',
                    ),
                    style: const TextStyle(color: Colors.orange),
                  ),
                Text(
                  l.t(
                    'All tracks share one time cursor; each keeps its own scale. Local data stays on the device, while Zabbix points are read on demand and are not copied into history.',
                    'У всех графиков общий временной курсор, но своя шкала. Локальные данные остаются на устройстве, точки Zabbix читаются по запросу и не копируются в историю.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF9DA7B3),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                SynchronizedTimeline(
                  startedMs: widget.startedMs,
                  endedMs: widget.endedMs,
                  tracks: _combined(l.ru),
                  ru: l.ru,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _export(l.ru),
                  icon: const Icon(Icons.ios_share),
                  label: Text(l.t(
                    'Export combined CSV',
                    'Экспорт общего CSV',
                  )),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String buildCombinedTimelineCsv(List<SessionTimelineTrack> tracks) {
  final buffer = StringBuffer(
    'source,track,series,timestamp_ms,value,unit\n',
  );
  String csv(Object? value) {
    final text = (value ?? '').toString().replaceAll('"', '""');
    return text.contains(',') || text.contains('"') || text.contains('\n')
        ? '"$text"'
        : text;
  }

  for (final track in tracks) {
    for (final series in track.series) {
      for (final point in series.points) {
        buffer.writeln([
          series.source,
          track.title,
          series.label,
          point.timestampMs,
          point.value,
          track.unit,
        ].map(csv).join(','));
      }
    }
  }
  return buffer.toString();
}

bool _sameUnit(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();
