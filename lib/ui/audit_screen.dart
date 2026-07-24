import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../audit/audit.dart';
import '../audit/audit_pdf.dart';
import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import '../state/monitor_controller.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

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

  Future<List<Finding>> _run() =>
      AuditEngine().run(context.read<MonitorController>().routers);

  Future<void> _exportPdf() async {
    final ctrl = context.read<MonitorController>();
    final l = context.read<SettingsController>().l;
    final findings = await (_future ?? _run());
    final hosts = ctrl.routers.map((r) => r.host ?? '?').join(', ');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
    final bytes = await buildAuditPdf(findings,
        l: l, subtitle: '${l.t('Routers', 'Роутеры')}: $hosts • $date');
    await Printing.sharePdf(bytes: bytes, filename: 'wifi-audit.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Config audit', 'Аудит настроек')),
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
          final issues =
              findings.where((f) => f.sev != AuditSeverity.ok).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summary(l, issues, findings.length),
              const SizedBox(height: 12),
              ...findings.map((f) => _card(l, f)),
              const SizedBox(height: 8),
              Text(
                l.t(
                    'Read-only — the app never changes your router. Apply fixes '
                        'yourself in WinBox/WebFig.',
                    'Только чтение — приложение ничего не меняет. Правки вноси '
                        'сам в WinBox/WebFig.'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(L10n l, int issues, int total) {
    final ok = issues == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (ok ? const Color(0xFF3FB950) : const Color(0xFFD29922))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.report_problem,
              color: ok ? const Color(0xFF3FB950) : const Color(0xFFD29922)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? l.t('No issues found. $total checks passed.',
                      'Проблем не найдено. Проверок пройдено: $total.')
                  : l.t('$issues issue(s) to review.',
                      'Найдено проблем: $issues.'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(L10n l, Finding f) {
    final (color, icon) = switch (f.sev) {
      AuditSeverity.critical => (const Color(0xFFF85149), Icons.error),
      AuditSeverity.warn => (const Color(0xFFD29922), Icons.warning_amber),
      AuditSeverity.info => (const Color(0xFF2F81F7), Icons.info_outline),
      AuditSeverity.ok => (const Color(0xFF3FB950), Icons.check_circle_outline),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t(f.titleEn, f.titleRu),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (f.where != null)
                  Text(f.where!,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF7D8590))),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.t(f.detailEn, f.detailRu),
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFFAAB2BD), height: 1.35)),
            if (f.fixEn != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.build_outlined,
                      size: 14, color: Color(0xFF3FB950)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.t(f.fixEn!, f.fixRu!),
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF9DD5A6),
                            height: 1.35)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
