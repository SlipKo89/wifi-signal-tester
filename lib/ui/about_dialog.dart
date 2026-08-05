import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../services/link_service.dart';
import '../settings/settings_controller.dart';
import 'theme.dart';

/// Opens the About dialog.
void showAboutSheet(BuildContext context) {
  showDialog<void>(context: context, builder: (_) => const _AboutDialog());
}

class _AboutDialog extends StatefulWidget {
  const _AboutDialog();

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  int _taps = 0;

  void _tapVersion() {
    _taps++;
    if (_taps >= 7) {
      _taps = 0;
      HapticFeedback.mediumImpact();
      _showEgg();
    }
  }

  void _showEgg() {
    final l = context.read<SettingsController>().l;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l.t('73! 📡', '73! 📡')),
        content: Text(
          l.t(
              '»)) ))) • ((( (( — may your SNR be high and your delta near '
                  'zero. Made by SlipKo & an AI, over many dBm.',
              '»)) ))) • ((( (( — пусть SNR будет высоким, а дельта — около '
                  'нуля. Сделано SlipKo и ИИ, на многих dBm.'),
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.t('Nice', 'Круто')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        // Scrollable: with the project links the dialog is taller than a small
        // phone in landscape.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.wifi_find,
                      color: AppTheme.accent, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(kAppName,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      // Tap 7× for an easter egg.
                      GestureDetector(
                        onTap: _tapVersion,
                        behavior: HitTestBehavior.opaque,
                        child: const Text('v$kAppVersion',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF7D8590))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l.t(kAppTagline, 'Двусторонний тестер Wi-Fi для MikroTik'),
              style: const TextStyle(fontSize: 13, color: Color(0xFFAAB2BD)),
            ),
            const SizedBox(height: 6),
            Text(
              l.t(
                  'See how the access point hears your device, not just how '
                      'your device hears the access point. Read-only, for your '
                      'MAC only.',
                  'Видно, как точка слышит твоё устройство, а не только как '
                      'устройство слышит точку. Только чтение, только по твоему '
                      'MAC.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF7D8590)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined,
                    size: 13, color: Color(0xFF7D8590)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.t('Built with Claude (AI): code, docs and design.',
                        'Собрано с Claude (ИИ): код, документация и дизайн.'),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF7D8590)),
                  ),
                ),
              ],
            ),
            const Divider(height: 28, color: Color(0xFF232B36)),
            Text(l.t('PROJECT', 'ПРОЕКТ'),
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: Color(0xFF7D8590),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const _LinkRow(
              icon: Icons.code,
              label: 'github.com/SlipKo89/wifi-signal-tester',
              url: kRepoUrl,
            ),
            _LinkRow(
              icon: Icons.menu_book_outlined,
              label: l.t('How to use the app', 'Как пользоваться приложением'),
              url: usageUrl(ru: l.ru),
            ),
            _LinkRow(
              icon: Icons.download_outlined,
              label: l.t('Latest release (APK)', 'Свежий релиз (APK)'),
              url: kReleasesUrl,
            ),
            const Divider(height: 28, color: Color(0xFF232B36)),
            Text(l.t('AUTHOR', 'АВТОР'),
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: Color(0xFF7D8590),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(kAuthor,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const _ContactRow(
              icon: Icons.mail_outline,
              label: kAuthorEmail,
              copyText: kAuthorEmail,
            ),
            const SizedBox(height: 8),
            const _ContactRow(
              icon: Icons.send,
              label: 'Telegram $kAuthorTelegram',
              copyText: kAuthorTelegram,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: kAppName,
                    applicationVersion: 'v$kAppVersion',
                    applicationLegalese: '© 2026 SlipKo · MIT',
                  ),
                  child: Text(l.t('Licenses', 'Лицензии')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.t('Close', 'Закрыть')),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// A row that opens [url] in a browser; long-press copies it instead.
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.read<SettingsController>().l;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openExternalLink(context, url,
          copiedLabel: l.t('Link copied: $url', 'Ссылка скопирована: $url')),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.t('Link copied', 'Ссылка скопирована')),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            const Icon(Icons.open_in_new, size: 14, color: Color(0xFF7D8590)),
          ],
        ),
      ),
    );
  }
}

/// A contact line that copies its value to the clipboard on tap.
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String copyText;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.copyText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: copyText));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied: $copyText'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13)),
            ),
            const Icon(Icons.copy, size: 14, color: Color(0xFF7D8590)),
          ],
        ),
      ),
    );
  }
}
