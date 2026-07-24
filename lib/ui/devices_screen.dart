import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/station_signal.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'theme.dart';

class _Lease {
  final String ip;
  final String mac;
  final String name;
  final bool bound;
  const _Lease(this.ip, this.mac, this.name, this.bound);
}

/// Lists devices from the routers' DHCP leases and shows the AP-side signal for
/// any one you pick — so you can check how the APs hear a TV, laptop, etc.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<_Lease>> _future;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load();
  }

  Future<List<_Lease>> _load() async {
    final ctrl = context.read<MonitorController>();
    final byMac = <String, _Lease>{};
    for (final svc in ctrl.routers) {
      try {
        for (final r in await svc.readMenu('/ip/dhcp-server/lease')) {
          final ip = r['address'] ?? '';
          final mac = r['mac-address'] ?? '';
          if (ip.isEmpty || mac.isEmpty) continue;
          final name = _clean(r['host-name']) ??
              _clean(r['comment']) ??
              mac;
          byMac[mac.toUpperCase()] =
              _Lease(ip, mac, name, r['status'] == 'bound');
        }
      } catch (_) {}
    }
    final list = byMac.values.toList()..sort((a, b) => _ipCmp(a.ip, b.ip));
    return list;
  }

  String? _clean(String? s) {
    if (s == null) return null;
    final t = s.replaceAll(RegExp(r'^-=\s*|\s*=-$'), '').trim();
    return t.isEmpty ? null : t;
  }

  int _ipCmp(String a, String b) {
    final pa = a.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pb = b.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (var i = 0; i < 4 && i < pa.length && i < pb.length; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Devices', 'Устройства')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.t('Search by name / IP / MAC', 'Поиск по имени / IP / MAC'),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_Lease>>(
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
                            d.ip.contains(_query) ||
                            d.mac.toLowerCase().contains(_query))
                        .toList();
                if (items.isEmpty) {
                  return Center(
                    child: Text(l.t('No devices.', 'Устройств нет.'),
                        style: const TextStyle(color: Color(0xFF7D8590))),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFF232B36)),
                  itemBuilder: (context, i) {
                    final d = items[i];
                    return ListTile(
                      leading: Icon(Icons.devices_other,
                          color: d.bound
                              ? AppTheme.phoneAccent
                              : const Color(0xFF7D8590)),
                      title: Text(d.name),
                      subtitle: Text('${d.ip}  ·  ${d.mac}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _openDevice(d),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openDevice(_Lease d) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeviceSheet(lease: d),
    );
  }
}

class _DeviceSheet extends StatefulWidget {
  final _Lease lease;
  const _DeviceSheet({required this.lease});

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  StationSignal? _station;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    final ctrl = context.read<MonitorController>();
    StationSignal? found;
    for (final svc in ctrl.routers) {
      try {
        found = await svc.fetchStation(widget.lease.mac);
      } catch (_) {}
      if (found != null) break;
    }
    if (mounted) {
      setState(() {
        _station = found;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final d = widget.lease;
    final s = _station;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${d.ip}  ·  ${d.mac}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7D8590))),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (s == null)
              _empty(l)
            else
              _signal(l, s),
          ],
        ),
      ),
    );
  }

  Widget _empty(L10n l) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          l.t(
              'Not on a managed AP right now — the device is offline, wired, or '
              'on an AP this router doesn\'t manage.',
              'Сейчас не на управляемой точке — устройство офлайн, по кабелю или '
              'на точке, которой этот роутер не управляет.'),
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF9DA7B3)),
        ),
      );

  Widget _signal(L10n l, StationSignal s) {
    final color = AppTheme.signalColor(s.signalDbm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    fontSize: 34, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 4),
            const Text('dBm',
                style: TextStyle(color: Color(0xFF7D8590), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 20, runSpacing: 12, children: [
          _tile(l.t('On AP', 'Точка'), s.interfaceName ?? '—'),
          if (s.ssid != null) _tile('SSID', s.ssid!),
          if (s.txRate != null) _tile('TX rate', s.txRate!),
          if (s.rxRate != null) _tile('RX rate', s.rxRate!),
          if (s.uptime != null) _tile(l.t('Uptime', 'Аптайм'), s.uptime!),
        ]),
      ],
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
