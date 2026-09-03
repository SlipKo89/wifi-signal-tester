import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wifi_apk/zabbix/zabbix_api_client.dart';
import 'package:wifi_apk/zabbix/zabbix_models.dart';

void main() {
  test('normalizes HTTP/HTTPS frontends and explicit ports', () {
    expect(
      ZabbixApiClient.normalizeEndpoint('zabbix.example.com/zabbix').toString(),
      'https://zabbix.example.com/zabbix/api_jsonrpc.php',
    );
    expect(
      ZabbixApiClient.normalizeEndpoint(
        'https://zabbix.example.com/api_jsonrpc.php/',
      ).toString(),
      'https://zabbix.example.com/api_jsonrpc.php',
    );
    expect(
      ZabbixApiClient.normalizeEndpoint(
        'zabbix.lan/zabbix',
        scheme: 'http',
        port: 8080,
      ).toString(),
      'http://zabbix.lan:8080/zabbix/api_jsonrpc.php',
    );
    expect(
      ZabbixApiClient.normalizeEndpoint(
        'https://zabbix.example.com:8443/zabbix',
      ).toString(),
      'https://zabbix.example.com:8443/zabbix/api_jsonrpc.php',
    );
    expect(
      ZabbixApiClient.normalizeEndpoint(
        'https://zabbix.example.com/zabbix',
        scheme: 'http',
        port: 8081,
      ).toString(),
      'http://zabbix.example.com:8081/zabbix/api_jsonrpc.php',
    );
  });

  test('rejects unsupported schemes and invalid ports', () {
    expect(
      () => ZabbixApiClient.normalizeEndpoint('ftp://zabbix.example.com'),
      throwsFormatException,
    );
    expect(
      () => ZabbixApiClient.normalizeEndpoint(
        'zabbix.example.com',
        port: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => ZabbixApiClient.normalizeEndpoint(
        'zabbix.example.com',
        port: 65536,
      ),
      throwsFormatException,
    );
  });

  test('read-only dispatcher exposes no mutating Zabbix methods', () {
    expect(
      ZabbixApiClient.allowedMethods,
      {
        'apiinfo.version',
        'host.get',
        'item.get',
        'history.get',
        'trend.get',
      },
    );
    expect(
      ZabbixApiClient.allowedMethods.every(
        (method) => method == 'apiinfo.version' || method.endsWith('.get'),
      ),
      isTrue,
    );
  });

  test('Zabbix 7 uses Bearer auth and returns readable hosts', () async {
    final seen = <http.Request>[];
    final client = ZabbixApiClient(
      url: 'https://zabbix.example.com/zabbix',
      apiToken: 'test-secret-token',
      httpClient: MockClient((request) async {
        seen.add(request);
        final call = jsonDecode(request.body) as Map<String, dynamic>;
        if (call['method'] == 'apiinfo.version') {
          return _response('7.4.2');
        }
        expect(call['method'], 'host.get');
        return _response([
          {
            'hostid': '12',
            'host': 'router-technical',
            'name': 'Main router',
            'status': '0',
          }
        ]);
      }),
    );

    final probe = await client.probe();
    expect(probe.version, '7.4.2');
    expect(probe.hosts.single.label, 'Main router');
    expect(seen.first.headers.containsKey('authorization'), isFalse);
    expect(seen.last.headers['authorization'], 'Bearer test-secret-token');
    expect(jsonDecode(seen.last.body), isNot(contains('auth')));
    client.close();
  });

  test('Zabbix 6.0 uses the compatible auth property', () async {
    final authenticatedBodies = <Map<String, dynamic>>[];
    final client = ZabbixApiClient(
      url: 'https://zabbix.example.com',
      apiToken: 'legacy-secret-token',
      httpClient: MockClient((request) async {
        final call = jsonDecode(request.body) as Map<String, dynamic>;
        if (call['method'] == 'apiinfo.version') return _response('6.0.40');
        authenticatedBodies.add(call);
        expect(request.headers.containsKey('authorization'), isFalse);
        return _response([]);
      }),
    );

    await client.probe();
    expect(authenticatedBodies.single['auth'], 'legacy-secret-token');
    client.close();
  });

  test('reads numeric items and hourly trend history', () async {
    final client = ZabbixApiClient(
      url: 'https://zabbix.example.com',
      apiToken: 'test-token',
      httpClient: MockClient((request) async {
        final call = jsonDecode(request.body) as Map<String, dynamic>;
        switch (call['method']) {
          case 'apiinfo.version':
            return _response('7.0.15');
          case 'item.get':
            return _response([
              {
                'itemid': '101',
                'name': 'LTE RSRP',
                'key_': 'lte.rsrp',
                'value_type': '0',
                'units': 'dBm',
                'lastvalue': '-103.5',
                'lastclock': '1720000000',
              },
              {
                'itemid': '102',
                'name': 'Router status',
                'key_': 'router.status',
                'value_type': '1',
                'units': '',
                'lastvalue': 'running',
                'lastclock': '1720000000',
              },
            ]);
          case 'trend.get':
            return _response([
              {
                'clock': '1720003600',
                'num': '3',
                'value_min': '-106',
                'value_avg': '-104',
                'value_max': '-102',
              },
              {
                'clock': '1720000000',
                'num': '1',
                'value_min': '-110',
                'value_avg': '-108',
                'value_max': '-107',
              },
            ]);
          default:
            fail('Unexpected method ${call['method']}');
        }
      }),
    );

    final items = await client.numericItems('50');
    expect(items, hasLength(1));
    expect(items.single.name, 'LTE RSRP');
    expect(items.single.lastValue, -103.5);

    final series = await client.history(
      item: items.single,
      from: DateTime.fromMillisecondsSinceEpoch(1719900000000),
      preferTrends: true,
    );
    expect(series.source, ZabbixHistorySource.trends);
    expect(series.points, hasLength(2));
    expect(series.points.first.value, -108);
    expect(series.minimum, -110);
    expect(series.maximum, -102);
    expect(series.average, -105);
    client.close();
  });

  test('classifies JSON-RPC authorization details without exposing them',
      () async {
    final client = ZabbixApiClient(
      url: 'https://zabbix.example.com',
      apiToken: 'expired-token',
      httpClient: MockClient((request) async {
        final call = jsonDecode(request.body) as Map<String, dynamic>;
        if (call['method'] == 'apiinfo.version') return _response('7.4.2');
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {
              'code': -32602,
              'message': 'Invalid params.',
              'data': 'Not authorized.',
            },
            'id': 1,
          }),
          200,
        );
      }),
    );

    try {
      await client.probe();
      fail('Authorization failure expected');
    } on ZabbixApiException catch (error) {
      expect(error.authorizationFailure, isTrue);
      expect(error.toString(), 'Invalid params.');
      expect(error.toString(), isNot(contains('expired-token')));
    }
    client.close();
  });
}

http.Response _response(Object? result) => http.Response(
      jsonEncode({'jsonrpc': '2.0', 'result': result, 'id': 1}),
      200,
      headers: {'content-type': 'application/json'},
    );
