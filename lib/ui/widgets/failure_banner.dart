import 'package:flutter/material.dart';

import '../../diagnostics/app_failure.dart';
import '../../l10n/l10n.dart';

class FailureBanner extends StatelessWidget {
  final AppFailure failure;
  final L10n l;
  final VoidCallback? onRetry;
  final VoidCallback? onEditConnection;
  final VoidCallback? onSystemSettings;
  final Future<void> Function()? onTrustHostKey;
  final VoidCallback onDiagnostics;
  final VoidCallback onDismiss;

  const FailureBanner({
    super.key,
    required this.failure,
    required this.l,
    required this.onDiagnostics,
    required this.onDismiss,
    this.onRetry,
    this.onEditConnection,
    this.onSystemSettings,
    this.onTrustHostKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (failure.severity) {
      AppFailureSeverity.info => const Color(0xFF58A6FF),
      AppFailureSeverity.warning => const Color(0xFFD29922),
      AppFailureSeverity.error => const Color(0xFFF85149),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${failure.title(l)} · ${failure.code}',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failure.description(l),
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                    if (failure.userDetail(l) case final detail?) ...[
                      const SizedBox(height: 7),
                      SelectableText(
                        detail,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l.t('Dismiss', 'Скрыть'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: Text(l.t('Retry', 'Повторить')),
                ),
              if (onEditConnection != null)
                TextButton.icon(
                  onPressed: onEditConnection,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(l.t('Edit connection', 'Изменить подключение')),
                ),
              if (onSystemSettings != null)
                TextButton.icon(
                  onPressed: onSystemSettings,
                  icon: const Icon(Icons.settings_outlined, size: 17),
                  label: Text(l.t('System settings', 'Настройки Android')),
                ),
              if (onTrustHostKey != null)
                TextButton.icon(
                  onPressed: onTrustHostKey,
                  icon: const Icon(Icons.verified_user_outlined, size: 17),
                  label: Text(l.t(
                    'Trust new SSH key',
                    'Доверять новому SSH-ключу',
                  )),
                ),
              TextButton.icon(
                onPressed: onDiagnostics,
                icon: const Icon(Icons.bug_report_outlined, size: 17),
                label: Text(l.t('Support report', 'Отчёт в поддержку')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
