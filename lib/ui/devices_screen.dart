import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/station_signal.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'theme.dart';

class _Dev {
  final StationSignal station;
  final String? ip;
  final String name;
  const _Dev(this.station, this.ip, this.name);

  String get mac => station.macAddress;
}

/// Lists the devices currently on Wi-Fi (from the routers' registration tables),
/// enriched with IP and name from DHCP leases. Tap one to see how the APs hear
/// it — handy for checking a TV, laptop, a guest's phone, etc.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<_Dev>> _future;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load();
  }

  Future<List<_Dev>> _load() async {
    final ctrl = context.read<MonitorController>();

    // MAC -> (ip, name) from DHCP leases.
    final leaseIp = <String, String>{};
    final leaseName = <String, String>{};
    for (final svc in ctrl.routers) {
      try {
        for (final r in await svc.readMenu('/ip/dhcp-server/lease')) {
          final mac = (r['mac-address'] ?? '').toUpperCase();
          if (mac.isEmpty) continue;
          final ip = r['address'];
          if (ip != null && ip.isNotEmpty) leaseIp[mac] = ip;
          final name = _clean(r['host-name']) ?? _clean(r['comment']);
          if (name != null) leaseName[mac] = name;
        }
      } catch (_) {}
    }

    // Devices currently associated on Wi-Fi.
    final devs = <String, _Dev>{};
    for (final svc in ctrl.routers) {
      try {
        for (final st in await svc.fetchAllStations()) {
          final mac = st.macAddress.toUpperCase();
          if (mac.isEmpty || devs.containsKey(mac)) continue;
          devs[mac] = _Dev(st, leaseIp[mac], leaseName[mac] ?? st.macAddress);
        }
      } catch (_) {}
    }

    final list = devs.values.toList()
      ..sort((a, b) =>
          (b.station.signalDbm ?? -999).compareTo(a.station.signalDbm ?? -999));
    return list;
  }

  String? _clean(String? s) {
    if (s == null) return null;
    final t = s.replaceAll(RegExp(r'^-=\s*|\s*=-$'), '').trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Devices on Wi-Fi', 'Устройства в Wi-Fi')),
        actions: [
          IconButton(
            tooltip: l.t('Refresh', 'Обновить'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.t('Search name / IP / MAC', 'Поиск имя / IP / MAC'),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_Dev>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!;
                final items = _query.isEmpty
                    ? all
                    : all
                        .where((d) =>
                            d.name.toLowerCase().contains(_query) ||
                            (d.ip ?? '').contains(_query) ||
                            d.mac.toLowerCase().contains(_query))
                        .toList();
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                        l.t('No devices on Wi-Fi right now.',
                            'Сейчас в Wi-Fi никого нет.'),
                        style: const TextStyle(color: Color(0xFF7D8590))),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFF232B36)),
                  itemBuilder: (context, i) => _row(l, items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(L10n l, _Dev d) {
    final sig = d.station.signalDbm;
    final color = AppTheme.signalColor(sig);
    return ListTile(
      leading: Icon(Icons.devices_other, color: color),
      title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${d.ip ?? d.mac}  ·  ${d.station.interfaceName ?? '—'}',
          style: const TextStyle(fontSize: 12)),
      trailing: Text(sig == null ? '—' : '$sig',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.surface,
        showDragHandle: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _DeviceSheet(dev: d),
      ),
    );
  }
}

class _DeviceSheet extends StatelessWidget {
  final _Dev dev;
  const _DeviceSheet({required this.dev});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final s = dev.station;
    final color = AppTheme.signalColor(s.signalDbm);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dev.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${dev.ip ?? '—'}  ·  ${dev.mac}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7D8590))),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.router, size: 16, color: AppTheme.apAccent),
                const SizedBox(width: 6),
                Text(l.t('AP → hears device', 'Точка → слышит устройство'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.apAccent)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(s.signalDbm?.toString() ?? '—',
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(width: 4),
                const Text('dBm',
                    style: TextStyle(color: Color(0xFF7D8590), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 20, runSpacing: 12, children: [
              _tile(l.t('On AP', 'Точка'), s.interfaceName ?? '—'),
              if (s.ssid != null) _tile('SSID', s.ssid!),
              if (s.txRate != null) _tile('TX rate', s.txRate!),
              if (s.rxRate != null) _tile('RX rate', s.rxRate!),
              if (s.rxCcq != null) _tile('RX CCQ', '${s.rxCcq}%'),
              if (s.uptime != null) _tile(l.t('Uptime', 'Аптайм'), s.uptime!),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  color: Color(0xFF7D8590),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      );
}
