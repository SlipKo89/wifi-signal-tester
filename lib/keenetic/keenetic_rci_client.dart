import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../router/wifi_router_service.dart';

/// Minimal read-only Keenetic RCI client.
///
/// RCI can configure a router through POST, therefore this client does not
/// expose a generic POST operation. The only POST allowed by construction is
/// `/auth`; all data access is a GET to an explicit `/rci/show/...` whitelist.
class KeeneticRciClient {
  static const allowedGetPaths = {
    '/rci/show/system',
    '/rci/show/version',
    '/rci/show/associations',
    '/rci/show/ip/dhcp/bindings',
    '/rci/show/ip/arp',
  };

  final Uri _baseUri;
  final String _username;
  String? _password;
  final http.Client _client;
  final Duration timeout;
  String? _cookie;
  bool _connected = false;

  KeeneticRciClient({
    required String host,
    required String username,
    required String password,
    bool useTls = true,
    int? port,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  })  : _baseUri = _parseBaseUri(host, useTls: useTls, port: port),
        _username = username,
        _password = password,
        _client = client ?? http.Client();

  String get kind => '${_baseUri.scheme.toUpperCase()} RCI';

  static Uri _parseBaseUri(
    String input, {
    required bool useTls,
    int? port,
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const RouterAccessException('Keenetic host is empty');
    }
    final parsed = Uri.tryParse(
      trimmed.contains('://')
          ? trimmed
          : '${useTls ? 'https' : 'http'}://$trimmed',
    );
    if (parsed == null ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw const RouterAccessException('Invalid Keenetic HTTP address');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const RouterAccessException(
        'Do not put Keenetic credentials in the URL',
      );
    }
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: port ?? (parsed.hasPort ? parsed.port : null),
    );
  }

  Uri _uri(String path) => _baseUri.replace(path: path);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (_cookie != null) 'Cookie': _cookie!,
      };

  Future<void> connect() async {
    final password = _password;
    if (password == null) {
      throw const RouterAccessException('Keenetic credentials were cleared');
    }
    final challengeResponse = await _client.get(_uri('/auth'),
        headers: const {'Accept': 'application/json'}).timeout(timeout);
    if (challengeResponse.statusCode != 401) {
      throw RouterAccessException(
        'Unexpected Keenetic authentication challenge '
        '(${challengeResponse.statusCode})',
      );
    }
    _captureCookie(challengeResponse);
    final realm = challengeResponse.headers['x-ndm-realm'] ??
        _quotedParameter(
          challengeResponse.headers['www-authenticate'],
          'realm',
        );
    final challenge = challengeResponse.headers['x-ndm-challenge'] ??
        _quotedParameter(
          challengeResponse.headers['www-authenticate'],
          'challenge',
        );
    if (realm == null || challenge == null || _cookie == null) {
      throw const RouterAccessException(
        'Keenetic x-ndw2 authentication challenge is incomplete',
      );
    }

    final credential =
        md5.convert(utf8.encode('$_username:$realm:$password')).toString();
    final responseHash =
        sha256.convert(utf8.encode('$challenge$credential')).toString();
    final authResponse = await _client
        .post(
          _uri('/auth'),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'login': _username,
            'password': responseHash,
          }),
        )
        .timeout(timeout);
    if (authResponse.statusCode < 200 || authResponse.statusCode >= 300) {
      throw RouterAccessException(
        'Keenetic authentication failed (${authResponse.statusCode})',
      );
    }
    _captureCookie(authResponse);
    _connected = true;
    _password = null;
  }

  Future<Map<String, dynamic>> getObject(String path) async {
    if (!_connected) {
      throw const RouterAccessException('Keenetic RCI is not connected');
    }
    if (!allowedGetPaths.contains(path)) {
      throw RouterAccessException('Keenetic RCI path is not allowed: $path');
    }
    final response =
        await _client.get(_uri(path), headers: _headers).timeout(timeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw RouterAccessException(
        'Keenetic RCI access denied (${response.statusCode})',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RouterAccessException(
        'Keenetic RCI read failed (${response.statusCode})',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('JSON root is not an object');
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      throw const RouterAccessException('Keenetic returned invalid JSON');
    }
  }

  void _captureCookie(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final pair = raw.split(';').first.trim();
    if (pair.isNotEmpty && pair.contains('=')) _cookie = pair;
  }

  static String? _quotedParameter(String? header, String name) {
    if (header == null) return null;
    return RegExp('$name="([^"]+)"', caseSensitive: false)
        .firstMatch(header)
        ?.group(1);
  }

  void close() {
    _connected = false;
    _cookie = null;
    _password = null;
    _client.close();
  }
}
