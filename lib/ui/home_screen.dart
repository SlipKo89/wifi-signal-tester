import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../audit/audit.dart';
import '../models/phone_signal.dart';
import '../services/link_service.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'about_dialog.dart';
import 'audit_screen.dart';
import 'delta_info.dart';
import 'devices_screen.dart';
import 'history_screen.dart';
import 'link_diagnostics_sheet.dart';
import 'lte_screen.dart';
import 'reference_screen.dart';
import 'settings_screen.dart';
import 'support_diagnostics_screen.dart';
import 'theme.dart';
import 'whats_new.dart';
import 'widgets/connection_form.dart';
import 'widgets/failure_banner.dart';
import 'widgets/metric_tile.dart';
import 'widgets/roam_transition.dart';
import 'widgets/signal_card.dart';

/// Formats a kbps value as Kbps/Mbps.
String _fmtKbps(int kbps) =>
    kbps >= 1000 ? '${(kbps / 1000).toStringAsFixed(1)} Mbps' : '$kbps Kbps';

/// Colour for a ping RTT (ms) / loss (%).
Color _pingColor(int? ms, int? loss) {
  if ((loss ?? 0) >= 20) return const Color(0xFFF85149);
  if (ms == null) return Colors.grey;
  if (ms < 20) return const Color(0xFF3FB950);
  if (ms < 80) return const Color(0xFFD29922);
  return const Color(0xFFF85149);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Announce new features once after an update.
    maybeShowWhatsNew(context, context.read<SettingsController>());
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>();
    final l = settings.l;
    final connected = ctrl.state == MonitorState.connected;

    void open(Widget screen) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _TitleBar(),
        actions: [
          if (connected)
            IconButton(
              tooltip: settings.alertsEnabled
                  ? l.t('Alerts on', 'Оповещения вкл')
                  : l.t('Alerts off', 'Оповещения выкл'),
              icon: Icon(
                settings.alertsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: settings.alertsEnabled ? AppTheme.apAccent : null,
              ),
              onPressed: () {
                settings.setAlertsEnabled(!settings.alertsEnabled);
                ctrl.applySettings(
                  pollSeconds: settings.pollSeconds,
                  historyLength: settings.historyLength,
                  alertsEnabled: settings.alertsEnabled,
                  alertThresholdDb: settings.alertThresholdDb,
                  minSignalDbm: settings.minSignalDbm,
                  minSnrDb: settings.minSnrDb,
                );
              },
            ),
          if (connected)
            IconButton(
              tooltip: ctrl.recording
                  ? l.t('Stop recording', 'Остановить запись')
                  : l.t('Record', 'Запись'),
              icon: Icon(
                ctrl.recording ? Icons.stop_circle : Icons.fiber_manual_record,
                color: ctrl.recording ? const Color(0xFFF85149) : null,
              ),
              onPressed: () =>
                  ctrl.recording ? ctrl.stopRecording() : ctrl.startRecording(),
            ),
          if (connected)
            IconButton(
              tooltip: ctrl.isLive
                  ? l.t('Pause', 'Пауза')
                  : l.t('Resume', 'Продолжить'),
              icon: Icon(ctrl.isLive ? Icons.pause : Icons.play_arrow),
              onPressed: ctrl.isLive ? ctrl.stopLive : ctrl.startLive,
            ),
          if (connected)
            IconButton(
              tooltip: l.t('Disconnect', 'Отключить'),
              icon: const Icon(Icons.logout),
              onPressed: ctrl.disconnect,
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'audit_wifi':
                  open(const AuditScreen(scope: AuditScope.wifi));
                case 'audit_system':
                  open(const AuditScreen(scope: AuditScope.system));
                case 'phone_audit':
                  open(const AuditScreen(phone: true));
                case 'devices':
                  open(const DevicesScreen());
                case 'lte':
                  open(const LteScreen());
                case 'reference':
                  open(const ReferenceScreen());
                case 'guide':
                  openExternalLink(context, usageUrl(ru: l.ru));
                case 'history':
                  open(const HistoryScreen());
                case 'settings':
                  open(const SettingsScreen());
                case 'changelog':
                  open(const ChangelogScreen());
                case 'diagnostics':
                  open(const SupportDiagnosticsScreen());
                case 'about':
                  showAboutSheet(context);
              }
            },
            itemBuilder: (_) => [
              if (connected && !ctrl.phoneOnly)
                PopupMenuItem(
                  value: 'audit_wifi',
                  child: Text(l.t('Wi-Fi audit', 'Аудит Wi-Fi')),
                ),
              if (connected && !ctrl.phoneOnly)
                PopupMenuItem(
                  value: 'audit_system',
                  child: Text(l.t('System audit', 'Системный аудит')),
                ),
              if (connected && ctrl.phoneOnly)
                PopupMenuItem(
                  value: 'phone_audit',
                  child: Text(
                      l.t('Network audit (phone)', 'Аудит сети (телефон)')),
                ),
              if (connected && !ctrl.phoneOnly)
                PopupMenuItem(
                  value: 'devices',
                  child: Text(l.t('Devices', 'Устройства')),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'lte',
                child: Row(
                  children: [
                    const Icon(Icons.cell_tower, size: 19),
                    const SizedBox(width: 10),
                    Text(l.t('LTE diagnostics', 'Диагностика LTE')),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'reference',
                child: Text(l.t('Reference', 'Справка')),
              ),
              PopupMenuItem(
                value: 'guide',
                child: Text(l.t('How to use (GitHub)', 'Инструкция (GitHub)')),
              ),
              PopupMenuItem(
                value: 'history',
                child: Text(l.t('History', 'История')),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text(l.t('Settings', 'Настройки')),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ctrl.failure != null)
                FailureBanner(
                  failure: ctrl.failure!,
                  l: l,
                  onRetry: ctrl.failure!.canRetry ? ctrl.retry : null,
                  onEditConnection: ctrl.failure!.wantsConnectionEdit
                      ? () async {
                          if (connected) {
                            await ctrl.disconnect();
                          } else {
                            ctrl.dismissFailure();
                          }
                        }
                      : null,
                  onSystemSettings: ctrl.failure!.wantsSystemSettings
                      ? openAppSettings
                      : null,
                  onDiagnostics: () => open(const SupportDiagnosticsScreen()),
                  onDismiss: ctrl.dismissFailure,
                ),
              if (connected)
                _Dashboard(ctrl: ctrl)
              else
                ConnectionForm(
                  busy: ctrl.state == MonitorState.connecting,
                  onConnect: (routers) {
                    ctrl.applySettings(
                      pollSeconds: settings.pollSeconds,
                      historyLength: settings.historyLength,
                      alertsEnabled: settings.alertsEnabled,
                      alertThresholdDb: settings.alertThresholdDb,
                      minSignalDbm: settings.minSignalDbm,
                      minSnrDb: settings.minSnrDb,
                    );
                    ctrl.connect(routers);
                  },
                  onPhoneOnly: () {
                    ctrl.applySettings(
                      pollSeconds: settings.pollSeconds,
                      historyLength: settings.historyLength,
                      alertsEnabled: settings.alertsEnabled,
                      alertThresholdDb: settings.alertThresholdDb,
                      minSignalDbm: settings.minSignalDbm,
                      minSnrDb: settings.minSnrDb,
                    );
                    ctrl.startPhoneOnly();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MonitorController>();
    final l = context.watch<SettingsController>().l;
    final parts = <String>[
      if (ctrl.transportKind != null) ctrl.transportKind!,
      if (ctrl.stackLabel != null) ctrl.stackLabel!,
      if (ctrl.routerCount > 1)
        '${ctrl.routerCount} ${l.t('routers', 'роутеров')}',
    ];
    final sub = ctrl.state == MonitorState.connected && parts.isNotEmpty
        ? parts.join(' · ')
        : 'MikroTik Wi-Fi Tester';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Wi-Fi Signal Tester',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text(sub,
            style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590))),
      ],
    );
  }
}

class _Dashboard extends StatelessWidget {
  final MonitorController ctrl;
  const _Dashboard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final phone = ctrl.phoneSignal;
    final ap = ctrl.stationSignal;
    final l = context.watch<SettingsController>().l;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ctrl.offWifi) _StatusBanner(ctrl: ctrl),
        if (!ctrl.offWifi) LinkDiagnosticsCard(report: ctrl.linkDiagnostics),
        _ConnectionSummary(
          phone: phone,
          delta: ctrl.signalDelta,
          apSignalDbm: ap?.signalDbm,
          apName: ap?.interfaceName ?? ctrl.connectedApName,
          locationIssue: !ctrl.locationGranted || !ctrl.locationServiceOn,
        ),
        const SizedBox(height: 12),
        SignalCard(
          title: l.t('PHONE → hears AP', 'ТЕЛЕФОН → слышит точку'),
          icon: Icons.smartphone,
          accent: AppTheme.phoneAccent,
          signalDbm: phone?.rssiDbm,
          metrics: [
            MetricTile(
              label: ctrl.phoneSnrIsEstimate ? 'SNR est.' : 'SNR',
              value: ctrl.phoneSnr?.toString() ?? '—',
              unit: 'dB',
              color: AppTheme.snrColor(ctrl.phoneSnr),
              helpKey: 'snr',
            ),
            if (ctrl.pingMs != null || ctrl.pingLossPct != null)
              MetricTile(
                label: l.t('Ping', 'Пинг'),
                value: ctrl.pingMs?.toString() ??
                    ((ctrl.pingLossPct ?? 0) >= 100 ? '✕' : '—'),
                unit: 'ms',
                color: _pingColor(ctrl.pingMs, ctrl.pingLossPct),
                helpKey: 'ping',
              ),
            MetricTile(
                label: l.t('Band', 'Диапазон'),
                value: phone?.band ?? '—',
                helpKey: 'band'),
            MetricTile(
                label: 'Freq',
                value: phone?.frequencyMhz?.toString() ?? '—',
                unit: 'MHz',
                helpKey: 'band'),
            if (phone?.channel != null)
              MetricTile(
                  label: l.t('Ch', 'Канал'),
                  value: phone!.channel.toString(),
                  helpKey: 'band'),
            if (phone?.linkSpeedMbps != null)
              MetricTile(
                  label: l.t('Link', 'Линк'),
                  value: phone!.linkSpeedMbps.toString(),
                  unit: 'Mbps',
                  helpKey: 'rate'),
            if (phone?.wifiStandard != null)
              MetricTile(
                  label: l.t('Standard', 'Стандарт'),
                  value: phone!.wifiStandard!),
            if (phone?.security != null)
              MetricTile(
                  label: l.t('Security', 'Защита'), value: phone!.security!),
          ],
        ),
        if (!ctrl.phoneOnly) ...[
          const SizedBox(height: 12),
          SignalCard(
            title: l.t('AP → hears PHONE', 'ТОЧКА → слышит телефон'),
            icon: Icons.router,
            accent: AppTheme.apAccent,
            signalDbm: ap?.signalDbm,
            emptyHint: ctrl.apUnmanaged
                ? (ctrl.connectedApName != null
                    ? l.t(
                        'On ${ctrl.connectedApName} — waiting for the router to '
                            'report this client…',
                        'На точке ${ctrl.connectedApName} — ждём данные от '
                            'роутера…')
                    : l.t(
                        "This client isn't on a MikroTik-managed AP (standalone / "
                            'non-CAPsMAN). No AP-side signal — only the phone side.',
                        'Клиент не на управляемой точке MikroTik (standalone / '
                            'не CAPsMAN). Сигнала с точки нет — только сторона '
                            'телефона.'))
                : null,
            metrics: [
              MetricTile(
                  label: l.t('On AP', 'Точка'),
                  value: ap?.interfaceName ?? '—'),
              if (ctrl.servingHost != null && ctrl.routerCount > 1)
                MetricTile(
                    label: l.t('Via', 'Через'), value: ctrl.servingHost!),
              MetricTile(
                label: ctrl.apSnrIsEstimate ? 'SNR est.' : 'SNR',
                value: ctrl.apSnr?.toString() ?? '—',
                unit: 'dB',
                color: AppTheme.snrColor(ctrl.apSnr),
                helpKey: 'snr',
              ),
              if (ctrl.downKbps != null)
                MetricTile(
                    label: l.t('Down', 'Загрузка'),
                    value: _fmtKbps(ctrl.downKbps!),
                    helpKey: 'throughput'),
              if (ctrl.upKbps != null)
                MetricTile(
                    label: l.t('Up', 'Отдача'),
                    value: _fmtKbps(ctrl.upKbps!),
                    helpKey: 'throughput'),
              MetricTile(
                  label: 'TX rate', value: ap?.txRate ?? '—', helpKey: 'rate'),
              MetricTile(
                  label: 'RX rate', value: ap?.rxRate ?? '—', helpKey: 'rate'),
              if (ap?.pThroughputKbps != null)
                MetricTile(
                    label: l.t('Est. thr', 'Оц. пропуск'),
                    value: _fmtKbps(ap!.pThroughputKbps!),
                    helpKey: 'throughput'),
              if (ap?.signalCh0 != null)
                MetricTile(
                    label: 'Ch0',
                    value: '${ap!.signalCh0}',
                    unit: 'dBm',
                    helpKey: 'signal'),
              if (ap?.signalCh1 != null)
                MetricTile(
                    label: 'Ch1',
                    value: '${ap!.signalCh1}',
                    unit: 'dBm',
                    helpKey: 'signal'),
              if (ap?.txCcq != null)
                MetricTile(
                    label: 'TX CCQ',
                    value: '${ap!.txCcq}',
                    unit: '%',
                    helpKey: 'ccq'),
              if (ap?.rxCcq != null)
                MetricTile(
                    label: 'RX CCQ',
                    value: '${ap!.rxCcq}',
                    unit: '%',
                    helpKey: 'ccq'),
              if (ap?.uptime != null)
                MetricTile(
                    label: l.t('Uptime', 'Аптайм'),
                    value: ap!.uptime!,
                    helpKey: 'uptime'),
            ],
          ),
        ],
        if (ctrl.routerResource != null || ctrl.roamCount > 0) ...[
          const SizedBox(height: 12),
          _RouterHealthCard(ctrl: ctrl),
        ],
        const SizedBox(height: 12),
        _HistoryChart(phone: ctrl.phoneHistory, ap: ctrl.apHistory),
      ],
    );
  }
}

/// Overall pass/fail strip for a walk test: green when every metric is inside
/// the configured targets, amber listing what's out of spec otherwise.
class _StatusBanner extends StatelessWidget {
  final MonitorController ctrl;
  const _StatusBanner({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final ok = ctrl.thresholdsOk;
    final color = ok ? const Color(0xFF3FB950) : const Color(0xFFD29922);

    String nameOf(ThresholdBreach b) => switch (b) {
          ThresholdBreach.phoneSignal => l.t('phone signal', 'сигнал телефона'),
          ThresholdBreach.apSignal => l.t('AP signal', 'сигнал точки'),
          ThresholdBreach.phoneSnr => l.t('phone SNR', 'SNR телефона'),
          ThresholdBreach.apSnr => l.t('AP SNR', 'SNR точки'),
          ThresholdBreach.asymmetry => l.t('asymmetry', 'асимметрия'),
        };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber,
              size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? l.t('Signal targets are met', 'Цели по сигналу соблюдены')
                  : '${l.t('Out of target', 'Вне цели')}: '
                      '${ctrl.breaches.map(nameOf).join(', ')}',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact health strip for the serving router: CPU, board/version, uptime,
/// and how many times the client has roamed this session.
class _RouterHealthCard extends StatelessWidget {
  final MonitorController ctrl;
  const _RouterHealthCard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final cpu = ctrl.cpuLoad;
    final cpuColor = cpu == null
        ? Colors.grey
        : cpu < 50
            ? const Color(0xFF3FB950)
            : cpu < 80
                ? const Color(0xFFD29922)
                : const Color(0xFFF85149);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 16, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  ctrl.routerBoard ?? l.t('Router', 'Роутер'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent,
                      letterSpacing: 0.5),
                ),
                const Spacer(),
                if (ctrl.routerVersion != null)
                  Text('RouterOS ${ctrl.routerVersion}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF7D8590))),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 14,
              children: [
                MetricTile(
                  label: 'CPU',
                  value: cpu?.toString() ?? '—',
                  unit: '%',
                  color: cpuColor,
                ),
                if (ctrl.routerUptime != null)
                  MetricTile(
                      label: l.t('Uptime', 'Аптайм'),
                      value: ctrl.routerUptime!),
                MetricTile(
                    label: l.t('Roams', 'Роуминги'),
                    value: ctrl.roamCount.toString()),
              ],
            ),
            if (ctrl.lastRoamFrom != null && ctrl.lastRoamTo != null) ...[
              const SizedBox(height: 14),
              RoamTransition(
                label: l.t('Last roam', 'Последний переход'),
                from: ctrl.lastRoamFrom!,
                to: ctrl.lastRoamTo!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Top strip: SSID / IP / MAC-resolution status and the two-sided delta.
class _ConnectionSummary extends StatelessWidget {
  final PhoneSignal? phone;
  final int? delta;
  final int? apSignalDbm;
  final String? apName;
  final bool locationIssue;
  const _ConnectionSummary({
    required this.phone,
    required this.delta,
    required this.apSignalDbm,
    required this.apName,
    required this.locationIssue,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    // We're connected if we have an IP — SSID may be hidden without location.
    final connected = phone?.ipAddress != null;
    final title = phone?.ssid ??
        (connected
            ? l.t('Wi-Fi connected', 'Wi-Fi подключён')
            : l.t('Not connected to Wi-Fi', 'Нет подключения к Wi-Fi'));
    final sub = [
      if (phone?.ipAddress != null) phone!.ipAddress!,
      if (phone?.bssid != null) phone!.bssid!,
    ].join('  ·  ');
    // Only nag about location when we're connected but the name is hidden.
    final showHint = connected && phone?.ssid == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sub.isEmpty ? '—' : sub,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF7D8590))),
                    ],
                  ),
                ),
                _DeltaBadge(
                  delta: delta,
                  onTap: () => showDeltaInfo(
                    context,
                    phoneRssi: phone?.rssiDbm,
                    apSignal: apSignalDbm,
                    delta: delta,
                    apName: apName,
                  ),
                ),
              ],
            ),
            if (showHint) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: openAppSettings,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppTheme.apAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.t(
                              'Grant location & turn on GPS to show the Wi-Fi '
                                  'name',
                              'Дай геолокацию и включи GPS, чтобы видеть имя '
                                  'сети'),
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.apAccent),
                        ),
                      ),
                      Text(l.t('Settings', 'Настройки'),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.apAccent)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final int? delta;
  final VoidCallback onTap;
  const _DeltaBadge({required this.delta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final has = delta != null;
    final sign = has && delta! > 0 ? '+' : '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Δ AP−phone',
                    style: TextStyle(fontSize: 9, color: Color(0xFF7D8590))),
                const SizedBox(width: 3),
                Icon(Icons.info_outline,
                    size: 10, color: AppTheme.accent.withValues(alpha: 0.8)),
              ],
            ),
            Text(has ? '$sign$delta dB' : '—',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  final List<int> phone;
  final List<int> ap;
  const _HistoryChart({required this.phone, required this.ap});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Legend(
                    color: AppTheme.phoneAccent,
                    label: l.t('Phone', 'Телефон')),
                const SizedBox(width: 16),
                _Legend(
                    color: AppTheme.apAccent,
                    label: l.t('Access point', 'Точка')),
                const Spacer(),
                Text(l.t('signal history', 'история сигнала'),
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF7D8590))),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: LineChart(
                LineChartData(
                  minY: _minY,
                  maxY: _maxY,
                  // Keep every stroke and fill inside the chart frame.
                  clipData: const FlClipData.all(),
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    _line(phone, AppTheme.phoneAccent),
                    _line(ap, AppTheme.apAccent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // dBm axis bounds; spots are clamped so out-of-range readings can't draw
  // outside the frame.
  static const double _minY = -100;
  static const double _maxY = -20;

  LineChartBarData _line(List<int> data, Color color) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < data.length; i++)
          FlSpot(i.toDouble(), data[i].toDouble().clamp(_minY, _maxY)),
      ],
      isCurved: true,
      preventCurveOverShooting: true,
      barWidth: 2,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFFAAB2BD))),
      ],
    );
  }
}
