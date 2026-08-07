import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../lte/lte_history_store.dart';
import '../settings/settings_controller.dart';
import 'widgets/zoomable_lte_chart.dart';

const _green = Color(0xFF3FB950);
const _blue = Color(0xFF58A6FF);
const _muted = Color(0xFF7D8590);

class LteHistoryScreen extends StatefulWidget {
  final LteHistoryStore store;
  final int? activeSessionId;
  final Future<void> Function()? stopActiveRecording;

  const LteHistoryScreen({
    super.key,
    required this.store,
    this.activeSessionId,
    this.stopActiveRecording,
  });

  @override
  State<LteHistoryScreen> createState() => _LteHistoryScreenState();
}

class _LteHistoryScreenState extends State<LteHistoryScreen> {
  late Future<List<LteSessionSummary>> _future;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _future = widget.store.sessions();
  }

  void _reload() {
    setState(() => _future = widget.store.sessions());
  }

  Future<void> _toggle(LteSessionSummary session, L10n l) async {
    if (_selected.contains(session.id)) {
      setState(() => _selected.remove(session.id));
      return;
    }
    if (_selected.length == 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t(
          'Select exactly two sessions. Clear one selection first.',
          'Для сравнения нужны две сессии. Сначала сними одну отметку.',
        )),
      ));
      return;
    }
    setState(() => _selected.add(session.id));
  }

  Future<void> _compare(List<LteSessionSummary> sessions) async {
    final selected = sessions
        .where((session) => _selected.contains(session.id))
        .toList(growable: false);
    if (selected.length != 2) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LteComparisonScreen(
        store: widget.store,
        first: selected[0],
        second: selected[1],
      ),
    ));
  }

  Future<void> _rename(LteSessionSummary session, L10n l) async {
    final text = TextEditingController(text: session.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.t('Rename LTE session', 'Переименовать LTE-сессию')),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(labelText: l.t('Name', 'Название')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('Cancel', 'Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: Text(l.t('Save', 'Сохранить')),
          ),
        ],
      ),
    );
    text.dispose();
    if (value == null || value.isEmpty) return;
    await widget.store.renameSession(session.id, value);
    _reload();
  }

  Future<void> _export(LteSessionSummary session, L10n l) async {
    final csv = await widget.store.exportCsv(session.id);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lte-session-${session.id}.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      text: l.t('LTE measurement session', 'Сессия LTE-замеров'),
    );
  }

  Future<void> _delete(LteSessionSummary session, L10n l) async {
    final yes = await _confirm(
      l.t('Delete this LTE session?', 'Удалить эту LTE-сессию?'),
      l.t(
        'Only this app-created recording will be deleted.',
        'Будет удалена только запись, созданная приложением.',
      ),
      l,
    );
    if (!yes) return;
    if (widget.activeSessionId == session.id) {
      await widget.stopActiveRecording?.call();
    }
    await widget.store.deleteSession(session.id);
    _selected.remove(session.id);
    _reload();
  }

  Future<void> _clear(L10n l) async {
    final yes = await _confirm(
      l.t('Delete all LTE history?', 'Удалить всю LTE-историю?'),
      l.t(
        'All LTE recordings created by the app will be removed.',
        'Все LTE-записи, созданные приложением, будут удалены.',
      ),
      l,
    );
    if (!yes) return;
    await widget.stopActiveRecording?.call();
    await widget.store.clearAll();
    _selected.clear();
    _reload();
  }

  Future<bool> _confirm(String title, String body, L10n l) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.t('Cancel', 'Отмена')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.t('Delete', 'Удалить')),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('LTE measurement history', 'История LTE-замеров')),
        actions: [
          IconButton(
            tooltip: l.t('Delete all', 'Удалить всё'),
            onPressed: () => _clear(l),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<LteSessionSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  l.t(
                    'No LTE recordings yet. Connect to the LTE router and tap the record button.',
                    'LTE-записей пока нет. Подключись к LTE-роутеру и нажми кнопку записи.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted),
                ),
              ),
            );
          }
          return Column(
            children: [
              Material(
                color: _blue.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.t(
                            'Select two sessions for retrospective comparison.',
                            'Отметь две сессии для ретроспективного сравнения.',
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _selected.length == 2
                            ? () => _compare(sessions)
                            : null,
                        icon: const Icon(Icons.compare_arrows, size: 18),
                        label: Text('${l.t('Compare', 'Сравнить')} '
                            '${_selected.length}/2'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: Color(0xFF232B36),
                  ),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return ListTile(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LteSessionScreen(
                            store: widget.store,
                            session: session,
                          ),
                        ),
                      ),
                      leading: Checkbox(
                        value: _selected.contains(session.id),
                        onChanged: (_) => _toggle(session, l),
                      ),
                      title: Text(
                        session.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_date(session.startedMs)} · '
                        '${session.sampleCount} ${l.t('samples', 'замеров')}\n'
                        '${_average(session)}',
                        maxLines: 2,
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          switch (value) {
                            case 'rename':
                              await _rename(session, l);
                            case 'export':
                              await _export(session, l);
                            case 'delete':
                              await _delete(session, l);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text(l.t('Rename', 'Переименовать')),
                          ),
                          PopupMenuItem(
                            value: 'export',
                            enabled: session.sampleCount > 0,
                            child: const Text('CSV'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l.t('Delete', 'Удалить')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _average(LteSessionSummary session) => [
        if (session.averageRsrp != null)
          'RSRP ${_number(session.averageRsrp!)} dBm',
        if (session.averageRsrq != null)
          'RSRQ ${_number(session.averageRsrq!)} dB',
        if (session.averageSinr != null)
          'SINR ${_number(session.averageSinr!)} dB',
      ].join(' · ');
}

class LteSessionScreen extends StatelessWidget {
  final LteHistoryStore store;
  final LteSessionSummary session;

  const LteSessionScreen({
    super.key,
    required this.store,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(title: Text(session.title)),
      body: FutureBuilder<List<LteRecordedSample>>(
        future: store.samplesFor(session.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final samples = snapshot.data!;
          final analysis = LteSessionAnalysis.fromSamples(samples);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SessionFacts(session: session, analysis: analysis, l: l),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.t('Radio history', 'История радиосигнала'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ZoomableLteChart(
                        datasets: [_dataset(session.title, _green, samples)],
                        showRssiAndCqi: true,
                        zoomHint: _zoomHint(l),
                        zoomInTooltip: l.t('Zoom in', 'Увеличить'),
                        zoomOutTooltip: l.t('Zoom out', 'Уменьшить'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _StatsCard(analysis: analysis, l: l),
            ],
          );
        },
      ),
    );
  }
}

class LteComparisonScreen extends StatelessWidget {
  final LteHistoryStore store;
  final LteSessionSummary first;
  final LteSessionSummary second;

  const LteComparisonScreen({
    super.key,
    required this.store,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
          title: Text(l.t('LTE session comparison', 'Сравнение LTE-сессий'))),
      body: FutureBuilder<List<List<LteRecordedSample>>>(
        future: Future.wait([
          store.samplesFor(first.id),
          store.samplesFor(second.id),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final a = snapshot.data![0];
          final b = snapshot.data![1];
          final aa = LteSessionAnalysis.fromSamples(a);
          final bb = LteSessionAnalysis.fromSamples(b);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ComparisonLegend(first: first, second: second),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: ZoomableLteChart(
                    datasets: [
                      _dataset('A', _green, a),
                      _dataset('B', _blue, b),
                    ],
                    showRssiAndCqi: true,
                    zoomHint: _zoomHint(l),
                    zoomInTooltip: l.t('Zoom in', 'Увеличить'),
                    zoomOutTooltip: l.t('Zoom out', 'Уменьшить'),
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
                        l.t(
                          'Averages and difference B − A',
                          'Средние значения и разница B − A',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      _CompareRow('RSRP', 'dBm', aa.rsrp, bb.rsrp),
                      _CompareRow('RSRQ', 'dB', aa.rsrq, bb.rsrq),
                      _CompareRow('SINR', 'dB', aa.sinr, bb.sinr),
                      _CompareRow('RSSI', 'dBm', aa.rssi, bb.rssi),
                      _CompareRow('CQI', '', aa.cqi, bb.cqi),
                      const SizedBox(height: 8),
                      Text(
                        l.t(
                          'A positive Δ means session B has a better average. Compare spread too: a smaller spread is more stable.',
                          'Положительная Δ означает, что среднее в сессии B лучше. Смотри и на разброс: меньший разброс стабильнее.',
                        ),
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionFacts extends StatelessWidget {
  final LteSessionSummary session;
  final LteSessionAnalysis analysis;
  final L10n l;

  const _SessionFacts({
    required this.session,
    required this.analysis,
    required this.l,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fact(l.t('Started', 'Начало'), _date(session.startedMs)),
              _fact(
                  l.t('Duration', 'Длительность'), _duration(session.duration)),
              _fact(l.t('Samples', 'Замеры'), '${analysis.sampleCount}'),
              _fact(l.t('Router', 'Роутер'), session.router),
              _fact(l.t('Interface', 'Интерфейс'), session.interfaceName),
              _fact(l.t('Operator', 'Оператор'), session.operatorName),
              _fact(l.t('Technology', 'Технология'), session.technology),
              _fact(l.t('Dominant band', 'Основной диапазон'),
                  analysis.dominantBand),
              _fact(
                  l.t('Dominant cell', 'Основная сота'), analysis.dominantCell),
            ],
          ),
        ),
      );
}

class _StatsCard extends StatelessWidget {
  final LteSessionAnalysis analysis;
  final L10n l;
  const _StatsCard({required this.analysis, required this.l});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.t('Session statistics', 'Статистика сессии'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _statsHeader(l),
              _statsRow('RSRP', analysis.rsrp),
              _statsRow('RSRQ', analysis.rsrq),
              _statsRow('SINR', analysis.sinr),
              _statsRow('RSSI', analysis.rssi),
              _statsRow('CQI', analysis.cqi),
            ],
          ),
        ),
      );

  Widget _statsHeader(L10n l) => Row(children: [
        const SizedBox(width: 48),
        for (final label in [
          l.t('min', 'мин'),
          l.t('avg', 'ср'),
          l.t('max', 'макс'),
          l.t('spread', 'разброс'),
        ])
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: _muted)),
          ),
      ]);

  Widget _statsRow(String label, LteMetricStats? stats) {
    if (stats == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(children: [
        SizedBox(
          width: 48,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final value in [stats.min, stats.average, stats.max, stats.spread])
          Expanded(child: Text(_number(value), textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _ComparisonLegend extends StatelessWidget {
  final LteSessionSummary first;
  final LteSessionSummary second;
  const _ComparisonLegend({required this.first, required this.second});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              _session('A', _green, first),
              const SizedBox(height: 8),
              _session('B', _blue, second),
            ],
          ),
        ),
      );

  Widget _session(String mark, Color color, LteSessionSummary session) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color.withValues(alpha: 0.16),
            foregroundColor: color,
            child: Text(mark, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text('${session.title}\n${_date(session.startedMs)}',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      );
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String unit;
  final LteMetricStats? first;
  final LteMetricStats? second;

  const _CompareRow(this.label, this.unit, this.first, this.second);

  @override
  Widget build(BuildContext context) {
    if (first == null && second == null) return const SizedBox.shrink();
    final delta = first == null || second == null
        ? null
        : second!.average - first!.average;
    final color = delta == null || delta.abs() < 0.05
        ? _muted
        : delta > 0
            ? _green
            : const Color(0xFFF85149);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(first == null ? '—' : _number(first!.average))),
          Expanded(
              child: Text(second == null ? '—' : _number(second!.average))),
          Expanded(
            child: Text(
              delta == null
                  ? '—'
                  : '${delta >= 0 ? '+' : ''}${_number(delta)} $unit',
              textAlign: TextAlign.end,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

LteChartDataset _dataset(
  String name,
  Color color,
  List<LteRecordedSample> samples,
) =>
    LteChartDataset(
      name: name,
      color: color,
      points: samples
          .map((sample) => LteChartPoint(
                sampledAt: DateTime.fromMillisecondsSinceEpoch(sample.tsMs),
                rsrp: sample.rsrp,
                rsrq: sample.rsrq,
                sinr: sample.sinr,
                rssi: sample.rssi,
                cqi: sample.cqi,
              ))
          .toList(growable: false),
    );

Widget _fact(String label, String? value) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child:
              Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

String _zoomHint(L10n l) => l.t(
      '1× — complete session · pinch with two fingers or use the slider',
      '1× — вся сессия · масштабируй двумя пальцами или ползунком',
    );

String _date(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  return '${hours > 0 ? '${hours}h ' : ''}${minutes}m ${seconds}s';
}

String _number(double value) => value.toStringAsFixed(
      value == value.roundToDouble() ? 0 : 1,
    );
