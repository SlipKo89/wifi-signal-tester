/// A deliberately small, sanitised snapshot from
/// `/interface lte monitor <interface> once`.
///
/// RouterOS also returns IMEI, IMSI and ICCID in the same response. They are
/// intentionally not represented here, so SIM/modem identifiers cannot leak
/// into the UI, logs, history or support bundles by accident.
class LteSignal {
  final DateTime sampledAt;
  final String interfaceName;
  final String? status;
  final bool registered;
  final String? manufacturer;
  final String? modemModel;
  final String? revision;
  final String? operatorName;
  final String? technology;
  final String? sessionUptime;

  final double? rsrp;
  final double? rsrq;
  final double? sinr;
  final double? rssi;
  final int? cqi;

  final String? band;
  final String? carrierAggregation;
  final double? bandwidthMhz;
  final int? earfcn;
  final int? physicalCellId;
  final String? enbId;
  final String? sectorId;
  final String? cellId;

  const LteSignal({
    required this.sampledAt,
    required this.interfaceName,
    required this.registered,
    this.status,
    this.manufacturer,
    this.modemModel,
    this.revision,
    this.operatorName,
    this.technology,
    this.sessionUptime,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
    this.cqi,
    this.band,
    this.carrierAggregation,
    this.bandwidthMhz,
    this.earfcn,
    this.physicalCellId,
    this.enbId,
    this.sectorId,
    this.cellId,
  });

  factory LteSignal.fromMonitor(
    Map<String, String> row, {
    required String interfaceName,
    DateTime? sampledAt,
  }) {
    final status = _first(row, const ['registration-status', 'status']);
    final statusText = status?.toLowerCase() ?? '';
    final operator = _clean(row['current-operator']);
    final rsrp = _number(row['rsrp']);

    // Some modem drivers say `registered`, while newer MBIM modems only say
    // `running`. A populated operator/RSRP is stronger evidence than either
    // spelling, and keeps the check compatible across RouterOS generations.
    final explicitlyRegistered =
        RegExp(r'(^|[\s,])registered($|[\s,])').hasMatch(statusText);
    final explicitlyNotRegistered = statusText.contains('not-registered') ||
        statusText.contains('denied') ||
        statusText.contains('searching');
    final registered = !explicitlyNotRegistered &&
        (explicitlyRegistered ||
            statusText == 'running' ||
            operator != null ||
            rsrp != null);

    final primaryBand = _clean(row['primary-band']);
    final earfcnText = _clean(row['earfcn']);
    final caBand = _clean(row['ca-band']);
    final band = _band(primaryBand) ?? _band(earfcnText) ?? _band(row['band']);

    return LteSignal(
      sampledAt: sampledAt ?? DateTime.now(),
      interfaceName: interfaceName,
      status: status,
      registered: registered,
      manufacturer: _clean(row['manufacturer']),
      modemModel: _clean(row['model']),
      revision: _clean(row['revision']),
      operatorName: operator,
      technology: _first(row, const ['access-technology', 'data-class']),
      sessionUptime: _clean(row['session-uptime']),
      rsrp: rsrp,
      rsrq: _number(row['rsrq']),
      sinr: _number(row['sinr']),
      rssi: _number(row['rssi']),
      cqi: _integer(row['cqi']),
      band: band,
      carrierAggregation: caBand,
      bandwidthMhz: _bandwidth(primaryBand) ?? _bandwidth(earfcnText),
      earfcn: _integer(earfcnText) ?? _labelledInteger(primaryBand, 'earfcn'),
      physicalCellId: _integer(row['phy-cellid']),
      enbId: _clean(row['enb-id']),
      sectorId: _clean(row['sector-id']),
      cellId: _first(row, const ['current-cellid', 'cellid']),
    );
  }

  bool get hasRadioMetrics =>
      rsrp != null || rsrq != null || sinr != null || rssi != null;

  static String? _first(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = _clean(row[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _clean(String? raw) {
    var value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value.isEmpty ? null : value;
  }

  static double? _number(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(raw);
    return match == null
        ? null
        : double.tryParse(match.group(0)!.replaceAll(',', '.'));
  }

  static int? _integer(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'-?\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static int? _labelledInteger(String? raw, String label) {
    if (raw == null) return null;
    final match =
        RegExp('$label\\s*:\\s*(\\d+)', caseSensitive: false).firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String? _band(String? raw) {
    if (raw == null) return null;
    final b = RegExp(r'\bB(\d+)\b', caseSensitive: false).firstMatch(raw);
    if (b != null) return 'B${b.group(1)}';
    final word =
        RegExp(r'\bband\s+(\d+)\b', caseSensitive: false).firstMatch(raw);
    return word == null ? null : 'B${word.group(1)}';
  }

  static double? _bandwidth(String? raw) {
    if (raw == null) return null;
    final at = RegExp(r'@(\d+(?:[.,]\d+)?)\s*MHz', caseSensitive: false)
        .firstMatch(raw);
    final word = RegExp(
      r'bandwidth\s+(\d+(?:[.,]\d+)?)\s*MHz',
      caseSensitive: false,
    ).firstMatch(raw);
    final value = at?.group(1) ?? word?.group(1);
    return value == null ? null : double.tryParse(value.replaceAll(',', '.'));
  }
}
