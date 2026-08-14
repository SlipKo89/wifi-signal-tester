import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../audit/audit.dart';
import '../audit/audit_pdf.dart';
import '../audit/phone_audit.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'widgets/audit_widgets.dart';

class AuditScreen extends StatefulWidget {
  /// When true, audits the phone's own view instead of the routers.
  final bool phone;

  /// For router audits: which slice of checks (Wi-Fi vs system).
  final AuditScope? scope;

  const AuditScreen({super.key, this.phone = false, this.scope});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  Future<List<Finding>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _run();
  }

  Future<List<Finding>> _run() {
    final ctrl = context.read<MonitorController>();
    if (widget.phone) return Future.value(PhoneAudit().run(ctrl.phoneSignal));
    return AuditEngine()
        .run(ctrl.routers, scope: widget.scope ?? AuditScope.wifi);
  }

  Future<void> _exportPdf() async {
    final ctrl = context.read<MonitorController>();
    final l = context.read<SettingsController>().l;
    final findings = await (_future ?? _run());
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
    final subtitle = widget.phone
        ? '${l.t('Device', 'Устройство')}: '
            '${ctrl.phoneSignal?.ssid ?? '—'} • $date'
        : '${l.t('Routers', 'Роутеры')}: '
            '${ctrl.routers.map((r) => r.host ?? '?').join(', ')} • $date';
    final title = widget.phone
        ? l.t('Network audit (phone)', 'Аудит сети (телефон)')
        : widget.scope == AuditScope.system
            ? l.t('System audit', 'Системный аудит')
            : l.t('Wi-Fi configuration audit', 'Аудит настроек Wi-Fi');
    final bytes = await buildAuditPdf(
      findings,
      l: l,
      subtitle: subtitle,
      title: title,
    );
    final file = widget.phone
        ? 'phone-audit.pdf'
        : widget.scope == AuditScope.system
            ? 'system-audit.pdf'
            : 'wifi-audit.pdf';
    await Printing.sharePdf(bytes: bytes, filename: file);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.phone
            ? l.t('Network audit (phone)', 'Аудит сети (телефон)')
            : widget.scope == AuditScope.system
                ? l.t('System audit', 'Системный аудит')
                : l.t('Wi-Fi audit', 'Аудит Wi-Fi')),
        actions: [
          IconButton(
            tooltip: l.t('Export PDF', 'Экспорт PDF'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportPdf,
          ),
          IconButton(
            tooltip: l.t('Re-run', 'Перепроверить'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _run()),
          ),
        ],
      ),
      body: FutureBuilder<List<Finding>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final findings = snap.data!;
          final issues = findings
              .where((f) =>
                  f.sev == AuditSeverity.critical ||
                  f.sev == AuditSeverity.warn)
              .length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AuditSummaryCard(l: l, issues: issues, total: findings.length),
              const SizedBox(height: 12),
              ...findings.map((f) => AuditFindingCard(l: l, finding: f)),
              const SizedBox(height: 8),
              Text(
                widget.phone
                    ? l.t(
                        'Read-only — based on what your phone reports about the '
                            'connection.',
                        'Только чтение — по данным, которые телефон сообщает о '
                            'подключении.')
                    : l.t(
                        'Read-only — the app never changes your router. Apply '
                            'fixes yourself in WinBox/WebFig.',
                        'Только чтение — приложение ничего не меняет. Правки '
                            'вноси сам в WinBox/WebFig.'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
              ),
            ],
          );
        },
      ),
    );
  }
}
