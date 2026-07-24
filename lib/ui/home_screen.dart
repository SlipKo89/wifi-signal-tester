import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/phone_signal.dart';
import '../state/monitor_controller.dart';
import 'about_dialog.dart';
import 'theme.dart';
import 'widgets/connection_form.dart';
import 'widgets/metric_tile.dart';
import 'widgets/signal_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MonitorController>();
    final connected = ctrl.state == MonitorState.connected;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _TitleBar(),
        actions: [
          if (connected)
            IconButton(
              tooltip: ctrl.isLive ? 'Pause' : 'Resume',
              icon: Icon(ctrl.isLive ? Icons.pause : Icons.play_arrow),
              onPressed: ctrl.isLive ? ctrl.stopLive : ctrl.startLive,
            ),
          if (connected)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.logout),
              onPressed: ctrl.disconnect,
            ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: connected
              ? _Dashboard(ctrl: ctrl)
              : ConnectionForm(
                  busy: ctrl.state == MonitorState.connecting,
                  onConnect: ctrl.connect,
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
    final parts = <String>[
      if (ctrl.transportKind != null) ctrl.transportKind!,
      if (ctrl.stackLabel != null) ctrl.stackLabel!,
      if (ctrl.routerCount > 1) '${ctrl.routerCount} routers',
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
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF7D8590))),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ctrl.error != null) _ErrorBanner(message: ctrl.error!),
        _ConnectionSummary(
          phone: phone,
          delta: ctrl.signalDelta,
          locationIssue: !ctrl.locationGranted || !ctrl.locationServiceOn,
        ),
        const SizedBox(height: 12),
        SignalCard(
          title: 'PHONE → hears AP',
          icon: Icons.smartphone,
          accent: AppTheme.phoneAccent,
          signalDbm: phone?.rssiDbm,
          metrics: [
            MetricTile(
              label: ctrl.phoneSnrIsEstimate ? 'SNR est.' : 'SNR',
              value: ctrl.phoneSnr?.toString() ?? '—',
              unit: 'dB',
              color: AppTheme.snrColor(ctrl.phoneSnr),
            ),
            MetricTile(label: 'Band', value: phone?.band ?? '—'),
            MetricTile(
                label: 'Freq',
                value: phone?.frequencyMhz?.toString() ?? '—',
                unit: 'MHz'),
          ],
        ),
        const SizedBox(height: 12),
        SignalCard(
          title: 'AP → hears PHONE',
          icon: Icons.router,
          accent: AppTheme.apAccent,
          signalDbm: ap?.signalDbm,
          emptyHint: ctrl.apUnmanaged
              ? (ctrl.connectedApName != null
                  ? 'On ${ctrl.connectedApName} — waiting for the router to '
                      'report this client…'
                  : "This client isn't on a MikroTik-managed AP (standalone / "
                      'non-CAPsMAN). No AP-side signal — only the phone side.')
              : null,
          metrics: [
            MetricTile(label: 'On AP', value: ap?.interfaceName ?? '—'),
            if (ctrl.servingHost != null && ctrl.routerCount > 1)
              MetricTile(label: 'Via', value: ctrl.servingHost!),
            MetricTile(
              label: ctrl.apSnrIsEstimate ? 'SNR est.' : 'SNR',
              value: ctrl.apSnr?.toString() ?? '—',
              unit: 'dB',
              color: AppTheme.snrColor(ctrl.apSnr),
            ),
            MetricTile(label: 'TX rate', value: ap?.txRate ?? '—'),
            MetricTile(label: 'RX rate', value: ap?.rxRate ?? '—'),
            if (ap?.signalCh0 != null)
              MetricTile(
                  label: 'Ch0', value: '${ap!.signalCh0}', unit: 'dBm'),
            if (ap?.signalCh1 != null)
              MetricTile(
                  label: 'Ch1', value: '${ap!.signalCh1}', unit: 'dBm'),
            if (ap?.rxCcq != null)
              MetricTile(label: 'RX CCQ', value: '${ap!.rxCcq}', unit: '%'),
          ],
        ),
        const SizedBox(height: 12),
        _HistoryChart(
            phone: ctrl.phoneHistory, ap: ctrl.apHistory),
      ],
    );
  }
}

/// Top strip: SSID / IP / MAC-resolution status and the two-sided delta.
class _ConnectionSummary extends StatelessWidget {
  final PhoneSignal? phone;
  final int? delta;
  final bool locationIssue;
  const _ConnectionSummary({
    required this.phone,
    required this.delta,
    required this.locationIssue,
  });

  @override
  Widget build(BuildContext context) {
    // We're connected if we have an IP — SSID may be hidden without location.
    final connected = phone?.ipAddress != null;
    final title = phone?.ssid ??
        (connected ? 'Wi-Fi connected' : 'Not connected to Wi-Fi');
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
                _DeltaBadge(delta: delta),
              ],
            ),
            if (showHint) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: openAppSettings,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: AppTheme.apAccent),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Grant location & turn on GPS to show the Wi-Fi name',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.apAccent),
                        ),
                      ),
                      Text('Settings',
                          style: TextStyle(
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
  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final has = delta != null;
    final sign = has && delta! > 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text('Δ AP−phone',
              style: TextStyle(fontSize: 9, color: Color(0xFF7D8590))),
          Text(has ? '$sign$delta dB' : '—',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _Legend(color: AppTheme.phoneAccent, label: 'Phone'),
                SizedBox(width: 16),
                _Legend(color: AppTheme.apAccent, label: 'Access point'),
                Spacer(),
                Text('signal history',
                    style: TextStyle(
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1618),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5C2327)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFFF85149), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFF0B4B4))),
          ),
        ],
      ),
    );
  }
}
