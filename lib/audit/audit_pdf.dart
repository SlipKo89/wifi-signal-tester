import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/l10n.dart';
import 'audit.dart';

/// Renders the audit findings as a shareable PDF report.
Future<Uint8List> buildAuditPdf(
  List<Finding> findings, {
  required L10n l,
  required String subtitle,
}) async {
  final reg =
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final doc =
      pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));

  final issues = findings.where((f) => f.sev != AuditSeverity.ok).length;

  PdfColor color(AuditSeverity s) => switch (s) {
        AuditSeverity.critical => PdfColors.red700,
        AuditSeverity.warn => PdfColors.orange800,
        AuditSeverity.info => PdfColors.blue700,
        AuditSeverity.ok => PdfColors.green700,
      };
  String label(AuditSeverity s) => switch (s) {
        AuditSeverity.critical => l.t('CRITICAL', 'КРИТИЧНО'),
        AuditSeverity.warn => l.t('WARNING', 'ВНИМАНИЕ'),
        AuditSeverity.info => l.t('INFO', 'ИНФО'),
        AuditSeverity.ok => 'OK',
      };

  pw.Widget card(Finding f) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: color(f.sev),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(label(f.sev),
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 8,
                          font: bold)),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Text(l.t(f.titleEn, f.titleRu),
                      style: pw.TextStyle(font: bold, fontSize: 11)),
                ),
                if (f.where != null)
                  pw.Text(f.where!,
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(l.t(f.detailEn, f.detailRu),
                style: const pw.TextStyle(fontSize: 9.5)),
            if (f.fixEn != null) ...[
              pw.SizedBox(height: 3),
              pw.Text('→ ${l.t(f.fixEn!, f.fixRu!)}',
                  style: const pw.TextStyle(
                      fontSize: 9.5, color: PdfColors.green800)),
            ],
          ],
        ),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (context) => [
      pw.Text(l.t('Wi-Fi configuration audit', 'Аудит настроек Wi-Fi'),
          style: pw.TextStyle(font: bold, fontSize: 20)),
      pw.SizedBox(height: 3),
      pw.Text(subtitle,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 12),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: issues == 0 ? PdfColors.green50 : PdfColors.orange50,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          issues == 0
              ? l.t('No issues found.', 'Проблем не найдено.')
              : l.t('$issues issue(s) to review.', 'Найдено проблем: $issues.'),
          style: pw.TextStyle(font: bold, fontSize: 12),
        ),
      ),
      pw.SizedBox(height: 14),
      ...findings.map(card),
      pw.SizedBox(height: 10),
      pw.Text(
          l.t('Read-only report — apply fixes yourself in WinBox/WebFig.',
              'Отчёт только для чтения — правки вноси сам в WinBox/WebFig.'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ],
  ));

  return doc.save();
}
