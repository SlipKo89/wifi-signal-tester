import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/mikrotik/rest_transport.dart';

void main() {
  test('REST transport can reconnect after its client was closed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    final requests = <String>[];
    final serving = server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/system/identity') {
        request.response.write(jsonEncode({'name': 'test-router'}));
      } else {
        request.response.write(jsonEncode({'cpu-load': '3'}));
      }
      await request.response.close();
    });
    addTearDown(serving.cancel);

    final transport = RestTransport(
      host: InternetAddress.loopbackIPv4.address,
      username: 'monitor',
      password: 'secret',
      useTls: false,
      port: server.port,
    );

    await transport.connect();
    await transport.close();
    await transport.connect();
    final rows = await transport.read('/system/resource');
    await transport.close();

    expect(rows.single['cpu-load'], '3');
    expect(
      requests.where((path) => path == '/rest/system/identity'),
      hasLength(2),
    );
  });
}
