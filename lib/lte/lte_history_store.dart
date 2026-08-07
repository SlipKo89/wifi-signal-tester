import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'lte_quality_score.dart';
import 'lte_signal.dart';

/// One LTE sample stored by this app. Modem/SIM identifiers are deliberately
/// absent, matching [LteSignal]'s privacy boundary.
class LteRecordedSample {
  final int tsMs;
  final bool registered;
  final double? rsrp;
  final double? rsrq;
  final double? sinr;
  final double? rssi;
  final int? cqi;
  final String? band;
  final double? bandwidthMhz;
  final int? earfcn;
  final int? physicalCellId;
  final String? cellId;

  const LteRecordedSample({
    required this.tsMs,
    required this.registered,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
    this.cqi,
    this.band,
    this.bandwidthMhz,
    this.earfcn,
    this.physicalCellId,
    this.cellId,
  });

  factory LteRecordedSample.fromSignal(LteSignal signal) => LteRecordedSample(
        tsMs: signal.sampledAt.millisecondsSinceEpoch,
        registered: signal.registered,
        rsrp: signal.rsrp,
        rsrq: signal.rsrq,
        sinr: signal.sinr,
        rssi: signal.rssi,
        cqi: signal.cqi,
        band: signal.band,
        bandwidthMhz: signal.bandwidthMhz,
        earfcn: signal.earfcn,
        physicalCellId: signal.physicalCellId,
        cellId: signal.cellId,
      );

  Map<String, Object?> toRow(int sessionId) => {
        'session_id': sessionId,
        'ts': tsMs,
        'registered': registered ? 1 : 0,
        'rsrp': rsrp,
        'rsrq': rsrq,
        'sinr': sinr,
        'rssi': rssi,
        'cqi': cqi,
        'band': band,
        'bandwidth_mhz': bandwidthMhz,
        'earfcn': earfcn,
        'pci': physicalCellId,
        'cell_id': cellId,
      };

  factory LteRecordedSample.fromRow(Map<String, Object?> row) =>
      LteRecordedSample(
        tsMs: row['ts'] as int,
        registered: (row['registered'] as int? ?? 0) != 0,
        rsrp: (row['rsrp'] as num?)?.toDouble(),
        rsrq: (row['rsrq'] as num?)?.toDouble(),
        sinr: (row['sinr'] as num?)?.toDouble(),
        rssi: (row['rssi'] as num?)?.toDouble(),
        cqi: (row['cqi'] as num?)?.toInt(),
        band: row['band'] as String?,
        bandwidthMhz: (row['bandwidth_mhz'] as num?)?.toDouble(),
        earfcn: (row['earfcn'] as num?)?.toInt(),
        physicalCellId: (row['pci'] as num?)?.toInt(),
        cellId: row['cell_id'] as String?,
      );

  LteQualitySample toQualitySample() => LteQualitySample(
        sampledAt: DateTime.fromMillisecondsSinceEpoch(tsMs),
        registered: registered,
        rsrp: rsrp,
        rsrq: rsrq,
        sinr: sinr,
        rssi: rssi,
        cqi: cqi,
        band: band,
        radioKey: _radioKey,
      );

  String? get _radioKey {
    if (cellId != null) return 'cell:$cellId';
    if (physicalCellId != null) return 'pci:$physicalCellId';
    return null;
  }
}

class LteMetricStats {
  final double min;
  final double average;
  final double max;

  const LteMetricStats({
    required this.min,
    required this.average,
    required this.max,
  });

  double get spread => max - min;

  static LteMetricStats? from(Iterable<num?> source) {
    final values = source
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList(growable: false);
    if (values.isEmpty) return null;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final average = values.reduce((a, b) => a + b) / values.length;
    return LteMetricStats(min: min, average: average, max: max);
  }
}

class LteSessionAnalysis {
  final int sampleCount;
  final LteMetricStats? rsrp;
  final LteMetricStats? rsrq;
  final LteMetricStats? sinr;
  final LteMetricStats? rssi;
  final LteMetricStats? cqi;
  final LteMetricStats? quality;
  final double? qualityP10;
  final String? dominantBand;
  final String? dominantCell;

  const LteSessionAnalysis({
    required this.sampleCount,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
    this.cqi,
    this.quality,
    this.qualityP10,
    this.dominantBand,
    this.dominantCell,
  });

  factory LteSessionAnalysis.fromSamples(List<LteRecordedSample> samples) {
    final qualityTimeline = LteQualityScorer.timeline(
      samples.map((sample) => sample.toQualitySample()).toList(growable: false),
    );
    final quality = LteQualityScorer.summarise(qualityTimeline);
    return LteSessionAnalysis(
      sampleCount: samples.length,
      rsrp: LteMetricStats.from(samples.map((sample) => sample.rsrp)),
      rsrq: LteMetricStats.from(samples.map((sample) => sample.rsrq)),
      sinr: LteMetricStats.from(samples.map((sample) => sample.sinr)),
      rssi: LteMetricStats.from(samples.map((sample) => sample.rssi)),
      cqi: LteMetricStats.from(samples.map((sample) => sample.cqi)),
      quality: quality == null
          ? null
          : LteMetricStats(
              min: quality.min,
              average: quality.average,
              max: quality.max,
            ),
      qualityP10: quality?.p10,
      dominantBand: _dominant(samples.map((sample) => sample.band)),
      dominantCell: _dominant(samples.map((sample) => sample.cellId)),
    );
  }

  static String? _dominant(Iterable<String?> source) {
    final counts = <String, int>{};
    for (final value in source.whereType<String>()) {
      if (value.trim().isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class LteSessionSummary {
  final int id;
  final int startedMs;
  final int endedMs;
  final String title;
  final String? router;
  final String? interfaceName;
  final String? operatorName;
  final String? technology;
  final int sampleCount;
  final double? averageRsrp;
  final double? averageRsrq;
  final double? averageSinr;

  const LteSessionSummary({
    required this.id,
    required this.startedMs,
    required this.endedMs,
    required this.title,
    required this.sampleCount,
    this.router,
    this.interfaceName,
    this.operatorName,
    this.technology,
    this.averageRsrp,
    this.averageRsrq,
    this.averageSinr,
  });

  Duration get duration => Duration(milliseconds: endedMs - startedMs);

  factory LteSessionSummary.fromRow(Map<String, Object?> row) {
    final started = row['started'] as int;
    return LteSessionSummary(
      id: row['id'] as int,
      startedMs: started,
      endedMs: (row['effective_ended'] as num?)?.toInt() ?? started,
      title: row['title'] as String? ?? '',
      router: row['router'] as String?,
      interfaceName: row['interface_name'] as String?,
      operatorName: row['operator_name'] as String?,
      technology: row['technology'] as String?,
      sampleCount: (row['sample_count'] as num?)?.toInt() ?? 0,
      averageRsrp: (row['avg_rsrp'] as num?)?.toDouble(),
      averageRsrq: (row['avg_rsrq'] as num?)?.toDouble(),
      averageSinr: (row['avg_sinr'] as num?)?.toDouble(),
    );
  }
}

/// Persistent LTE recordings. This database contains only data created by the
/// app and is separate from the Wi-Fi survey database.
class LteHistoryStore {
  Database? _db;
  Future<Database>? _opening;

  Future<Database> _open() {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    return _opening ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'lte_history.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE lte_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started INTEGER NOT NULL,
            ended INTEGER,
            title TEXT NOT NULL,
            router TEXT,
            interface_name TEXT,
            operator_name TEXT,
            technology TEXT
          )''');
        await db.execute('''
          CREATE TABLE lte_samples(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            ts INTEGER NOT NULL,
            registered INTEGER NOT NULL,
            rsrp REAL, rsrq REAL, sinr REAL, rssi REAL, cqi INTEGER,
            band TEXT, bandwidth_mhz REAL, earfcn INTEGER, pci INTEGER,
            cell_id TEXT
          )''');
        await db.execute(
          'CREATE INDEX idx_lte_samples_session '
          'ON lte_samples(session_id, ts)',
        );
      },
    );
    _db = db;
    _opening = null;
    return db;
  }

  Future<int> startSession({
    required int startedMs,
    required String title,
    String? router,
    String? interfaceName,
    String? operatorName,
    String? technology,
  }) async {
    final db = await _open();
    return db.insert('lte_sessions', {
      'started': startedMs,
      'title': title,
      'router': router,
      'interface_name': interfaceName,
      'operator_name': operatorName,
      'technology': technology,
    });
  }

  Future<void> finishSession(int id, int endedMs) async {
    final db = await _open();
    await db.update(
      'lte_sessions',
      {'ended': endedMs},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addSample(int sessionId, LteRecordedSample sample) async {
    final db = await _open();
    await db.insert('lte_samples', sample.toRow(sessionId));
  }

  Future<List<LteSessionSummary>> sessions() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT s.*,
             COUNT(m.id) AS sample_count,
             COALESCE(s.ended, MAX(m.ts), s.started) AS effective_ended,
             AVG(m.rsrp) AS avg_rsrp,
             AVG(m.rsrq) AS avg_rsrq,
             AVG(m.sinr) AS avg_sinr
      FROM lte_sessions s
      LEFT JOIN lte_samples m ON m.session_id = s.id
      GROUP BY s.id
      ORDER BY s.started DESC
    ''');
    return rows.map(LteSessionSummary.fromRow).toList(growable: false);
  }

  Future<LteSessionSummary?> session(int id) async {
    final rows = await sessions();
    for (final session in rows) {
      if (session.id == id) return session;
    }
    return null;
  }

  Future<List<LteRecordedSample>> samplesFor(int sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'lte_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'ts ASC',
    );
    return rows.map(LteRecordedSample.fromRow).toList(growable: false);
  }

  Future<void> renameSession(int id, String title) async {
    final db = await _open();
    await db.update(
      'lte_sessions',
      {'title': title.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSession(int id) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('lte_samples', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('lte_sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> clearAll() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('lte_samples');
      await txn.delete('lte_sessions');
    });
  }

  Future<String> exportCsv(int sessionId) async {
    final samples = await samplesFor(sessionId);
    final qualityTimeline = LteQualityScorer.timeline(
      samples.map((sample) => sample.toQualitySample()).toList(growable: false),
    );
    final buffer = StringBuffer(
      'timestamp_ms,registered,rsrp_dbm,rsrq_db,sinr_db,rssi_dbm,cqi,quality_score,'
      'band,bandwidth_mhz,earfcn,pci,cell_id\n',
    );
    String csv(Object? value) {
      final text = (value ?? '').toString().replaceAll('"', '""');
      return text.contains(',') || text.contains('"') ? '"$text"' : text;
    }

    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      buffer.writeln([
        sample.tsMs,
        sample.registered,
        sample.rsrp,
        sample.rsrq,
        sample.sinr,
        sample.rssi,
        sample.cqi,
        qualityTimeline[index].score?.toStringAsFixed(1),
        sample.band,
        sample.bandwidthMhz,
        sample.earfcn,
        sample.physicalCellId,
        sample.cellId,
      ].map(csv).join(','));
    }
    return buffer.toString();
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    await db?.close();
  }
}
