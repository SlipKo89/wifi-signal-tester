import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import 'theme.dart';

/// Opens the About dialog.
void showAboutSheet(BuildContext context) {
  showDialog<void>(context: context, builder: (_) => const _AboutDialog());
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kAppName,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      Text('v$kAppVersion',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF7D8590))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              kAppTagline,
              style: TextStyle(fontSize: 13, color: Color(0xFFAAB2BD)),
            ),
            const SizedBox(height: 6),
            const Text(
              'See how the access point hears your device, not just how your '
              'device hears the access point. Read-only, for your MAC only.',
              style: TextStyle(fontSize: 12, color: Color(0xFF7D8590)),
            ),
            const Divider(height: 28, color: Color(0xFF232B36)),
            const Text('AUTHOR',
                style: TextStyle(
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
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
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
