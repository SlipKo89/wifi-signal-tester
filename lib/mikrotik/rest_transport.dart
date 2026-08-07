import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'router_os_transport.dart';

/// RouterOS 7.1+ REST API transport (HTTPS by default).
///
/// Menu path `/interface/wireless/registration-table` maps to
/// `https://host/rest/interface/wireless/registration-table`.
class RestTransport implements RouterOsTransport {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useTls;
  final Duration timeout;

  late final http.Client _client;
  late final String _authHeader;

  RestTransport({
    required this.host,
    required this.username,
    required this.password,
    this.useTls = true,
    int? port,
    this.timeout = const Duration(seconds: 8),
  }) : port = port ?? (useTls ? 443 : 80);

  @override
  String get kind => 'REST';

  String get _scheme => useTls ? 'https' : 'http';

  @override
  Future<void> connect() async {
    // Accept self-signed certs — routers on a LAN almost always use them.
    final io = HttpClient();
    io.badCertificateCallback = (_, __, ___) => true;
    io.connectionTimeout = timeout;
    _client = IOClient(io);
    _authHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

    // A cheap authenticated probe to fail fast on wrong credentials / no REST.
    final uri = Uri.parse('$_scheme://$host:$port/rest/system/identity');
    final resp = await _client
        .get(uri, headers: {'Authorization': _authHeader}).timeout(timeout);
    if (resp.statusCode == 401) {
      throw RouterOsException('Authentication failed (401)');
    }
    if (resp.statusCode >= 400) {
      throw RouterOsException('REST API not available (${resp.statusCode})');
    }
  }

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  }) async {
    validateReadFields(fields);
    var uri = Uri.parse('$_scheme://$host:$port/rest$menuPath');
    final query = <String, String>{
      ...?filters,
      if (fields != null && fields.isNotEmpty) '.proplist': fields.join(','),
    };
    if (query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final resp = await _client
        .get(uri, headers: {'Authorization': _authHeader}).timeout(timeout);

    if (resp.statusCode == 401) {
      throw RouterOsException('Authentication failed (401)');
    }
    if (resp.statusCode >= 400) {
      throw RouterOsException('GET $menuPath → HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    Map<String, String> asRow(Map row) =>
        row.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    // Most menus return a JSON array; a few (e.g. /system/resource) return a
    // single object — wrap it so callers always get a list of rows.
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(asRow)
          .map((row) => projectReadFields(row, fields))
          .toList();
    }
    if (decoded is Map) return [projectReadFields(asRow(decoded), fields)];
    return const [];
  }

  @override
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  ) async {
    validateReadOnlyCommand(path, params);
    final uri = Uri.parse('$_scheme://$host:$port/rest$path');
    final resp = await _client
        .post(uri,
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(params))
        .timeout(timeout);
    if (resp.statusCode >= 400) {
      throw RouterOsException('POST $path → HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    Map<String, String> asRow(Map row) =>
        row.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    if (decoded is List) return decoded.whereType<Map>().map(asRow).toList();
    if (decoded is Map) return [asRow(decoded)];
    return const [];
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}
