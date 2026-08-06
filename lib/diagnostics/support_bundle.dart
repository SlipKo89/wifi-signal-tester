import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostic_log.dart';
import 'support_redactor.dart';

class SupportSnapshot {
  final DateTime createdAt;
  final Map<String, Object?> report;
  final List<DiagnosticEvent> events;

  const SupportSnapshot({
    required this.createdAt,
    required this.report,
    required this.events,
  });
}

/// Produces a local support bundle. It never uploads or sends it: sharing is a
/// separate, explicit user action in the UI.
class SupportBundleBuilder {
  final SupportSnapshot snapshot;
  final SupportRedactor redactor;

  SupportBundleBuilder({
    required this.snapshot,
    required bool includeNetworkIdentifiers,
  }) : redactor = SupportRedactor(
          includeNetworkIdentifiers: includeNetworkIdentifiers,
          networkIdentifiers: _networkIdentifiers(snapshot.report),
        );

  Map<String, Object?> get sanitizedReport {
    final report = <String, Object?>{
      'generated_at': snapshot.createdAt.toUtc().toIso8601String(),
      'privacy': {
        'network_identifiers_included': redactor.includeNetworkIdentifiers,
        'credentials_included': false,
        'automatic_upload': false,
      },
      ...snapshot.report,
    };
    return redactor.map(report);
  }

  List<Map<String, Object?>> get sanitizedEvents => snapshot.events
      .map((event) => redactor.map(event.toJson()))
      .toList(growable: false);

  String renderJson() => const JsonEncoder.withIndent('  ').convert({
        ...sanitizedReport,
        'events': sanitizedEvents,
      });

  String renderText() {
    final out = StringBuffer()
      ..writeln('Wi-Fi Signal Tester — support report')
      ..writeln('Generated: ${snapshot.createdAt.toLocal().toIso8601String()}')
      ..writeln('This report was created locally and was not uploaded.')
      ..writeln('Credentials and private keys are never included.');
    _writeMap(out, sanitizedReport, 0);
    out
      ..writeln()
      ..writeln('EVENTS (${sanitizedEvents.length})');
    for (final event in sanitizedEvents) {
      out.writeln(_eventLine(event));
    }
    return out.toString();
  }

  String renderEventLog() => sanitizedEvents.map(_eventLine).join('\n');

  Uint8List archiveBytes() {
    final archive = Archive()
      ..addFile(ArchiveFile.string('report.txt', renderText()))
      ..addFile(ArchiveFile.string('report.json', renderJson()))
      ..addFile(ArchiveFile.string('events.log', renderEventLog()))
      ..addFile(ArchiveFile.string(
        'README.txt',
        'Created locally by Wi-Fi Signal Tester after an explicit user action.\n'
            'No file was uploaded automatically. Passwords, tokens and private keys\n'
            'are excluded. Review report.txt before sharing this archive.\n',
      ));
    return ZipEncoder().encodeBytes(archive);
  }

  Future<File> writeToTemporaryDirectory() async {
    final dir = await getTemporaryDirectory();
    final stamp = _fileStamp(snapshot.createdAt);
    final file = File(p.join(
      dir.path,
      'wifi-signal-tester-support-$stamp.zip',
    ));
    return file.writeAsBytes(archiveBytes(), flush: true);
  }

  static void _writeMap(
    StringBuffer out,
    Map<String, Object?> map,
    int depth,
  ) {
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map) {
        out
          ..writeln()
          ..writeln('${'  ' * depth}${entry.key.toUpperCase()}');
        _writeMap(
          out,
          value.map((k, v) => MapEntry(k.toString(), v)),
          depth + 1,
        );
      } else if (value is Iterable) {
        out.writeln('${'  ' * depth}${entry.key}: ${value.join(', ')}');
      } else {
        out.writeln('${'  ' * depth}${entry.key}: ${value ?? '—'}');
      }
    }
  }

  static String _eventLine(Map<String, Object?> event) {
    final details = event['details'];
    final detailsText =
        details is Map && details.isNotEmpty ? ' ${jsonEncode(details)}' : '';
    final repeats =
        event['occurrences'] == null ? '' : ' x${event['occurrences']}';
    return '${event['timestamp']} ${event['code']} ${event['message']}'
        '$repeats$detailsText';
  }

  static String _fileStamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final v = value.toLocal();
    return '${v.year}${two(v.month)}${two(v.day)}-'
        '${two(v.hour)}${two(v.minute)}${two(v.second)}';
  }

  static Set<String> _networkIdentifiers(Map<String, Object?> report) {
    final result = <String>{};
    void visit(String key, Object? value) {
      final lower = key.toLowerCase();
      final sensitive = lower.contains('ssid') ||
          lower.contains('bssid') ||
          lower.contains('mac') ||
          lower.contains('host') ||
          lower.contains('ip_address') ||
          lower.contains('gateway') ||
          lower.contains('ap_name') ||
          lower.contains('interface') ||
          lower == 'last_roam';
      if (sensitive && value is String && value.isNotEmpty) result.add(value);
      if (value is Map) {
        value.forEach((nestedKey, nestedValue) {
          visit(nestedKey.toString(), nestedValue);
        });
      } else if (value is Iterable) {
        for (final item in value) {
          visit(key, item);
        }
      }
    }

    report.forEach(visit);
    return result;
  }
}
