import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
  final int sampleCount;
  const SessionInfo(this.id, this.startedMs, this.sampleCount);
}

/// Local SQLite store for recorded measurement sessions.
class HistoryStore {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'wifi_history.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started INTEGER NOT NULL
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
        await db.execute(
            'CREATE INDEX idx_samples_session ON samples(session_id)');
      },
    );
    return _db!;
  }

  Future<int> startSession(int startedMs) async {
    final db = await _open();
    return db.insert('sessions', {'started': startedMs});
  }

  Future<void> addSample(int sessionId, Sample s) async {
    final db = await _open();
    await db.insert('samples', s.toRow(sessionId));
  }

  Future<List<SessionInfo>> sessions() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT s.id, s.started, COUNT(m.id) AS n
      FROM sessions s LEFT JOIN samples m ON m.session_id = s.id
      GROUP BY s.id ORDER BY s.started DESC''');
    return rows
        .map((r) => SessionInfo(
              r['id'] as int,
              r['started'] as int,
              (r['n'] as int?) ?? 0,
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
    await db.delete('samples', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<void> clearAll() async {
    final db = await _open();
    await db.delete('samples');
    await db.delete('sessions');
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
}
