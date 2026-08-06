import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../diagnostics/support_bundle.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';

class SupportDiagnosticsScreen extends StatefulWidget {
  const SupportDiagnosticsScreen({super.key});

  @override
  State<SupportDiagnosticsScreen> createState() =>
      _SupportDiagnosticsScreenState();
}

class _SupportDiagnosticsScreenState extends State<SupportDiagnosticsScreen> {
  bool _includeIdentifiers = false;
  bool _busy = false;

  Future<SupportBundleBuilder> _build() async {
    final settings = context.read<SettingsController>();
    final snapshot = await context
        .read<MonitorController>()
        .createSupportSnapshot(locale: settings.l.ru ? 'ru' : 'en');
    return SupportBundleBuilder(
      snapshot: snapshot,
      includeNetworkIdentifiers: _includeIdentifiers,
    );
  }

  Future<void> _copy() async {
    setState(() => _busy = true);
    try {
      final report = await _build();
      await Clipboard.setData(ClipboardData(text: report.renderText()));
      if (!mounted) return;
      final l = context.read<SettingsController>().l;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t(
          'Readable report copied to the clipboard',
          'Читаемый отчёт скопирован в буфер обмена',
        )),
      ));
      context.read<MonitorController>().diagnosticLog.record(
        'SUPPORT-COPIED',
        'Readable support report copied by user',
        details: {'network_identifiers': _includeIdentifiers},
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final report = await _build();
      final file = await report.writeToTemporaryDirectory();
      if (!mounted) return;
      final l = context.read<SettingsController>().l;
      context.read<MonitorController>().diagnosticLog.record(
        'SUPPORT-ARCHIVE',
        'Support archive created by user',
        details: {'network_identifiers': _includeIdentifiers},
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Wi-Fi Signal Tester support report',
        text: l.t(
          'Support archive created by Wi-Fi Signal Tester',
          'Диагностический архив Wi-Fi Signal Tester',
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    final ctrl = context.read<MonitorController>();
    ctrl.diagnosticLog.record(
      'SUPPORT-EXPORT-FAILED',
      'Support report export failed',
      details: {'technical': error.toString()},
    );
    if (!mounted) return;
    final l = context.read<SettingsController>().l;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.t(
        'Could not create the report. Try again.',
        'Не удалось создать отчёт. Попробуй ещё раз.',
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MonitorController>();
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Support report', 'Отчёт в поддержку')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.privacy_tip_outlined),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l.t('Created locally, sent only by you',
                              'Создаётся локально, отправляешь только ты'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.t(
                      'The app does not upload telemetry. The archive is built '
                          'only after you press Share. Review report.txt before '
                          'sending it to the developer.',
                      'Приложение не загружает телеметрию. Архив создаётся '
                          'только после нажатия «Поделиться». Перед отправкой '
                          'разработчику можно проверить report.txt.',
                    ),
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.t(
                      'Passwords, tokens, private keys, raw RouterOS responses '
                          'and full lists of other clients are never included.',
                      'Пароли, токены, приватные ключи, сырые ответы RouterOS и '
                          'полные списки чужих клиентов не включаются никогда.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7D8590),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _includeIdentifiers,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _includeIdentifiers = value),
                  title: Text(l.t(
                    'Include network identifiers',
                    'Включить сетевые идентификаторы',
                  )),
                  subtitle: Text(l.t(
                    'Off by default. When off, SSID, BSSID, MAC, router/AP '
                        'names and IP addresses are masked.',
                    'По умолчанию выключено. SSID, BSSID, MAC, имена роутеров/'
                        'точек и IP-адреса маскируются.',
                  )),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(l.t('Archive contents', 'Содержимое архива')),
                  subtitle: const Text(
                    'report.txt · report.json · events.log · README.txt',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: Text(l.t('Diagnostic events', 'События диагностики')),
                  trailing: Text('${ctrl.diagnosticLog.events.length}/200'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
            label: Text(l.t('Create and share ZIP', 'Создать и отправить ZIP')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _copy,
            icon: const Icon(Icons.copy_outlined),
            label: Text(l.t('Copy readable report', 'Копировать отчёт')),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: ctrl.diagnosticLog.events.isEmpty || _busy
                ? null
                : ctrl.clearDiagnosticLog,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(l.t(
              'Clear in-memory event log',
              'Очистить журнал событий в памяти',
            )),
          ),
        ],
      ),
    );
  }
}
