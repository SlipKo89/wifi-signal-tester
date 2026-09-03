import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'widgets/app_safe_area.dart';
import 'zabbix_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final monitor = context.read<MonitorController>();
    final l = s.l;

    void applyToMonitor() => monitor.applySettings(
          pollSeconds: s.pollSeconds,
          healthPollSeconds: s.healthPollSeconds,
          identityPollSeconds: s.identityPollSeconds,
          historyLength: s.historyLength,
          alertsEnabled: s.alertsEnabled,
          alertThresholdDb: s.alertThresholdDb,
          minSignalDbm: s.minSignalDbm,
          minSnrDb: s.minSnrDb,
          autoLinkDiagnostics: s.autoLinkDiagnostics,
          linkDiagnosticDelaySeconds: s.linkDiagnosticDelaySeconds,
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.t('Settings', 'Настройки'))),
      body: AppSafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(l.t('Language', 'Язык')),
            _langTile(context, s, 'system', l.t('System', 'Системный')),
            _langTile(context, s, 'en', 'English'),
            _langTile(context, s, 'ru', 'Русский'),
            const SizedBox(height: 20),
            _section(l.t('Monitoring', 'Мониторинг')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.t('Polling profile', 'Профиль опроса')),
              subtitle: Text(
                l.t(
                  'Signal ${_period(s.pollSeconds, false)}, router health ${_period(s.healthPollSeconds, false)}, client discovery ${_period(s.identityPollSeconds, false)}',
                  'Сигнал ${_period(s.pollSeconds, true)}, состояние роутера ${_period(s.healthPollSeconds, true)}, поиск клиента ${_period(s.identityPollSeconds, true)}',
                ),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: DropdownButton<PollingProfile>(
                value: s.pollingProfile,
                underline: const SizedBox.shrink(),
                items: [
                  for (final profile in PollingProfile.values)
                    DropdownMenuItem(
                      value: profile,
                      child: Text(_profileName(profile, l.ru)),
                    ),
                ],
                onChanged: (profile) async {
                  if (profile == null) return;
                  await s.setPollingProfile(profile);
                  applyToMonitor();
                },
              ),
            ),
            if (s.pollingProfile == PollingProfile.custom) ...[
              _sliderTile(
                title: l.t('Signal and ping', 'Сигнал и ping'),
                value: s.pollSeconds.toDouble(),
                min: 1,
                max: 30,
                label: _period(s.pollSeconds, l.ru),
                onChanged: (v) => s.setPollSeconds(v.round()),
                onDone: applyToMonitor,
              ),
              _sliderTile(
                title: l.t('Router health / CPU', 'Состояние роутера / CPU'),
                value: s.healthPollSeconds.toDouble(),
                min: 5,
                max: 300,
                divisions: 59,
                label: _period(s.healthPollSeconds, l.ru),
                onChanged: (v) => s.setHealthPollSeconds((v / 5).round() * 5),
                onDone: applyToMonitor,
              ),
              _sliderTile(
                title: l.t('IP → MAC discovery', 'Поиск IP → MAC'),
                value: s.identityPollSeconds.toDouble(),
                min: 10,
                max: 600,
                divisions: 59,
                label: _period(s.identityPollSeconds, l.ru),
                onChanged: (v) =>
                    s.setIdentityPollSeconds((v / 10).round() * 10),
                onDone: applyToMonitor,
              ),
            ],
            _sliderTile(
              title: l.t('Chart history length', 'Длина графика'),
              value: s.historyLength.toDouble(),
              min: 20,
              max: 240,
              divisions: 11,
              label: '${s.historyLength} ${l.t('points', 'точек')}',
              onChanged: (v) => s.setHistoryLength((v / 20).round() * 20),
              onDone: applyToMonitor,
            ),
            const SizedBox(height: 20),
            _section(l.t('Connection diagnosis', 'Диагностика соединения')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.t('Run automatically after connect or roam',
                  'Автозапуск после подключения или роуминга')),
              subtitle: Text(
                l.t('Waits for the radio link to settle before collecting a fixed result. Manual start is always available on the dashboard.',
                    'Ждёт стабилизации радиоканала и затем фиксирует результат. Ручной запуск всегда доступен на дашборде.'),
                style: const TextStyle(fontSize: 12),
              ),
              value: s.autoLinkDiagnostics,
              onChanged: (v) {
                s.setAutoLinkDiagnostics(v);
                applyToMonitor();
              },
            ),
            if (s.autoLinkDiagnostics)
              _sliderTile(
                title: l.t('Link settling delay', 'Пауза на стабилизацию'),
                value: s.linkDiagnosticDelaySeconds.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: '${s.linkDiagnosticDelaySeconds} ${l.t('sec', 'сек')}',
                onChanged: (v) => s.setLinkDiagnosticDelaySeconds(v.round()),
                onDone: applyToMonitor,
              ),
            const SizedBox(height: 20),
            _section(l.t('Targets', 'Целевые значения')),
            _sliderTile(
              title: l.t('Minimum signal', 'Минимальный сигнал'),
              value: s.minSignalDbm.toDouble(),
              min: -90,
              max: -40,
              label: '${s.minSignalDbm} dBm',
              onChanged: (v) => s.setMinSignalDbm(v.round()),
              onDone: applyToMonitor,
            ),
            _sliderTile(
              title: l.t('Minimum SNR', 'Минимальный SNR'),
              value: s.minSnrDb.toDouble(),
              min: 5,
              max: 40,
              label: '${s.minSnrDb} dB',
              onChanged: (v) => s.setMinSnrDb(v.round()),
              onDone: applyToMonitor,
            ),
            const SizedBox(height: 20),
            _section(l.t('Alerts', 'Оповещения')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.t('Beep when out of target',
                  'Бип при выходе за целевые значения')),
              subtitle: Text(
                l.t('Sounds when signal, SNR or asymmetry is out of target',
                    'Звук, когда сигнал, SNR или асимметрия вне цели'),
                style: const TextStyle(fontSize: 12),
              ),
              value: s.alertsEnabled,
              onChanged: (v) {
                s.setAlertsEnabled(v);
                applyToMonitor();
              },
            ),
            if (s.alertsEnabled)
              _sliderTile(
                title: l.t('Asymmetry threshold', 'Порог асимметрии'),
                value: s.alertThresholdDb.toDouble(),
                min: 4,
                max: 30,
                label: '${s.alertThresholdDb} dB',
                onChanged: (v) => s.setAlertThresholdDb(v.round()),
                onDone: applyToMonitor,
              ),
            const SizedBox(height: 20),
            _section(l.t('Integrations', 'Интеграции')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Zabbix'),
              subtitle: Text(
                l.t(
                  'Read historical metrics with your API token',
                  'Чтение истории метрик по API-токену',
                ),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ZabbixScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7D8590))),
      );

  static String _profileName(PollingProfile profile, bool ru) =>
      switch (profile) {
        PollingProfile.fast => ru ? 'Быстрый' : 'Fast',
        PollingProfile.normal => ru ? 'Обычный' : 'Normal',
        PollingProfile.economical => ru ? 'Экономичный' : 'Economical',
        PollingProfile.custom => ru ? 'Свой' : 'Custom',
      };

  static String _period(int seconds, bool ru) {
    if (seconds >= 60 && seconds % 60 == 0) {
      final minutes = seconds ~/ 60;
      return ru ? '$minutes мин' : '$minutes min';
    }
    return ru ? '$seconds сек' : '$seconds sec';
  }

  Widget _langTile(
      BuildContext context, SettingsController s, String code, String label) {
    final selected = s.lang == code;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () => s.setLang(code),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
    );
  }

  Widget _sliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String label,
    required ValueChanged<double> onChanged,
    required VoidCallback onDone,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              Text(label,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF7D8590))),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions ?? (max - min).round(),
          onChanged: onChanged,
          onChangeEnd: (_) => onDone(),
        ),
      ],
    );
  }
}
