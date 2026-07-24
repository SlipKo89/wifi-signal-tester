import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../history/history_store.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';

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
      body: FutureBuilder<List<SessionInfo>>(
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
                leading: const Icon(Icons.timeline),
                title: Text(_fmt(dt)),
                subtitle: Text('${s.sampleCount} ${l.t('samples', 'замеров')}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l.t('Export CSV', 'Экспорт CSV'),
                      icon: const Icon(Icons.ios_share),
                      onPressed:
                          s.sampleCount == 0 ? null : () => _export(s),
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
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
