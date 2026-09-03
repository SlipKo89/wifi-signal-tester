import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef HistoryDatabaseOpener = Future<Database> Function();

/// One recorded measurement (our own app data only).
class Sample {
  final int tsMs;
  final String? ssid;
  final String? apName;
  final int? phoneRssi;
  final int? apSignal;
  final int? apSnr;
  final int? delta;
  final String? txRate;
  final String? rxRate;
  final int? downKbps;
  final int? upKbps;

  const Sample({
    required this.tsMs,
    this.ssid,
    this.apName,
    this.phoneRssi,
    this.apSignal,
    this.apSnr,
    this.delta,
    this.txRate,
    this.rxRate,
    this.downKbps,
    this.upKbps,
  });

  Map<String, Object?> toRow(int sessionId) => {
        'session_id': sessionId,
        'ts': tsMs,
        'ssid': ssid,
        'ap_name': apName,
        'phone_rssi': phoneRssi,
        'ap_signal': apSignal,
        'ap_snr': apSnr,
        'delta': delta,
        'tx_rate': txRate,
        'rx_rate': rxRate,
        'down_kbps': downKbps,
        'up_kbps': upKbps,
      };

  factory Sample.fromRow(Map<String, Object?> r) => Sample(
        tsMs: r['ts'] as int,
        ssid: r['ssid'] as String?,
        apName: r['ap_name'] as String?,
        phoneRssi: r['phone_rssi'] as int?,
        apSignal: r['ap_signal'] as int?,
        apSnr: r['ap_snr'] as int?,
        delta: r['delta'] as int?,
        txRate: r['tx_rate'] as String?,
        rxRate: r['rx_rate'] as String?,
        downKbps: r['down_kbps'] as int?,
        upKbps: r['up_kbps'] as int?,
      );
}

class SessionInfo {
  final int id;
  final int startedMs;
  final int endedMs;
  final int sampleCount;
  final String? routerHost;

  const SessionInfo(
    this.id,
    this.startedMs,
    this.endedMs,
    this.sampleCount, {
    this.routerHost,
  });

  Duration get duration => Duration(milliseconds: endedMs - startedMs);
}

/// Local SQLite store for recorded measurement sessions.
class HistoryStore {
  final HistoryDatabaseOpener _databaseOpener;
  Database? _db;
  Future<Database>? _opening;
  Future<void>? _closing;

  HistoryStore({HistoryDatabaseOpener? databaseOpener})
      : _databaseOpener = databaseOpener ?? _openDefaultDatabase;

  Future<Database> _open() async {
    final closing = _closing;
    if (closing != null) await closing;

    final existing = _db;
    if (existing != null) return existing;
    return _opening ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    try {
      final db = await _databaseOpener();
      _db = db;
      return db;
    } finally {
      // A failed open must be retryable, while concurrent callers must all
      // share the same in-flight Future.
      _opening = null;
    }
  }

  static Future<Database> _openDefaultDatabase() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'wifi_history.db'),
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started INTEGER NOT NULL,
            router_host TEXT
          )''');
        await db.execute('''
          CREATE TABLE samples(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            ts INTEGER NOT NULL,
            ssid TEXT, ap_name TEXT,
            phone_rssi INTEGER, ap_signal INTEGER, ap_snr INTEGER, delta INTEGER,
            tx_rate TEXT, rx_rate TEXT, down_kbps INTEGER, up_kbps INTEGER
          )''');
        await db
            .execute('CREATE INDEX idx_samples_session ON samples(session_id)');
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE sessions ADD COLUMN router_host TEXT');
        }
      },
    );
  }

  Future<int> startSession(int startedMs, {String? routerHost}) async {
    final db = await _open();
    return db.insert('sessions', {
      'started': startedMs,
      'router_host': _nonEmpty(routerHost),
    });
  }

  Future<void> setRouterHostIfEmpty(int sessionId, String routerHost) async {
    final normalized = _nonEmpty(routerHost);
    if (normalized == null) return;
    final db = await _open();
    await db.rawUpdate(
      'UPDATE sessions SET router_host = ? '
      'WHERE id = ? AND (router_host IS NULL OR router_host = ?)',
      [normalized, sessionId, ''],
    );
  }

  Future<void> addSample(int sessionId, Sample s) async {
    final db = await _open();
    await db.insert('samples', s.toRow(sessionId));
  }

  Future<List<SessionInfo>> sessions() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT s.id, s.started, s.router_host, COUNT(m.id) AS n,
             COALESCE(MAX(m.ts), s.started) AS effective_ended
      FROM sessions s LEFT JOIN samples m ON m.session_id = s.id
      GROUP BY s.id ORDER BY s.started DESC''');
    return rows
        .map((r) => SessionInfo(
              r['id'] as int,
              r['started'] as int,
              (r['effective_ended'] as num?)?.toInt() ?? r['started'] as int,
              (r['n'] as int?) ?? 0,
              routerHost: r['router_host'] as String?,
            ))
        .toList();
  }

  Future<List<Sample>> samplesFor(int sessionId) async {
    final db = await _open();
    final rows = await db.query('samples',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'ts ASC');
    return rows.map(Sample.fromRow).toList();
  }

  Future<void> deleteSession(int sessionId) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(
        'samples',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  Future<void> clearAll() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('samples');
      await txn.delete('sessions');
    });
  }

  /// Renders a session as CSV text.
  Future<String> exportCsv(int sessionId) async {
    final rows = await samplesFor(sessionId);
    final b = StringBuffer(
        'timestamp_ms,ssid,ap,phone_rssi_dbm,ap_signal_dbm,ap_snr_db,'
        'delta_db,tx_rate,rx_rate,down_kbps,up_kbps\n');
    String c(Object? v) {
      final s = (v ?? '').toString();
      return s.contains(',') ? '"$s"' : s;
    }

    for (final s in rows) {
      b.writeln([
        s.tsMs,
        c(s.ssid),
        c(s.apName),
        c(s.phoneRssi),
        c(s.apSignal),
        c(s.apSnr),
        c(s.delta),
        c(s.txRate),
        c(s.rxRate),
        c(s.downKbps),
        c(s.upKbps),
      ].join(','));
    }
    return b.toString();
  }

  /// Closes the app-owned database. Concurrent close calls share one Future;
  /// a later read may open it again (useful after a controller is recreated).
  Future<void> close() => _closing ??= _closeDatabase();

  Future<void> _closeDatabase() async {
    try {
      Database? db = _db;
      final opening = _opening;
      if (db == null && opening != null) {
        try {
          db = await opening;
        } catch (_) {
          // There is no open handle to close. The next operation can retry.
        }
      }
      if (identical(_db, db)) _db = null;
      _opening = null;
      await db?.close();
    } finally {
      _closing = null;
    }
  }
}

String? _nonEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
