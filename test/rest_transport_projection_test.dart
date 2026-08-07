import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/mikrotik/rest_transport.dart';

void main() {
  test('REST read sends .proplist and returns projected log fields', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Future<void>>[];
    final subscription = server.listen((request) {
      requests.add(() async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/rest/system/identity') {
          request.response.write(jsonEncode({'name': 'test'}));
        } else {
          expect(request.uri.path, '/rest/log');
          expect(
              request.uri.queryParameters['.proplist'], 'time,topics,message');
          request.response.write(jsonEncode([
            {
              'time': '12:00:00',
              'topics': 'wireless,info',
              'message': 'client connected',
              'buffer': 'memory',
            },
          ]));
        }
        await request.response.close();
      }());
    });
    final transport = RestTransport(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      username: 'readonly',
      password: 'test',
      useTls: false,
      timeout: const Duration(seconds: 2),
    );

    try {
      await transport.connect();
      final rows = await transport.read(
        '/log',
        fields: const ['time', 'topics', 'message'],
      );
      expect(rows.single, {
        'time': '12:00:00',
        'topics': 'wireless,info',
        'message': 'client connected',
      });
    } finally {
      await transport.close();
      await subscription.cancel();
      await server.close(force: true);
      await Future.wait(requests);
    }
  });
}
