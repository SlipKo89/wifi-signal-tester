import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../router/router_connection.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'about_dialog.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'lte_screen.dart';
import 'reference_screen.dart';
import 'settings_screen.dart';
import 'support_diagnostics_screen.dart';
import 'theme.dart';
import 'whats_new.dart';
import 'widgets/app_safe_area.dart';
import 'wifi_sites_screen.dart';
import 'wifi_floor_maps_screen.dart';
import 'zabbix_screen.dart';

class ModeHomeScreen extends StatefulWidget {
  const ModeHomeScreen({super.key});

  @override
  State<ModeHomeScreen> createState() => _ModeHomeScreenState();
}

class _ModeHomeScreenState extends State<ModeHomeScreen> {
  @override
  void initState() {
    super.initState();
    maybeShowWhatsNew(context, context.read<SettingsController>());
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _leaveCurrentWifi(RouterVendor target) async {
    final ctrl = context.read<MonitorController>();
    if (ctrl.state != MonitorState.connected) return true;
    if (target == RouterVendor.mikrotik && ctrl.phoneOnly) return true;
    final sameVendor = target == RouterVendor.mikrotik
        ? ctrl.hasMikrotikRouters
        : ctrl.hasKeeneticRouters;
    if (sameVendor && !ctrl.phoneOnly) return true;
    final l = context.read<SettingsController>().l;
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t('Switch Wi-Fi mode?', 'Сменить режим Wi-Fi?')),
            content: Text(l.t(
              'The current Wi-Fi measurement will be disconnected before the '
                  'other vendor mode opens.',
              'Текущий Wi-Fi-замер будет отключён перед открытием режима '
                  'другого производителя.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.t('Switch', 'Переключить')),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return false;
    await ctrl.disconnect();
    return mounted;
  }

  Future<void> _openMikrotik() async {
    if (!await _leaveCurrentWifi(RouterVendor.mikrotik)) return;
    await _open(const WifiSitesScreen());
  }

  Future<void> _openKeenetic() async {
    if (!await _leaveCurrentWifi(RouterVendor.keenetic)) return;
    await _open(const HomeScreen(vendor: RouterVendor.keenetic));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final ctrl = context.watch<MonitorController>();
    final activeMikrotik = ctrl.state == MonitorState.connected &&
        (ctrl.hasMikrotikRouters || ctrl.phoneOnly);
    final activeKeenetic = ctrl.state == MonitorState.connected &&
        ctrl.hasKeeneticRouters &&
        !ctrl.phoneOnly;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kAppName,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              'Wi-Fi & LTE field toolkit',
              style: TextStyle(fontSize: 10, color: Color(0xFF7D8590)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.t('Settings', 'Настройки'),
            onPressed: () => _open(const SettingsScreen()),
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'history':
                  _open(const HistoryScreen());
                case 'zabbix':
                  _open(const ZabbixScreen());
                case 'floor_maps':
                  _open(const WifiFloorMapsScreen());
                case 'reference':
                  _open(const ReferenceScreen());
                case 'changelog':
                  _open(const ChangelogScreen());
                case 'diagnostics':
                  _open(const SupportDiagnosticsScreen());
                case 'about':
                  showAboutSheet(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'history',
                child: Text(l.t('Wi-Fi history', 'История Wi-Fi')),
              ),
              PopupMenuItem(
                value: 'zabbix',
                child: Text(l.t('Zabbix history', 'История из Zabbix')),
              ),
              PopupMenuItem(
                value: 'floor_maps',
                child: Text(l.t('Wi-Fi floor maps', 'Карты Wi-Fi')),
              ),
              PopupMenuItem(
                value: 'reference',
                child: Text(l.t('Reference', 'Справка')),
              ),
              PopupMenuItem(
                value: 'changelog',
                child: Text(l.t('Changelog', 'История версий')),
              ),
              PopupMenuItem(
                value: 'diagnostics',
                child: Text(l.t('Support report', 'Отчёт в поддержку')),
              ),
              PopupMenuItem(
                value: 'about',
                child: Text(l.t('About', 'О программе')),
              ),
            ],
          ),
        ],
      ),
      body: AppSafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l.t('Choose a tool', 'Выбери инструмент'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              l.t(
                'Each mode keeps its own connection profiles and workflow.',
                'У каждого режима свои подключения и рабочий сценарий.',
              ),
              style: const TextStyle(color: Color(0xFF8B949E)),
            ),
            const SizedBox(height: 18),
            _ModeCard(
              icon: Icons.wifi_find,
              color: AppTheme.accent,
              title: 'MikroTik Wi-Fi',
              subtitle: l.t(
                'Two-sided signal, sites with several APs, audit and roaming',
                'Двусторонний сигнал, объекты с несколькими точками, аудит и роуминг',
              ),
              active: activeMikrotik,
              activeLabel: l.t('ACTIVE', 'АКТИВНО'),
              onTap: _openMikrotik,
            ),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.cell_tower,
              color: AppTheme.apAccent,
              title: 'MikroTik LTE',
              subtitle: l.t(
                'Radio diagnostics, antenna alignment, history and LTE audit',
                'Диагностика радио, юстировка антенны, история и LTE-аудит',
              ),
              onTap: () => _open(const LteScreen()),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.router_outlined,
              color: AppTheme.phoneAccent,
              title: 'Keenetic Wi-Fi',
              badge: l.t('ALPHA', 'АЛЬФА'),
              subtitle: l.t(
                'Current-device signal over HTTPS RCI; limited compatibility',
                'Сигнал текущего устройства через HTTPS RCI; ограниченная совместимость',
              ),
              active: activeKeenetic,
              activeLabel: l.t('ACTIVE', 'АКТИВНО'),
              onTap: _openKeenetic,
            ),
            const SizedBox(height: 20),
            Text(
              l.t('Additional tools', 'Дополнительные инструменты'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: Text(l.t('Wi-Fi floor maps', 'Карты Wi-Fi')),
                    subtitle: Text(l.t(
                      'Import or draw an editable scaled floor plan',
                      'Импортировать или нарисовать редактируемый план в масштабе',
                    )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const WifiFloorMapsScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.monitor_heart_outlined),
                    title: Text(l.t('Zabbix history', 'История из Zabbix')),
                    subtitle: Text(l.t(
                      'Compare saved measurements with monitoring data',
                      'Сравнить сохранённые замеры с данными мониторинга',
                    )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ZabbixScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(l.t('Reference', 'Справка')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ReferenceScreen()),
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

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final bool active;
  final String activeLabel;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.active = false,
    this.activeLabel = 'ACTIVE',
  });

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            _Pill(label: badge!, color: color),
                          ],
                          if (active) ...[
                            const SizedBox(width: 8),
                            _Pill(
                              label: activeLabel,
                              color: AppTheme.phoneAccent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFAAB2BD),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 11),
                  child: Icon(Icons.chevron_right, color: Color(0xFF7D8590)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}
