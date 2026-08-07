import '../mikrotik/mikrotik_service.dart';
import 'wifi_log_analysis.dart';

class WifiLogService {
  static const int maxRowsPerRouter = 2000;

  Future<WifiLogSourceSnapshot> readSource(MikrotikService router) async {
    final host = router.host ?? 'MikroTik';
    final transport = router.transportKind ?? '—';
    try {
      final rows = await router.readMenu(
        '/log',
        fields: const ['time', 'topics', 'message'],
      );
      final total = rows.length;
      final recent = total > maxRowsPerRouter
          ? rows.sublist(total - maxRowsPerRouter)
          : rows;
      var info = false;
      var debug = false;
      try {
        final settings = await router.readMenu(
          '/system/logging',
          fields: const ['topics', 'disabled', 'action'],
        );
        for (final row in settings) {
          if (_isDisabled(row['disabled'])) continue;
          final topics = (row['topics'] ?? '')
              .toLowerCase()
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet();
          final wifi = topics.contains('wireless') || topics.contains('caps');
          if (topics.contains('info') || wifi) info = true;
          if (topics.contains('debug') &&
              (wifi || topics.length == 1 || topics.contains('info'))) {
            debug = true;
          }
        }
      } catch (_) {
        // Existing log rows remain useful even when the logging configuration
        // menu is hidden from this read-only group.
      }
      return WifiLogSourceSnapshot(
        host: host,
        transport: transport,
        rows: List.unmodifiable(recent),
        totalRows: total,
        truncated: total > recent.length,
        infoLogging: info,
        debugLogging: debug,
      );
    } catch (error) {
      return WifiLogSourceSnapshot(
        host: host,
        transport: transport,
        rows: const [],
        totalRows: 0,
        truncated: false,
        infoLogging: false,
        debugLogging: false,
        error: _shortError(error),
      );
    }
  }

  bool _isDisabled(String? raw) {
    final value = raw?.toLowerCase();
    return value == 'true' || value == 'yes';
  }

  String _shortError(Object error) {
    final value = error.toString().replaceFirst('RouterOsException: ', '');
    return value.length <= 180 ? value : '${value.substring(0, 180)}…';
  }
}
