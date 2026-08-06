import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser. If no browser answers (a stripped-down device,
/// a work profile without one), the address is copied to the clipboard instead
/// so the link is never a dead end.
Future<void> openExternalLink(
  BuildContext context,
  String url, {
  String? copiedLabel,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened) return;

  await Clipboard.setData(ClipboardData(text: url));
  messenger?.showSnackBar(
    SnackBar(
      content: Text(copiedLabel ?? 'Link copied: $url'),
      duration: const Duration(seconds: 3),
    ),
  );
}
