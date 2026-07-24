import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../release_notes.dart';
import '../settings/settings_controller.dart';
import 'theme.dart';

/// Shows the "What's new" popup for [release] once (e.g. after an update).
void showWhatsNew(BuildContext context, Release release) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Builder(builder: (context) {
          final l = context.watch<SettingsController>().l;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('${l.t("What's new", 'Что нового')} · v${release.version}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: _Highlights(release: release),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.t('Got it', 'Понятно')),
                ),
              ),
            ],
          );
        }),
      ),
    ),
  );
}

/// If the app was updated since the user last saw the notes, show them once.
void maybeShowWhatsNew(BuildContext context, SettingsController settings) {
  final seen = settings.lastSeenVersion;
  if (seen == kAppVersion) return;
  // Persist immediately so it only shows once.
  settings.setLastSeenVersion(kAppVersion);
  // Skip on a fresh install (nothing seen yet) — only announce real updates.
  if (seen.isEmpty) return;
  Release? release;
  for (final r in kReleases) {
    if (r.version == kAppVersion) {
      release = r;
      break;
    }
  }
  if (release == null) return;
  final found = release;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) showWhatsNew(context, found);
  });
}

class _Highlights extends StatelessWidget {
  final Release release;
  const _Highlights({required this.release});

  @override
  Widget build(BuildContext context) {
    final ru = context.watch<SettingsController>().l.ru;
    final items = ru ? release.ru : release.en;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_outline,
                      size: 15, color: AppTheme.phoneAccent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item,
                      style: const TextStyle(fontSize: 13, height: 1.35)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Full in-app changelog: every release with its highlights.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('Changelog', 'История версий'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final r in kReleases)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('v${r.version}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Text(r.date,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF7D8590))),
                        if (r.version == kAppVersion) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(l.t('installed', 'установлено'),
                                style: const TextStyle(
                                    fontSize: 10, color: AppTheme.accent)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Highlights(release: r),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
