import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'router_os_transport.dart';

/// RouterOS binary API transport (ports 8728 plain / 8729 TLS).
///
/// Implements the MikroTik API word/sentence protocol:
///   * length-prefixed words,
///   * sentences terminated by a zero-length word,
///   * `!re` reply rows, `!done` terminator, `!trap`/`!fatal` errors.
///
/// Login supports both the modern (6.43+) plaintext form and the legacy MD5
/// challenge-response, so it works on RouterOS 6 and 7.
class BinaryApiTransport implements RouterOsTransport {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useTls;
  final Duration timeout;

  Socket? _socket;

  /// Bytes received but not yet consumed by the parser.
  final List<int> _inbox = [];
  Completer<void>? _dataWaiter;

  BinaryApiTransport({
    required this.host,
    required this.username,
    required this.password,
    this.useTls = false,
    int? port,
    this.timeout = const Duration(seconds: 8),
  }) : port = port ?? (useTls ? 8729 : 8728);

  @override
  String get kind => 'API';

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect() async {
    final socket = useTls
        ? await SecureSocket.connect(
            host,
            port,
            onBadCertificate: (_) => true, // self-signed on LAN
            timeout: timeout,
          )
        : await Socket.connect(host, port, timeout: timeout);
    _socket = socket;
    socket.listen(
      (data) {
        _inbox.addAll(data);
        _dataWaiter?.complete();
        _dataWaiter = null;
      },
      onError: (_) => _wakeReader(),
      onDone: _wakeReader,
      cancelOnError: true,
    );
    await _login();
  }

  Future<void> _login() async {
    // Modern plaintext login first.
    _writeSentence(['/login', '=name=$username', '=password=$password']);
    var reply = await _readSentence();
    final tag = reply.isEmpty ? '' : reply.first;

    if (tag == '!trap' || tag == '!fatal') {
      throw RouterOsException(_attr(reply, 'message') ?? 'Login rejected');
    }

    // Legacy path: RouterOS < 6.43 answers with a `ret` challenge.
    final challenge = _attr(reply, 'ret');
    if (challenge != null) {
      final chalBytes = _hexToBytes(challenge);
      final digest = md5
          .convert([0, ...utf8.encode(password), ...chalBytes])
          .toString();
      _writeSentence(
          ['/login', '=name=$username', '=response=00$digest']);
      reply = await _readSentence();
      if (reply.isEmpty || reply.first != '!done') {
        throw RouterOsException(
            _attr(reply, 'message') ?? 'Authentication failed');
      }
    } else if (tag != '!done') {
      throw RouterOsException('Unexpected login reply: $tag');
    }
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
  }) async {
    final words = <String>['$menuPath/print'];
    filters?.forEach((k, v) => words.add('?$k=$v'));
    _writeSentence(words);

    final rows = <Map<String, String>>[];
    while (true) {
      final sentence = await _readSentence();
      if (sentence.isEmpty) continue;
      final tag = sentence.first;
      if (tag == '!re') {
        rows.add(_parseAttributes(sentence.skip(1)));
      } else if (tag == '!done') {
        break;
      } else if (tag == '!trap') {
        throw RouterOsException(_attr(sentence, 'message') ?? 'trap');
      } else if (tag == '!fatal') {
        throw RouterOsException('fatal: ${sentence.skip(1).join(' ')}');
      }
    }
    return rows;
  }

  @override
  Future<void> close() async {
    await _socket?.close();
    _socket?.destroy();
    _socket = null;
  }

  // ---------------------------------------------------------------------------
  // Protocol primitives
  // ---------------------------------------------------------------------------

  void _writeSentence(List<String> words) {
    final socket = _socket;
    if (socket == null) throw RouterOsException('Not connected');
    for (final w in words) {
      final bytes = utf8.encode(w);
      socket.add(_encodeLength(bytes.length));
      socket.add(bytes);
    }
    socket.add(const [0]); // zero-length word ends the sentence
  }

  Future<List<String>> _readSentence() async {
    final words = <String>[];
    while (true) {
      final len = await _readLength();
      if (len == 0) break;
      words.add(utf8.decode(await _readBytes(len)));
    }
    return words;
  }

  /// MikroTik variable-length encoding of a word length.
  List<int> _encodeLength(int l) {
    if (l < 0x80) return [l];
    if (l < 0x4000) {
      l |= 0x8000;
      return [(l >> 8) & 0xFF, l & 0xFF];
    }
    if (l < 0x200000) {
      l |= 0xC00000;
      return [(l >> 16) & 0xFF, (l >> 8) & 0xFF, l & 0xFF];
    }
    if (l < 0x10000000) {
      l |= 0xE0000000;
      return [(l >> 24) & 0xFF, (l >> 16) & 0xFF, (l >> 8) & 0xFF, l & 0xFF];
    }
    return [0xF0, (l >> 24) & 0xFF, (l >> 16) & 0xFF, (l >> 8) & 0xFF, l & 0xFF];
  }

  Future<int> _readLength() async {
    final c = await _readByte();
    if ((c & 0x80) == 0x00) return c;
    if ((c & 0xC0) == 0x80) {
      return ((c & 0x3F) << 8) + await _readByte();
    }
    if ((c & 0xE0) == 0xC0) {
      final b = await _readBytes(2);
      return ((c & 0x1F) << 16) + (b[0] << 8) + b[1];
    }
    if ((c & 0xF0) == 0xE0) {
      final b = await _readBytes(3);
      return ((c & 0x0F) << 24) + (b[0] << 16) + (b[1] << 8) + b[2];
    }
    final b = await _readBytes(4);
    return (b[0] << 24) + (b[1] << 16) + (b[2] << 8) + b[3];
  }

  Future<int> _readByte() async {
    await _ensure(1);
    return _inbox.removeAt(0);
  }

  Future<List<int>> _readBytes(int n) async {
    await _ensure(n);
    final out = _inbox.sublist(0, n);
    _inbox.removeRange(0, n);
    return out;
  }

  Future<void> _ensure(int n) async {
    while (_inbox.length < n) {
      if (_socket == null) throw RouterOsException('Connection closed');
      _dataWaiter = Completer<void>();
      await _dataWaiter!.future.timeout(
        timeout,
        onTimeout: () => throw RouterOsException('Read timed out'),
      );
    }
  }

  void _wakeReader() {
    _dataWaiter?.complete();
    _dataWaiter = null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, String> _parseAttributes(Iterable<String> words) {
    final map = <String, String>{};
    for (final w in words) {
      if (!w.startsWith('=')) continue;
      final sep = w.indexOf('=', 1);
      if (sep < 0) continue;
      map[w.substring(1, sep)] = w.substring(sep + 1);
    }
    return map;
  }

  String? _attr(List<String> sentence, String key) {
    final prefix = '=$key=';
    for (final w in sentence) {
      if (w.startsWith(prefix)) return w.substring(prefix.length);
    }
    return null;
  }

  List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
