import 'package:flutter/material.dart';

import '../../audit/audit.dart';
import '../../l10n/l10n.dart';
import '../../services/link_service.dart';

class AuditSummaryCard extends StatelessWidget {
  final L10n l;
  final int issues;
  final int total;

  const AuditSummaryCard({
    super.key,
    required this.l,
    required this.issues,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ok = issues == 0;
    final color = ok ? const Color(0xFF3FB950) : const Color(0xFFD29922);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.report_problem, color: color),
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
}

class AuditFindingCard extends StatelessWidget {
  final L10n l;
  final Finding finding;

  const AuditFindingCard({
    super.key,
    required this.l,
    required this.finding,
  });

  @override
  Widget build(BuildContext context) {
    final f = finding;
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
                  child: Text(
                    l.t(f.titleEn, f.titleRu),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (f.where != null)
                  Flexible(
                    child: Text(
                      f.where!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7D8590),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l.t(f.detailEn, f.detailRu),
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFAAB2BD),
                height: 1.35,
              ),
            ),
            if (f.fixEn != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.build_outlined,
                    size: 14,
                    color: Color(0xFF3FB950),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.t(f.fixEn!, f.fixRu!),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF9DD5A6),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (f.sourceUrl != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => openExternalLink(
                    context,
                    f.sourceUrl!,
                    copiedLabel: l.t(
                      'MikroTik documentation link copied',
                      'Ссылка на документацию MikroTik скопирована',
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(
                    l.t('MikroTik recommendation', 'Рекомендация MikroTik'),
                    style: const TextStyle(fontSize: 12),
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
