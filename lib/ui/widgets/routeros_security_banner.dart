import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../routeros_updates/routeros_security.dart';
import '../../services/link_service.dart';

class RouterOsSecurityBanner extends StatelessWidget {
  final L10n l;
  final List<RouterOsSecurityStatus> warnings;
  final bool checking;

  const RouterOsSecurityBanner({
    super.key,
    required this.l,
    required this.warnings,
    this.checking = false,
  });

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final catalogue = warnings.first.catalog;
    final checked = catalogue.checkedAt;
    final source = checked == null
        ? l.t(
            'Bundled catalogue · 2026-09-03',
            'Встроенный каталог · 03.09.2026',
          )
        : l.t(
            'Official page checked ${_date(checked)}',
            'Официальная страница проверена ${_date(checked)}',
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFD29922).withValues(alpha: 0.12),
        border: Border.all(
          color: const Color(0xFFD29922).withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.security_update_warning_outlined,
                color: Color(0xFFD29922),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t(
                        'Important RouterOS security update',
                        'Важное обновление безопасности RouterOS',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${warning.host}: ${warning.installedVersion} → '
                          '≥ ${warning.fixedVersion}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (checking)
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 2),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            l.t(
              'MikroTik says most configurations are not at immediate risk, '
                  'but highly recommends upgrading. This is a vendor '
                  'recommendation, not a claim that this router was compromised.',
              'MikroTik пишет, что большинству конфигураций ничего не угрожает '
                  'немедленно, но настоятельно рекомендует обновиться. Это '
                  'рекомендация производителя, а не утверждение о взломе роутера.',
            ),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFAAB2BD),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  source,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF7D8590),
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: () => openExternalLink(
                  context,
                  RouterOsSecurityCatalog.sourceUrl,
                  copiedLabel: l.t(
                    'MikroTik security link copied',
                    'Ссылка на бюллетень MikroTik скопирована',
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(l.t('Details', 'Подробнее')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}
