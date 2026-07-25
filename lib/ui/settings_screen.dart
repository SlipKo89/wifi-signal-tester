import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final monitor = context.read<MonitorController>();
    final l = s.l;

    void applyToMonitor() => monitor.applySettings(
          pollSeconds: s.pollSeconds,
          historyLength: s.historyLength,
          alertsEnabled: s.alertsEnabled,
          alertThresholdDb: s.alertThresholdDb,
          minSignalDbm: s.minSignalDbm,
          minSnrDb: s.minSnrDb,
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.t('Settings', 'Настройки'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(l.t('Language', 'Язык')),
          _langTile(context, s, 'system', l.t('System', 'Системный')),
          _langTile(context, s, 'en', 'English'),
          _langTile(context, s, 'ru', 'Русский'),
          const SizedBox(height: 20),
          _section(l.t('Monitoring', 'Мониторинг')),
          _sliderTile(
            title: l.t('Poll interval', 'Интервал опроса'),
            value: s.pollSeconds.toDouble(),
            min: 1,
            max: 10,
            label: '${s.pollSeconds} ${l.t('sec', 'сек')}',
            onChanged: (v) => s.setPollSeconds(v.round()),
            onDone: applyToMonitor,
          ),
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
        ],
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
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF7D8590))),
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
