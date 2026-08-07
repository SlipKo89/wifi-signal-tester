import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:meta/meta.dart';

import 'router_os_transport.dart';

/// RouterOS SSH transport: runs console commands over SSH and parses the CLI
/// output back into the same rows the REST/API transports return.
///
/// Why it exists: on plenty of boxes REST is absent (RouterOS 6) and the binary
/// API service is switched off, while SSH is the one management channel that is
/// always on. This makes those routers readable without touching their config.
///
/// **Read-only by construction.** An SSH session is a full console, so unlike
/// REST/API the restriction cannot come from the protocol — it is enforced here:
///
///   * command lines are *built* from a menu path plus a fixed verb, never
///     taken from the caller as free text;
///   * [_readOnlyCommand] validates the composed line against a whitelist
///     (`print` / `monitor once`) and rejects console metacharacters, so a
///     crafted menu path cannot smuggle in a second command;
///   * `monitor` must carry `once`, otherwise it would stream forever.
///
/// Pair it with a RouterOS user whose group has `ssh,read,test` and no `write`
/// (see docs/mikrotik-readonly-user.md) — then read-only holds on both ends.
class SshTransport implements RouterOsTransport {
  final String host;
  final int port;
  final String username;
  final String password;
  final Duration timeout;

  SSHClient? _client;

  /// RouterOS runs one command per channel; requests are serialised so a poll
  /// and an audit can't interleave on the same connection.
  Future<void> _queue = Future<void>.value();

  /// Guards the reconnect path against recursing into itself.
  bool _reconnecting = false;

  /// Console tuning appended to the username: no colours, no terminal
  /// detection, wide output so `print terse` rows never wrap.
  static const _consoleSuffix = '+cet1024w';

  /// Menu paths we are willing to touch: letters, digits, dashes, slashes.
  static final _menuPathRe = RegExp(r'^(/[a-zA-Z0-9\-]+)+$');

  /// Anything that could end or chain a console command. Double quotes are
  /// allowed because this transport adds them itself around values with spaces
  /// (interface names like `hAP AC2 2GHz`) — arguments are validated before
  /// quoting, and the guard checks that quotes stay balanced.
  static final _forbiddenRe = RegExp(r"""[;\n\r\[\]{}$'`\\|&<>*?]""");

  /// Start of a `key=value` field in terse/detail output: preceded by
  /// whitespace or line start, and the key must begin with a letter. That rules
  /// out the `=` inside values like `VHTMCS:SS1=0-9` or a `-=` in a comment.
  static final _fieldRe = RegExp(r'(?:^|\s)([A-Za-z][A-Za-z0-9._\-]*)=');

  /// Console flag letters → the boolean fields REST would have returned.
  /// Without this the audit would read a disabled service as enabled: terse
  /// output marks state with a letter and omits `disabled=`.
  static const _flagFields = {
    'X': 'disabled',
    'D': 'dynamic',
    'I': 'invalid',
    'R': 'running',
    'A': 'active',
    'S': 'slave',
    'B': 'bound',
  };

  /// Signal fields across stacks — used to tell whether `print stats` already
  /// carries the numbers we came for.
  static const _signalKeys = ['signal-strength', 'rx-signal', 'signal'];

  /// ANSI/VT sequences RouterOS may still emit.
  static final _ansiRe = RegExp(r'\x1B\[[0-9;?]*[a-zA-Z]');

  SshTransport({
    required this.host,
    required this.username,
    required this.password,
    int? port,
    this.timeout = const Duration(seconds: 10),
  }) : port = port ?? 22;

  @override
  String get kind => 'SSH';

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect() async {
    // First try with the console-tuning suffix; some setups (RADIUS users,
    // exotic ROS builds) reject it, so fall back to the bare username.
    try {
      _client = await _login('$username$_consoleSuffix');
    } on SSHAuthFailError {
      try {
        _client = await _login(username);
      } on SSHAuthFailError {
        // Also what RouterOS answers when the user's group lacks `ssh` policy.
        throw RouterOsException(
            'Authentication failed (SSH) — check the password and that the '
            "user's group has the `ssh` policy");
      }
    }

    // Cheap authenticated probe: proves the console answers and that this user
    // may read at all, before the poll loop starts. It bypasses the queue on
    // purpose — a reconnect happens *inside* a queued command, and waiting for
    // that queue here would deadlock.
    final identity =
        await _execOnce(_readOnlyCommand('/system identity print'));
    if (identity.trim().isEmpty) {
      throw RouterOsException('SSH connected but the console returned nothing');
    }
  }

  Future<SSHClient> _login(String user) async {
    final socket =
        await SSHSocket.connect(host, port, timeout: timeout).timeout(timeout);
    final client = SSHClient(
      socket,
      username: user,
      onPasswordRequest: () => password,
    );
    try {
      await client.authenticated.timeout(timeout);
    } catch (e) {
      client.close();
      if (e is SSHAuthFailError) rethrow;
      throw RouterOsException(_friendly(e));
    }
    return client;
  }

  String _friendly(Object e) {
    if (e is TimeoutException) return 'SSH timed out';
    if (e is SSHAuthFailError) return 'Authentication failed (SSH)';
    if (e is SSHError) return 'SSH error: ${e.toString()}';
    return e.toString();
  }

  @override
  Future<void> close() async {
    _client?.close();
    _client = null;
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  }) async {
    validateReadFields(fields);
    final menu = _consoleMenu(menuPath);
    final isRegTable = menuPath.endsWith('registration-table');

    // Which print flavour to ask for, in order:
    //   * `stats` — registration tables only: plain `terse` hides the runtime
    //     numbers (signal, rates, uptime) that the whole app is about;
    //   * `terse` — one `key=value` record per line, the workhorse;
    //   * `print` — single-record menus (e.g. /system/resource) reject both of
    //     the above and answer with an aligned `label: value` block.
    final variants = [if (isRegTable) 'print stats', 'print terse', 'print'];
    final projection =
        fields == null || fields.isEmpty ? '' : ' proplist=${fields.join(',')}';

    var rows = <Map<String, String>>[];
    String? lastError;
    for (final variant in variants) {
      final out = await _run('$menu $variant$projection');
      if (_isSyntaxError(out)) {
        lastError = out.trim().split('\n').first;
        continue; // this flavour isn't supported here — try the next
      }
      rows = parseRecords(out);
      if (rows.isEmpty) {
        final single = parseLabelled(out);
        if (single.isNotEmpty) rows = [single];
      }
      lastError = null;
      break;
    }
    if (lastError != null) {
      throw RouterOsException('$menuPath: $lastError');
    }

    // Classic wireless keeps `signal-strength` in the plain table rather than
    // in stats; if stats came back without any signal, merge terse on top.
    if (isRegTable &&
        rows.isNotEmpty &&
        !rows.any((r) => _signalKeys.any(r.containsKey))) {
      final terse = await _run('$menu print terse');
      if (!_isSyntaxError(terse)) _mergeByMac(rows, parseRecords(terse));
    }

    if (filters != null && filters.isNotEmpty) {
      // Filtering client-side, as the contract allows — registration tables
      // and ARP caches are small, and it keeps the command line free of user
      // input.
      rows = rows
          .where((r) => filters.entries.every((f) => r[f.key] == f.value))
          .toList();
    }
    if (fields != null && fields.isNotEmpty) {
      rows = rows.map((row) => projectReadFields(row, fields)).toList();
    }
    return rows;
  }

  @override
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  ) async {
    validateReadOnlyCommand(path, params);
    final menu = _consoleMenu(path);
    // `{'.id': 'wlan1', 'once': ''}` → `/interface wireless monitor wlan1 once`
    final args = <String>[];
    final id = params['.id'] ?? params['numbers'];
    if (id != null && id.isNotEmpty) args.add(_quoteArg(id));
    params.forEach((k, v) {
      if (k == '.id' || k == 'numbers') return;
      args.add(v.isEmpty ? _quoteArg(k) : '$k=${_quoteArg(v)}');
    });

    final out = await _run(([menu, ...args]).join(' '));
    if (_isSyntaxError(out)) {
      throw RouterOsException('$path: ${out.trim().split('\n').first}');
    }
    // `monitor once` answers with an aligned block, so that parser wins here;
    // a few commands do print records instead.
    final rows = parseRecords(out);
    if (rows.isNotEmpty && rows.any((r) => r.isNotEmpty)) return rows;
    final single = parseLabelled(out);
    return single.isEmpty ? const [] : [single];
  }

  // ---------------------------------------------------------------------------
  // Command execution
  // ---------------------------------------------------------------------------

  /// Serialises the command, runs it, and returns stdout+stderr as text.
  Future<String> _run(String command) {
    final safe = _readOnlyCommand(command);
    final result = _queue.then((_) => _exec(safe));
    // Keep the chain alive even if this command failed.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Runs the command, reconnecting once if the SSH session died in between.
  ///
  /// Android suspends sockets while the app is in the background and RouterOS
  /// drops idle sessions, so a connection that worked a minute ago can be gone.
  /// Without this retry every read after a resume failed, and the audit quietly
  /// drew conclusions from empty data.
  Future<String> _exec(String command) async {
    try {
      return await _execOnce(command);
    } catch (e) {
      if (_reconnecting || !_isDeadSession(e)) rethrow;
      _reconnecting = true;
      try {
        await close();
        await connect();
        return await _execOnce(command);
      } finally {
        _reconnecting = false;
      }
    }
  }

  Future<String> _execOnce(String command) async {
    final client = _client;
    if (client == null) throw RouterOsException('Not connected');
    try {
      final res = await client.runWithResult(command).timeout(timeout);
      final text = utf8.decode(res.stdout, allowMalformed: true) +
          utf8.decode(res.stderr, allowMalformed: true);
      return text.replaceAll(_ansiRe, '').replaceAll('\r', '');
    } catch (e) {
      if (e is RouterOsException) rethrow;
      throw RouterOsException(_friendly(e));
    }
  }

  /// A dropped session, as opposed to a refused command or a bad password —
  /// only the former is worth reconnecting for.
  bool _isDeadSession(Object e) {
    if (_client == null) return false;
    final s = e.toString().toLowerCase();
    return s.contains('transport is closed') ||
        s.contains('connection closed') ||
        s.contains('socket') ||
        s.contains('timed out') ||
        s.contains('broken pipe');
  }

  /// `/interface/wifi/registration-table` → `/interface wifi registration-table`
  ///
  /// The space form is understood by both RouterOS 6 and 7 consoles.
  String _consoleMenu(String menuPath) {
    if (!_menuPathRe.hasMatch(menuPath)) {
      throw RouterOsException('Refusing suspicious menu path: $menuPath');
    }
    return '/${menuPath.substring(1).split('/').join(' ')}';
  }

  /// Quotes an argument that contains spaces (RouterOS interface names often
  /// do: `hAP AC2 2GHz`). Rejects anything that could break out of the quotes.
  String _quoteArg(String value) {
    if (_forbiddenRe.hasMatch(value) || value.contains('"')) {
      throw RouterOsException('Refusing suspicious argument: $value');
    }
    return value.contains(' ') ? '"$value"' : value;
  }

  /// Last line of defence: only `print` and `monitor … once` may leave here.
  String _readOnlyCommand(String command) {
    final line = command.trim();
    if (_forbiddenRe.hasMatch(line)) {
      throw RouterOsException('Refusing command with control characters');
    }
    if (line.split('"').length.isEven) {
      throw RouterOsException('Refusing command with unbalanced quotes');
    }
    final words = line.split(RegExp(r'\s+'));
    final verbIndex = words.indexWhere((w) => w == 'print' || w == 'monitor');
    if (!line.startsWith('/') || verbIndex < 1) {
      throw RouterOsException('Refusing non-read-only command: $line');
    }
    if (words[verbIndex] == 'monitor' && !words.contains('once')) {
      throw RouterOsException('Refusing a streaming monitor (needs `once`)');
    }
    // Nothing after the verb may look like another verb.
    const banned = {
      'set',
      'add',
      'remove',
      'reset',
      'reset-configuration',
      'enable',
      'disable',
      'unset',
      'move',
      'edit',
      'import',
      'export',
      'reboot',
      'shutdown',
      'upgrade',
      'downgrade',
      'install',
      'scan',
      'sniff',
      'reset-counters',
      'clear',
      'password',
      'renew',
      'release',
      'kill',
    };
    for (final w in words) {
      if (banned.contains(w)) {
        throw RouterOsException('Refusing non-read-only command: $line');
      }
    }
    return line;
  }

  bool _isSyntaxError(String out) {
    final head = out.toLowerCase();
    return head.contains('syntax error') ||
        head.contains('expected end of command') ||
        head.contains('bad command name') ||
        head.contains('no such command') ||
        head.contains('invalid command name') ||
        head.contains('no such item') ||
        head.contains('unknown argument') ||
        head.contains('not enough permissions');
  }

  // ---------------------------------------------------------------------------
  // Output parsing
  // ---------------------------------------------------------------------------

  /// Parses `print terse` / `print stats` / `print detail` output into rows:
  ///
  /// ```
  ///  0 HC address=192.168.88.10 mac-address=AA:BB:CC:DD:EE:FF interface=bridge
  ///  1 ;;; -= Kitchen switch =-
  ///    interface=hAP AC3 2GHz rx-signal=-75 tx-rate="39Mbps-20MHz/1S"
  /// ```
  ///
  /// A record starts at a leading index; a line without one continues the
  /// record above it (detail/stats put fields on their own line, and long terse
  /// lines can wrap). Flag letters become boolean fields, `;;;` becomes
  /// `comment`.
  @visibleForTesting
  static List<Map<String, String>> parseRecords(String out) {
    final rows = <Map<String, String>>[];
    for (final raw in out.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty) continue;

      final index = RegExp(r'^(\d+)\s*(.*)$').firstMatch(line);
      if (index != null) {
        rows.add(<String, String>{});
        line = index.group(2)!;
      } else if (rows.isEmpty) {
        // Detail output of a single-record menu comes without an index.
        if (!_fieldRe.hasMatch(' $line')) continue;
        rows.add(<String, String>{});
      }
      final row = rows.last;

      // `;;;` introduces a comment, but only when it precedes the fields — a
      // comment *value* may itself contain semicolons.
      final firstField = _fieldRe.firstMatch(' $line')?.start ?? line.length;
      final commentAt = line.indexOf(';;;');
      if (commentAt >= 0 && commentAt <= firstField) {
        final text = line.substring(commentAt + 3).trim();
        if (text.isNotEmpty) row['comment'] = text;
        line = line.substring(0, commentAt);
      }

      // Everything before the first field is flag letters (` HC `, ` X `).
      final head =
          line.length <= firstField ? line : line.substring(0, firstField);
      for (final letter in head.replaceAll(RegExp(r'[^A-Z]'), '').split('')) {
        final field = _flagFields[letter];
        if (field != null) row[field] = 'true';
      }

      row.addAll(_parseFields(line));
    }
    return rows;
  }

  /// Splits `key=value key=value` into a map.
  ///
  /// Values are *not* quoted in terse output and routinely contain spaces
  /// (`interface=hAP AC2 2GHz ssid=SlipKo Wi-Fi`), so tokens are cut at the next
  /// key boundary rather than at whitespace. `stats`/`detail` output does quote
  /// such values — the quotes are stripped.
  static Map<String, String> _parseFields(String line) {
    final out = <String, String>{};
    final keys = _fieldRe.allMatches(' $line').toList();
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i].group(1)!;
      // Offsets are against ' $line', so shift by one back onto `line`.
      final valueStart = keys[i].end - 1;
      final valueEnd =
          i + 1 < keys.length ? keys[i + 1].start - 1 : line.length;
      var value = line.substring(valueStart, valueEnd).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = _normalizeBool(value);
    }
    return out;
  }

  /// The console prints booleans as `yes`/`no`, REST as `true`/`false`. Callers
  /// (the audit above all) compare against `'true'`, so the console form is
  /// translated here — otherwise NTP-on would read as NTP-off over SSH.
  static String _normalizeBool(String value) {
    if (value == 'yes') return 'true';
    if (value == 'no') return 'false';
    return value;
  }

  /// Folds [extra] rows into [rows] by MAC — used when the signal lives in a
  /// different print flavour than the rest of the record.
  void _mergeByMac(
    List<Map<String, String>> rows,
    List<Map<String, String>> extra,
  ) {
    final byMac = <String, Map<String, String>>{};
    for (final r in extra) {
      final mac = (r['mac-address'] ?? '').toLowerCase();
      if (mac.isNotEmpty) byMac[mac] = r;
    }
    for (final row in rows) {
      final match = byMac[(row['mac-address'] ?? '').toLowerCase()];
      if (match == null) continue;
      match.forEach((k, v) => row.putIfAbsent(k, () => v));
    }
  }

  /// Parses the aligned `label: value` block that plain `print` and
  /// `monitor once` produce, e.g. `noise-floor: -101`.
  @visibleForTesting
  static Map<String, String> parseLabelled(String out) {
    final row = <String, String>{};
    for (final raw in out.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith(';;;')) continue;
      // Several labels can share a line: `status: running-ap  channel: 2412`.
      for (final m
          in RegExp(r'([a-z0-9\-]+):\s*([^\s].*?)(?=\s{2,}[a-z0-9\-]+:|$)')
              .allMatches(line)) {
        row[m.group(1)!] = _normalizeBool(m.group(2)!.trim());
      }
    }
    return row;
  }
}
