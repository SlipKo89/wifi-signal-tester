import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wifi_apk/keenetic/keenetic_rci_client.dart';
import 'package:wifi_apk/router/wifi_router_service.dart';

void main() {
  test('RCI authenticates with x-ndw2 and only reads whitelisted show paths',
      () async {
    const username = 'monitor';
    const password = 's3cret!';
    const realm = 'Runner 4G';
    const challenge = 'challenge-value';
    const cookie = '__Host-Http-test=session-value';
    final requests = <String>[];

    final httpClient = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' && request.url.path == '/auth') {
        expect(request.url.host, 'router.example');
        expect(request.url.path, '/auth');
        return http.Response('', 401, headers: {
          'x-ndm-realm': realm,
          'x-ndm-challenge': challenge,
          'set-cookie': '$cookie; Path=/; Secure; HttpOnly',
        });
      }
      if (request.method == 'POST' && request.url.path == '/auth') {
        expect(request.headers['cookie'], cookie);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final digest =
            md5.convert(utf8.encode('$username:$realm:$password')).toString();
        final expected =
            sha256.convert(utf8.encode('$challenge$digest')).toString();
        expect(body['login'], username);
        expect(body['password'], expected);
        expect(request.body, isNot(contains(password)));
        return http.Response('{}', 200);
      }
      if (request.method == 'GET' && request.url.path == '/rci/show/system') {
        expect(request.headers['cookie'], cookie);
        return http.Response(jsonEncode({'cpuload': 12}), 200);
      }
      fail('Unexpected RCI request: ${request.method} ${request.url}');
    });

    final client = KeeneticRciClient(
      host: 'https://router.example/rci/show/system',
      username: username,
      password: password,
      client: httpClient,
    );
    addTearDown(client.close);

    await client.connect();
    expect(await client.getObject('/rci/show/system'), {'cpuload': 12});
    expect(
      () => client.getObject('/rci/system/reboot'),
      throwsA(isA<RouterAccessException>()),
    );
    expect(requests, [
      'GET /auth',
      'POST /auth',
      'GET /rci/show/system',
    ]);
  });

  test('RCI errors do not expose a response body', () async {
    const privateBody = 'private router response';
    final client = KeeneticRciClient(
      host: 'router.example',
      username: 'monitor',
      password: 'wrong',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response('', 401, headers: {
            'x-ndm-realm': 'realm',
            'x-ndm-challenge': 'challenge',
            'set-cookie': 'session=value; Path=/',
          });
        }
        return http.Response(privateBody, 403);
      }),
    );
    addTearDown(client.close);

    Object? error;
    try {
      await client.connect();
    } catch (caught) {
      error = caught;
    }
    expect(error, isA<RouterAccessException>());
    expect(error.toString(), isNot(contains(privateBody)));
    expect(error.toString(), isNot(contains('wrong')));
  });
}
