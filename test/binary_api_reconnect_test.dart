import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/mikrotik/binary_api_transport.dart';

void main() {
  test('binary API reconnects once after a dead background session', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final handled = <Future<void>>[];
    var connections = 0;
    final events = <String>[];

    final subscription = server.listen((socket) {
      final connection = ++connections;
      handled.add(() async {
        final reader = _SentenceReader(socket);
        expect((await reader.read()).first, '/login');
        socket.add(_sentence(['!done']));

        final command = await reader.read();
        expect(command.first, '/system/resource/print');
        if (connection == 1) {
          socket.destroy();
          return;
        }
        socket.add(_sentence(['!re', '=version=7.22.3', '=cpu-load=12']));
        socket.add(_sentence(['!done']));
        await socket.flush();
      }());
    });

    final transport = BinaryApiTransport(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      username: 'readonly',
      password: 'test',
      timeout: const Duration(seconds: 2),
      onEvent: (code, _, __) => events.add(code),
    );

    try {
      await transport.connect();
      final rows = await transport.read('/system/resource');
      expect(rows.single['version'], '7.22.3');
      expect(rows.single['cpu-load'], '12');
      expect(connections, 2);
      expect(events, containsAllInOrder(['API-RECONNECT', 'API-RECONNECTED']));
    } finally {
      await transport.close();
      await subscription.cancel();
      await server.close();
      await Future.wait(handled);
    }
  });
}

class _SentenceReader {
  final StreamIterator<List<int>> _chunks;
  final List<int> _buffer = [];

  _SentenceReader(Socket socket) : _chunks = StreamIterator(socket);

  Future<List<String>> read() async {
    final result = <String>[];
    while (true) {
      final length = await _byte();
      if (length == 0) return result;
      expect(length, lessThan(0x80));
      await _ensure(length);
      result.add(String.fromCharCodes(_buffer.take(length)));
      _buffer.removeRange(0, length);
    }
  }

  Future<int> _byte() async {
    await _ensure(1);
    return _buffer.removeAt(0);
  }

  Future<void> _ensure(int count) async {
    while (_buffer.length < count) {
      if (!await _chunks.moveNext()) {
        throw StateError('Socket closed while reading a test sentence');
      }
      _buffer.addAll(_chunks.current);
    }
  }
}

List<int> _sentence(List<String> words) => [
      for (final word in words) ...[
        word.length,
        ...word.codeUnits,
      ],
      0,
    ];
