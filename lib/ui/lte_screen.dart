import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../diagnostics/app_failure.dart';
import '../l10n/l10n.dart';
import '../lte/lte_controller.dart';
import '../lte/lte_credentials_store.dart';
import '../lte/lte_diagnostics.dart';
import '../lte/lte_service.dart';
import '../lte/lte_signal.dart';
import '../settings/settings_controller.dart';
import 'theme.dart';
import 'widgets/metric_tile.dart';

class LteScreen extends StatefulWidget {
  const LteScreen({super.key});

  @override
  State<LteScreen> createState() => _LteScreenState();
}

class _LteScreenState extends State<LteScreen> {
  final _controller = LteController();
  final _store = LteCredentialsStore();
  final _host = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _interface = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final saved = await _store.load();
    if (!mounted || saved == null) return;
    setState(() {
      _host.text = saved.host;
      _username.text = saved.username;
      _password.text = saved.password;
      _port.text = saved.port.toString();
      _interface.text = saved.interfaceName ?? '';
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _host.dispose();
    _username.dispose();
    _password.dispose();
    _port.dispose();
    _interface.dispose();
    super.dispose();
  }

  Future<void> _connect(L10n l) async {
    final host = _host.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || username.isEmpty || password.isEmpty || port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t(
            'Enter host, username, password and a valid SSH port.',
            'Укажи адрес, логин, пароль и корректный SSH-порт.',
          )),
        ),
      );
      return;
    }
    final connection = LteConnection(
      host: host,
      username: username,
      password: password,
      port: port,
      interfaceName:
          _interface.text.trim().isEmpty ? null : _interface.text.trim(),
    );
    if (await _controller.connect(connection)) {
      await _store.save(connection);
    }
  }

  Future<void> _forget(L10n l) async {
    await _controller.disconnect();
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _host.clear();
      _username.clear();
      _password.clear();
      _port.text = '22';
      _interface.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.t(
          'Saved LTE profile removed from this device.',
          'Сохранённый LTE-профиль удалён с устройства.',
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final connected = _controller.state == LteMonitorState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('LTE diagnostics', 'LTE-диагностика')),
            Text(
              connected
                  ? '${_host.text} · ${_controller.interfaceName ?? 'LTE'} · SSH'
                  : l.t('Separate from Wi-Fi monitoring',
                      'Отдельно от мониторинга Wi-Fi'),
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF7D8590),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          if (connected)
            IconButton(
              tooltip: l.t('Refresh now', 'Обновить сейчас'),
              icon: const Icon(Icons.refresh),
              onPressed: _controller.refresh,
            ),
          if (connected)
            IconButton(
              tooltip: _controller.isLive
                  ? l.t('Pause', 'Пауза')
                  : l.t('Resume', 'Продолжить'),
              icon: Icon(_controller.isLive ? Icons.pause : Icons.play_arrow),
              onPressed: _controller.isLive
                  ? _controller.stopLive
                  : _controller.startLive,
            ),
          if (connected)
            IconButton(
              tooltip: l.t('Disconnect', 'Отключить'),
              icon: const Icon(Icons.logout),
              onPressed: _controller.disconnect,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_controller.failure != null)
              _LteFailureCard(
                failure: _controller.failure!,
                l: l,
                onRetry: _controller.retry,
              ),
            if (connected)
              _LteDashboard(controller: _controller, l: l)
            else
              _connectionForm(l),
          ],
        ),
      ),
    );
  }

  Widget _connectionForm(L10n l) {
    final busy = _controller.state == LteMonitorState.connecting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cell_tower, color: AppTheme.apAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.t('LTE MikroTik over SSH', 'LTE MikroTik по SSH'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.t(
                'This is an independent tool for a MikroTik with an LTE modem. '
                    'It does not use phone Wi-Fi data and does not change the router.',
                'Это отдельный инструмент для MikroTik с LTE-модемом. Он не '
                    'использует данные Wi-Fi телефона и не меняет роутер.',
              ),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7D8590),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _host,
              enabled: !busy,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Host / IP',
                prefixIcon: Icon(Icons.router_outlined),
                hintText: '192.168.88.1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: l.t('Username', 'Пользователь'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !busy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: l.t('Password', 'Пароль'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _port,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.t('SSH port', 'Порт SSH'),
                      prefixIcon: const Icon(Icons.numbers),
                      hintText: '22',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _interface,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: l.t('LTE interface', 'LTE-интерфейс'),
                      hintText: l.t('auto', 'авто'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l.t(
                'The interface may be left empty. The app selects a running '
                    'LTE interface automatically. Credentials are stored in the device Keystore.',
                'Интерфейс можно не указывать: приложение само выберет работающий '
                    'LTE-интерфейс. Данные входа хранятся в Keystore устройства.',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : () => _connect(l),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cell_tower),
              label: Text(busy
                  ? l.t('Connecting…', 'Подключение…')
                  : l.t('Connect and analyze LTE',
                      'Подключиться и анализировать LTE')),
            ),
            TextButton.icon(
              onPressed: busy ? null : () => _forget(l),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.t('Forget saved LTE profile',
                  'Забыть сохранённый LTE-профиль')),
            ),
            const SizedBox(height: 4),
            Text(
              l.t(
                'Read-only commands: `/interface lte print`, '
                    '`/interface lte monitor … once`, `/system resource print`.',
                'Только чтение: `/interface lte print`, '
                    '`/interface lte monitor … once`, `/system resource print`.',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF565E68)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LteDashboard extends StatelessWidget {
  final LteController controller;
  final L10n l;

  const _LteDashboard({required this.controller, required this.l});

  @override
  Widget build(BuildContext context) {
    final signal = controller.signal;
    if (signal == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final diagnosis = controller.diagnosis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VerdictCard(report: diagnosis, l: l),
        const SizedBox(height: 12),
        _IdentityCard(signal: signal, controller: controller, l: l),
        const SizedBox(height: 12),
        _MetricsCard(signal: signal, l: l),
        const SizedBox(height: 12),
        _RadioCard(signal: signal, l: l),
        if (controller.history.length >= 2) ...[
          const SizedBox(height: 12),
          _StabilityCard(controller: controller, l: l),
        ],
        const SizedBox(height: 12),
        _AdviceCard(report: diagnosis, l: l),
      ],
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final LteDiagnosticReport report;
  final L10n l;

  const _VerdictCard({required this.report, required this.l});

  @override
  Widget build(BuildContext context) {
    final color = _qualityColor(report.quality);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_qualityIcon(report.quality), color: color, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _qualityLabel(l, report.quality).toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  l.t(report.titleEn, report.titleRu),
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.t(report.summaryEn, report.summaryRu),
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final LteSignal signal;
  final LteController controller;
  final L10n l;

  const _IdentityCard({
    required this.signal,
    required this.controller,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final modem = [signal.manufacturer, signal.modemModel]
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .join(' ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.cell_tower, l.t('Connection', 'Подключение')),
            const SizedBox(height: 12),
            _detail(l.t('Operator', 'Оператор'), signal.operatorName),
            _detail(l.t('Technology', 'Технология'), signal.technology),
            _detail(l.t('Modem', 'Модем'), modem.isEmpty ? null : modem),
            _detail(l.t('Router', 'Роутер'), controller.routerBoard),
            _detail('RouterOS', controller.routerVersion),
            _detail(l.t('Session', 'Сессия'), signal.sessionUptime),
            _detail(
              l.t('Status', 'Статус'),
              signal.status ??
                  (signal.registered
                      ? l.t('registered', 'зарегистрирован')
                      : l.t('not registered', 'не зарегистрирован')),
              color: signal.registered
                  ? const Color(0xFF3FB950)
                  : const Color(0xFFF85149),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  final LteSignal signal;
  final L10n l;

  const _MetricsCard({required this.signal, required this.l});

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      MetricTile(
        label: 'RSRP',
        value: _number(signal.rsrp),
        unit: 'dBm',
        color: _qualityColor(LteDiagnostics.rsrpQuality(signal.rsrp)),
        helpKey: 'lte_rsrp',
      ),
      MetricTile(
        label: 'RSRQ',
        value: _number(signal.rsrq),
        unit: 'dB',
        color: _qualityColor(LteDiagnostics.rsrqQuality(signal.rsrq)),
        helpKey: 'lte_rsrq',
      ),
      MetricTile(
        label: 'SINR',
        value: _number(signal.sinr),
        unit: 'dB',
        color: _qualityColor(LteDiagnostics.sinrQuality(signal.sinr)),
        helpKey: 'lte_sinr',
      ),
      if (signal.rssi != null)
        MetricTile(
          label: 'RSSI',
          value: _number(signal.rssi),
          unit: 'dBm',
          color: _qualityColor(LteDiagnostics.rssiQuality(signal.rssi)),
          helpKey: 'lte_rssi',
        ),
      if (signal.cqi != null)
        MetricTile(
          label: 'CQI',
          value: signal.cqi.toString(),
          color: _qualityColor(LteDiagnostics.cqiQuality(signal.cqi)),
          helpKey: 'lte_cqi',
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.signal_cellular_alt,
                l.t('Radio quality', 'Качество радиоканала')),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 18,
                  children: metrics
                      .map((metric) => SizedBox(width: width, child: metric))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              l.t(
                'RSRP is power; RSRQ and SINR describe quality. Do not judge an LTE link by RSSI alone.',
                'RSRP — мощность, RSRQ и SINR — качество. Не оценивай LTE только по RSSI.',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioCard extends StatelessWidget {
  final LteSignal signal;
  final L10n l;

  const _RadioCard({required this.signal, required this.l});

  @override
  Widget build(BuildContext context) {
    final bandwidth = signal.bandwidthMhz == null
        ? null
        : '${_number(signal.bandwidthMhz)} MHz';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.settings_input_antenna,
                l.t('Serving cell', 'Обслуживающая сота')),
            const SizedBox(height: 12),
            _detail(l.t('Band', 'Диапазон'), signal.band),
            _detail(l.t('Channel width', 'Ширина канала'), bandwidth),
            _detail('EARFCN', signal.earfcn?.toString()),
            _detail('PCI', signal.physicalCellId?.toString()),
            _detail('eNodeB', signal.enbId),
            _detail(l.t('Sector', 'Сектор'), signal.sectorId),
            _detail('Cell ID', signal.cellId),
            if (signal.carrierAggregation != null)
              _detail('Carrier aggregation', signal.carrierAggregation),
          ],
        ),
      ),
    );
  }
}

class _StabilityCard extends StatelessWidget {
  final LteController controller;
  final L10n l;

  const _StabilityCard({required this.controller, required this.l});

  @override
  Widget build(BuildContext context) {
    final rows = <({
      String label,
      String unit,
      ({double min, double average, double max})? stats
    })>[
      (label: 'RSRP', unit: 'dBm', stats: controller.stats((s) => s.rsrp)),
      (label: 'RSRQ', unit: 'dB', stats: controller.stats((s) => s.rsrq)),
      (label: 'SINR', unit: 'dB', stats: controller.stats((s) => s.sinr)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              Icons.timeline,
              '${l.t('Stability', 'Стабильность')} · ${controller.history.length}',
            ),
            const SizedBox(height: 12),
            for (final row in rows)
              if (row.stats != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(row.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Text(
                          '${l.t('min', 'мин')} ${_number(row.stats!.min)}  ·  '
                          '${l.t('avg', 'ср')} ${_number(row.stats!.average)}  ·  '
                          '${l.t('max', 'макс')} ${_number(row.stats!.max)} ${row.unit}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFAAB2BD),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            Text(
              l.t(
                'The diagnosis flags an RSRP swing ≥ 8 dB or SINR swing ≥ 10 dB after four samples.',
                'Диагностика отмечает скачок RSRP ≥ 8 dB или SINR ≥ 10 dB после четырёх замеров.',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdviceCard extends StatelessWidget {
  final LteDiagnosticReport report;
  final L10n l;

  const _AdviceCard({required this.report, required this.l});

  @override
  Widget build(BuildContext context) {
    final facts = l.ru ? report.factsRu : report.factsEn;
    final advice = l.ru ? report.adviceRu : report.adviceEn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.troubleshoot,
                l.t('Analysis and advice', 'Анализ и советы')),
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.t('What the numbers say', 'Что говорят цифры'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...facts.map(_bullet),
            ],
            if (advice.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(l.t('What to check', 'Что проверить'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...advice.map(_bullet),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(Icons.circle, size: 5, color: Color(0xFF7D8590)),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
          ],
        ),
      );
}

class _LteFailureCard extends StatelessWidget {
  final AppFailure failure;
  final L10n l;
  final VoidCallback onRetry;

  const _LteFailureCard({
    required this.failure,
    required this.l,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF85149).withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFFF85149).withValues(alpha: 0.38)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF85149)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${failure.title(l)} · ${failure.code}',
                    style: const TextStyle(
                      color: Color(0xFFF85149),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(failure.description(l),
                      style: const TextStyle(fontSize: 12, height: 1.35)),
                  const SizedBox(height: 5),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 17),
                    label: Text(l.t('Retry', 'Повторить')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

Widget _sectionTitle(IconData icon, String title) => Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.apAccent),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );

Widget _detail(String label, String? value, {Color? color}) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7D8590))),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              )),
        ),
      ],
    ),
  );
}

String _number(double? value) {
  if (value == null) return '—';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

Color _qualityColor(LteQuality quality) => switch (quality) {
      LteQuality.excellent => const Color(0xFF3FB950),
      LteQuality.good => const Color(0xFF56D364),
      LteQuality.fair => const Color(0xFFD29922),
      LteQuality.poor => const Color(0xFFF85149),
      LteQuality.unknown => const Color(0xFF7D8590),
    };

IconData _qualityIcon(LteQuality quality) => switch (quality) {
      LteQuality.excellent || LteQuality.good => Icons.check_circle_outline,
      LteQuality.fair => Icons.info_outline,
      LteQuality.poor => Icons.error_outline,
      LteQuality.unknown => Icons.hourglass_empty,
    };

String _qualityLabel(L10n l, LteQuality quality) => switch (quality) {
      LteQuality.excellent => l.t('Excellent', 'Отлично'),
      LteQuality.good => l.t('Good', 'Хорошо'),
      LteQuality.fair => l.t('Attention', 'Внимание'),
      LteQuality.poor => l.t('Poor', 'Плохо'),
      LteQuality.unknown => l.t('No data', 'Нет данных'),
    };
