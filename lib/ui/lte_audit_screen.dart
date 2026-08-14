import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../audit/audit.dart';
import '../audit/audit_pdf.dart';
import '../l10n/l10n.dart';
import '../lte/lte_audit.dart';
import '../lte/lte_controller.dart';
import '../settings/settings_controller.dart';
import 'widgets/audit_widgets.dart';

class LteAuditScreen extends StatefulWidget {
  final LteController controller;

  const LteAuditScreen({super.key, required this.controller});

  @override
  State<LteAuditScreen> createState() => _LteAuditScreenState();
}

class _LteAuditScreenState extends State<LteAuditScreen> {
  LteAuditRole _role = LteAuditRole.general;
  Future<List<Finding>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.runAudit(_role);
  }

  void _run() {
    setState(() => _future = widget.controller.runAudit(_role));
  }

  Future<void> _exportPdf() async {
    final l = context.read<SettingsController>().l;
    final findings = await (_future ?? widget.controller.runAudit(_role));
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
    final subtitle = '${widget.controller.routerBoard ?? 'MikroTik'} · '
        '${widget.controller.interfaceName ?? 'LTE'} · '
        '${_roleLabel(l, _role)} · $date';
    final bytes = await buildAuditPdf(
      findings,
      l: l,
      subtitle: subtitle,
      title: l.t('LTE configuration audit', 'Аудит настроек LTE'),
    );
    await Printing.sharePdf(bytes: bytes, filename: 'lte-audit.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('LTE configuration audit', 'Аудит настроек LTE')),
        actions: [
          IconButton(
            tooltip: l.t('Export PDF', 'Экспорт PDF'),
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: l.t('Re-run', 'Перепроверить'),
            onPressed: _run,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Finding>>(
        future: _future,
        builder: (context, snapshot) {
          final content = <Widget>[
            _RoleCard(
              l: l,
              role: _role,
              onChanged: (value) {
                if (value == null || value == _role) return;
                _role = value;
                _run();
              },
            ),
            const SizedBox(height: 12),
          ];
          if (snapshot.hasError) {
            content.add(_ErrorCard(l: l, onRetry: _run));
          } else if (!snapshot.hasData) {
            content.add(const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            ));
          } else {
            final findings = snapshot.data!;
            final issues = findings
                .where((finding) =>
                    finding.sev == AuditSeverity.critical ||
                    finding.sev == AuditSeverity.warn)
                .length;
            content.addAll([
              AuditSummaryCard(
                l: l,
                issues: issues,
                total: findings.length,
              ),
              const SizedBox(height: 12),
              ...findings.map(
                (finding) => AuditFindingCard(l: l, finding: finding),
              ),
            ]);
          }
          content.addAll([
            const SizedBox(height: 8),
            Text(
              l.t(
                'Read-only static audit. It does not run AT commands, scan cells, inspect APN credentials or change the router.',
                'Статический аудит только для чтения. Он не запускает AT-команды, не сканирует соты, не читает учётные данные APN и не меняет роутер.',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
            ),
          ]);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: content,
          );
        },
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final L10n l;
  final LteAuditRole role;
  final ValueChanged<LteAuditRole?> onChanged;

  const _RoleCard({
    required this.l,
    required this.role,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.t('How is this LTE link used?',
                    'Как используется этот LTE-канал?'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                l.t(
                  'The role only changes route and passthrough advice; it never changes RouterOS.',
                  'Роль влияет только на советы о маршруте и passthrough и ничего не меняет в RouterOS.',
                ),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF7D8590),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LteAuditRole>(
                initialValue: role,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.t('Link role', 'Роль канала'),
                ),
                items: [
                  for (final value in LteAuditRole.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        _roleLabel(l, value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  final L10n l;
  final VoidCallback onRetry;

  const _ErrorCard({required this.l, required this.onRetry});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFF85149)),
              const SizedBox(height: 8),
              Text(l.t('Could not run the LTE audit.',
                  'Не удалось выполнить LTE-аудит.')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l.t('Try again', 'Повторить')),
              ),
            ],
          ),
        ),
      );
}

String _roleLabel(L10n l, LteAuditRole role) => switch (role) {
      LteAuditRole.general =>
        l.t('General / not specified', 'Общий / не задан'),
      LteAuditRole.primary => l.t('Primary Internet link', 'Основной интернет'),
      LteAuditRole.backup => l.t('Backup link', 'Резервный канал'),
      LteAuditRole.passthrough => 'LTE passthrough',
      LteAuditRole.monitor =>
        l.t('Monitoring / alignment only', 'Только мониторинг / юстировка'),
    };
