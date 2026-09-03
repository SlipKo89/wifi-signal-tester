import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'zabbix_models.dart';

class ZabbixApiException implements Exception {
  final int? code;
  final String message;
  final bool authorizationFailure;

  const ZabbixApiException(
    this.message, {
    this.code,
    this.authorizationFailure = false,
  });

  @override
  String toString() => message;
}

/// A deliberately read-only Zabbix JSON-RPC client. The private dispatcher
/// rejects every method outside this fixed list; there is no generic public
/// call and no create/update/delete/acknowledge operation.
class ZabbixApiClient {
  static const allowedMethods = <String>{
    'apiinfo.version',
    'host.get',
    'item.get',
    'history.get',
    'trend.get',
  };

  static const _historyLimit = 1500;

  final Uri endpoint;
  final String apiToken;
  final Duration timeout;
  final http.Client _http;
  String? _version;

  ZabbixApiClient({
    required String url,
    required this.apiToken,
    String? scheme,
    int? port,
    this.timeout = const Duration(seconds: 12),
    http.Client? httpClient,
  })  : endpoint = normalizeEndpoint(url, scheme: scheme, port: port),
        _http = httpClient ?? http.Client() {
    if (apiToken.trim().isEmpty) {
      throw const FormatException('API token is required.');
    }
  }

  static Uri normalizeEndpoint(
    String input, {
    String? scheme,
    int? port,
  }) {
    var value = input.trim();
    if (value.isEmpty) throw const FormatException('Zabbix URL is required.');
    final requestedScheme = scheme?.trim().toLowerCase();
    if (requestedScheme != null &&
        requestedScheme != 'https' &&
        requestedScheme != 'http') {
      throw const FormatException('Zabbix scheme must be HTTP or HTTPS.');
    }
    if (!value.contains('://')) {
      value = '${requestedScheme ?? 'https'}://$value';
    }
    var parsed = Uri.tryParse(value);
    if (parsed == null ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'https' && parsed.scheme != 'http')) {
      throw const FormatException(
        'Enter a valid HTTP or HTTPS Zabbix frontend address.',
      );
    }
    if (requestedScheme != null && parsed.scheme != requestedScheme) {
      parsed = parsed.replace(scheme: requestedScheme);
    }
    int parsedPort;
    try {
      parsedPort = parsed.port;
    } on FormatException {
      throw const FormatException('The Zabbix port is not valid.');
    }
    final selectedPort = port ?? (parsed.hasPort ? parsedPort : null);
    if (selectedPort != null && (selectedPort < 1 || selectedPort > 65535)) {
      throw const FormatException('The Zabbix port must be from 1 to 65535.');
    }
    if (parsed.userInfo.isNotEmpty || parsed.hasQuery || parsed.hasFragment) {
      throw const FormatException('The Zabbix URL is not valid.');
    }
    if (port != null) parsed = parsed.replace(port: port);
    var path = parsed.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith('/api_jsonrpc.php')) {
      path = '$path/api_jsonrpc.php';
    }
    return parsed.replace(path: path, query: null, fragment: null);
  }

  bool get usesCleartext => endpoint.scheme == 'http';

  Future<ZabbixProbe> probe() async {
    final version = await apiVersion();
    final readableHosts = await hosts();
    return ZabbixProbe(version: version, hosts: readableHosts);
  }

  Future<String> apiVersion() async {
    final result =
        await _call('apiinfo.version', const {}, authenticated: false);
    final version = result?.toString().trim() ?? '';
    if (version.isEmpty) {
      throw const ZabbixApiException(
        'The endpoint did not return a Zabbix API version.',
      );
    }
    _version = version;
    return version;
  }

  Future<List<ZabbixHost>> hosts() async {
    await _ensureVersion();
    final result = await _call('host.get', {
      'output': ['hostid', 'host', 'name', 'status'],
      'sortfield': 'name',
    });
    if (result is! List) return [];
    final hosts = <ZabbixHost>[];
    for (final value in result.whereType<Map>()) {
      final row = _row(value);
      final id = row['hostid']?.toString() ?? '';
      if (id.isEmpty) continue;
      hosts.add(ZabbixHost(
        hostId: id,
        technicalName: row['host']?.toString() ?? '',
        visibleName: row['name']?.toString() ?? '',
        enabled: row['status']?.toString() != '1',
      ));
    }
    hosts
        .sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return hosts;
  }

  Future<List<ZabbixItem>> numericItems(String hostId) async {
    await _ensureVersion();
    final result = await _call('item.get', {
      'output': [
        'itemid',
        'name',
        'key_',
        'value_type',
        'units',
        'lastvalue',
        'lastclock',
        'status',
        'state',
      ],
      'hostids': [hostId],
      'filter': {'status': '0', 'state': '0'},
      'sortfield': 'name',
    });
    if (result is! List) return [];
    final items = <ZabbixItem>[];
    for (final value in result.whereType<Map>()) {
      final row = _row(value);
      final valueType = int.tryParse(row['value_type']?.toString() ?? '');
      if (valueType != 0 && valueType != 3) continue;
      final id = row['itemid']?.toString() ?? '';
      if (id.isEmpty) continue;
      final lastClock = int.tryParse(row['lastclock']?.toString() ?? '');
      items.add(ZabbixItem(
        itemId: id,
        name: row['name']?.toString() ?? id,
        key: row['key_']?.toString() ?? '',
        valueType: valueType!,
        units: row['units']?.toString() ?? '',
        lastValue: double.tryParse(row['lastvalue']?.toString() ?? ''),
        lastReceivedAt: lastClock == null || lastClock <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastClock * 1000),
      ));
    }
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<ZabbixSeries> history({
    required ZabbixItem item,
    required DateTime from,
    DateTime? till,
    bool preferTrends = false,
  }) async {
    await _ensureVersion();
    final to = till ?? DateTime.now();
    if (preferTrends) {
      final trends = await _trends(item, from, to);
      if (trends.isNotEmpty) {
        return ZabbixSeries(
          source: ZabbixHistorySource.trends,
          points: trends,
        );
      }
      final fallback = await _rawHistory(item, from, to);
      return ZabbixSeries(
        source: ZabbixHistorySource.historyFallback,
        points: fallback,
        possiblyTruncated: fallback.length >= _historyLimit,
      );
    }
    final points = await _rawHistory(item, from, to);
    return ZabbixSeries(
      source: ZabbixHistorySource.history,
      points: points,
      possiblyTruncated: points.length >= _historyLimit,
    );
  }

  Future<List<ZabbixHistoryPoint>> _rawHistory(
    ZabbixItem item,
    DateTime from,
    DateTime till,
  ) async {
    final result = await _call('history.get', {
      'output': ['clock', 'value'],
      'history': item.valueType,
      'itemids': [item.itemId],
      'time_from': from.millisecondsSinceEpoch ~/ 1000,
      'time_till': till.millisecondsSinceEpoch ~/ 1000,
      'sortfield': 'clock',
      'sortorder': 'DESC',
      'limit': _historyLimit,
    });
    if (result is! List) return [];
    final points = <ZabbixHistoryPoint>[];
    for (final value in result.whereType<Map>()) {
      final row = _row(value);
      final clock = int.tryParse(row['clock']?.toString() ?? '');
      final number = double.tryParse(row['value']?.toString() ?? '');
      if (clock == null || number == null || !number.isFinite) continue;
      points.add(ZabbixHistoryPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(clock * 1000),
        value: number,
        minimum: number,
        maximum: number,
      ));
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  Future<List<ZabbixHistoryPoint>> _trends(
    ZabbixItem item,
    DateTime from,
    DateTime till,
  ) async {
    final result = await _call('trend.get', {
      'output': [
        'clock',
        'num',
        'value_min',
        'value_avg',
        'value_max',
      ],
      'itemids': [item.itemId],
      'time_from': from.millisecondsSinceEpoch ~/ 1000,
      'time_till': till.millisecondsSinceEpoch ~/ 1000,
      'limit': _historyLimit,
    });
    if (result is! List) return [];
    final points = <ZabbixHistoryPoint>[];
    for (final value in result.whereType<Map>()) {
      final row = _row(value);
      final clock = int.tryParse(row['clock']?.toString() ?? '');
      final average = double.tryParse(row['value_avg']?.toString() ?? '');
      final minimum = double.tryParse(row['value_min']?.toString() ?? '');
      final maximum = double.tryParse(row['value_max']?.toString() ?? '');
      if (clock == null ||
          average == null ||
          minimum == null ||
          maximum == null ||
          !average.isFinite ||
          !minimum.isFinite ||
          !maximum.isFinite) {
        continue;
      }
      points.add(ZabbixHistoryPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(clock * 1000),
        value: average,
        minimum: minimum,
        maximum: maximum,
        samples: int.tryParse(row['num']?.toString() ?? '') ?? 1,
      ));
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  Future<void> _ensureVersion() async {
    if (_version == null) await apiVersion();
  }

  Future<Object?> _call(
    String method,
    Map<String, Object?> params, {
    bool authenticated = true,
  }) async {
    if (!allowedMethods.contains(method)) {
      throw StateError('Zabbix method is outside the read-only allowlist.');
    }
    final body = <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': 1,
    };
    final headers = <String, String>{
      'Content-Type': 'application/json-rpc',
      'Accept': 'application/json',
    };
    if (authenticated) {
      if (_usesLegacyAuthProperty) {
        body['auth'] = apiToken;
      } else {
        headers['Authorization'] = 'Bearer $apiToken';
      }
    }

    final response = await _http
        .post(endpoint, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ZabbixApiException(
        'Zabbix HTTP error ${response.statusCode}.',
        code: response.statusCode,
        authorizationFailure:
            response.statusCode == 401 || response.statusCode == 403,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const ZabbixApiException(
        'Zabbix returned a response that is not JSON.',
      );
    }
    if (decoded is! Map) {
      throw const ZabbixApiException('Invalid Zabbix JSON-RPC response.');
    }
    final error = decoded['error'];
    if (error is Map) {
      final message = error['message']?.toString().trim();
      final details = error['data']?.toString().toLowerCase() ?? '';
      final combined = '${message?.toLowerCase() ?? ''} $details';
      throw ZabbixApiException(
        message == null || message.isEmpty
            ? 'Zabbix rejected the request.'
            : message,
        code: int.tryParse(error['code']?.toString() ?? ''),
        authorizationFailure: combined.contains('not authorized') ||
            combined.contains('not authorised') ||
            combined.contains('permission denied'),
      );
    }
    if (!decoded.containsKey('result')) {
      throw const ZabbixApiException('Zabbix response has no result.');
    }
    return decoded['result'];
  }

  bool get _usesLegacyAuthProperty {
    final parts = (_version ?? '').split('.');
    final major = parts.isEmpty ? null : int.tryParse(parts.first);
    final minor = parts.length < 2 ? null : int.tryParse(parts[1]);
    if (major == null) return false;
    return major < 6 || (major == 6 && (minor ?? 0) < 4);
  }

  static Map<String, Object?> _row(Map source) => source.map(
        (key, value) => MapEntry(key.toString(), value),
      );

  void close() => _http.close();
}
