import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/mikrotik/mikrotik_service.dart';
import 'package:wifi_apk/wifi_logs/wifi_log_service.dart';

void main() {
  test('log reader projects fields and keeps only the newest bounded window',
      () async {
    final rows = [
      for (var i = 0; i < 2005; i++)
        {
          'time': '12:00:${(i % 60).toString().padLeft(2, '0')}',
          'topics': 'wireless,info',
          'message': 'event $i',
          'unused': 'must not be requested',
        },
    ];
    final router = _FakeRouter(
      logs: rows,
      logging: const [
        {'topics': 'wireless,debug', 'action': 'memory'},
      ],
    );

    final source = await WifiLogService().readSource(router);

    expect(source.totalRows, 2005);
    expect(source.rows, hasLength(2000));
    expect(source.rows.first['message'], 'event 5');
    expect(source.truncated, isTrue);
    expect(source.debugLogging, isTrue);
    expect(router.requestedFields['/log'], ['time', 'topics', 'message']);
    expect(source.rows.first, isNot(contains('unused')));
  });
}

class _FakeRouter extends MikrotikService {
  final List<Map<String, String>> logs;
  final List<Map<String, String>> logging;
  final Map<String, List<String>?> requestedFields = {};

  _FakeRouter({required this.logs, required this.logging}) {
    host = 'router.test';
  }

  @override
  String? get transportKind => 'REST';

  @override
  Future<List<Map<String, String>>> readMenu(
    String path, {
    Map<String, String>? filters,
    List<String>? fields,
  }) async {
    requestedFields[path] = fields;
    final source = path == '/log' ? logs : logging;
    if (fields == null || fields.isEmpty) return source;
    return [
      for (final row in source)
        {
          for (final field in fields)
            if (row.containsKey(field)) field: row[field]!,
        },
    ];
  }
}
