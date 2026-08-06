/// Read-only, rule-based diagnosis of the current Wi-Fi link.
///
/// The engine deliberately reports correlations and likely causes, not facts it
/// cannot prove. A finding is emitted only after several consecutive samples so
/// a single bad ping or rate change does not produce a warning.
enum LinkIssueKind {
  routerLoad,
  packetLoss,
  lowCcq,
  strongSignalLowSnr,
  lowRate,
  uplinkAsymmetry,
  downlinkAsymmetry,
  highLatency,
  weakCoverage,
}

enum LinkIssueSeverity { warning, critical }

class LinkDiagnosticFinding {
  final LinkIssueKind kind;
  final LinkIssueSeverity severity;

  const LinkDiagnosticFinding(this.kind, this.severity);
}

class LinkDiagnosticSample {
  final DateTime timestamp;
  final int? phoneRssi;
  final int? apSignal;
  final int? phoneSnr;
  final int? apSnr;
  final bool phoneSnrEstimated;
  final bool apSnrEstimated;
  final int? delta;
  final int? txCcq;
  final int? rxCcq;
  final double? phoneRateMbps;
  final double? apTxRateMbps;
  final double? apRxRateMbps;
  final int? pThroughputKbps;
  final int? pingAvgMs;
  final int? pingLossPct;
  final int pingSamples;
  final int? cpuLoad;

  const LinkDiagnosticSample({
    required this.timestamp,
    this.phoneRssi,
    this.apSignal,
    this.phoneSnr,
    this.apSnr,
    this.phoneSnrEstimated = false,
    this.apSnrEstimated = false,
    this.delta,
    this.txCcq,
    this.rxCcq,
    this.phoneRateMbps,
    this.apTxRateMbps,
    this.apRxRateMbps,
    this.pThroughputKbps,
    this.pingAvgMs,
    this.pingLossPct,
    this.pingSamples = 0,
    this.cpuLoad,
  });
}

class LinkDiagnosticSummary {
  final int? phoneRssi;
  final int? apSignal;
  final int? phoneSnr;
  final int? apSnr;
  final bool phoneSnrEstimated;
  final bool apSnrEstimated;
  final int? delta;
  final int? txCcq;
  final int? rxCcq;
  final double? phoneRateMbps;
  final double? apTxRateMbps;
  final double? apRxRateMbps;
  final int? pThroughputKbps;
  final int? pingAvgMs;
  final int? pingLossPct;
  final int pingSamples;
  final int? cpuLoad;

  const LinkDiagnosticSummary({
    this.phoneRssi,
    this.apSignal,
    this.phoneSnr,
    this.apSnr,
    this.phoneSnrEstimated = false,
    this.apSnrEstimated = false,
    this.delta,
    this.txCcq,
    this.rxCcq,
    this.phoneRateMbps,
    this.apTxRateMbps,
    this.apRxRateMbps,
    this.pThroughputKbps,
    this.pingAvgMs,
    this.pingLossPct,
    this.pingSamples = 0,
    this.cpuLoad,
  });

  int? get lowestCcq {
    final values = [txCcq, rxCcq].whereType<int>().toList();
    if (values.isEmpty) return null;
    values.sort();
    return values.first;
  }

  double? get lowestRateMbps {
    final values = [phoneRateMbps, apTxRateMbps, apRxRateMbps]
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;
    values.sort();
    return values.first;
  }
}

class LinkDiagnosticReport {
  final int sampleCount;
  final int requiredSamples;
  final int windowSeconds;
  final LinkDiagnosticSummary summary;
  final List<LinkDiagnosticFinding> findings;

  const LinkDiagnosticReport({
    required this.sampleCount,
    required this.requiredSamples,
    required this.windowSeconds,
    required this.summary,
    required this.findings,
  });

  bool get ready => sampleCount >= requiredSamples;
  bool get healthy => ready && findings.isEmpty;
  bool get hasProblems => ready && findings.isNotEmpty;
  LinkDiagnosticFinding? get primary =>
      findings.isEmpty ? null : findings.first;
}

class LinkDiagnosticsEngine {
  static const int requiredSamples = 6;
  static const int maxSamples = 8;

  final List<LinkDiagnosticSample> _samples = [];

  LinkDiagnosticReport get report => _buildReport();

  void add(LinkDiagnosticSample sample) {
    _samples.add(sample);
    if (_samples.length > maxSamples) _samples.removeAt(0);
  }

  void clear() => _samples.clear();

  LinkDiagnosticReport _buildReport() {
    final summary = LinkDiagnosticSummary(
      phoneRssi: _medianInt(_samples.map((s) => s.phoneRssi)),
      apSignal: _medianInt(_samples.map((s) => s.apSignal)),
      phoneSnr: _medianInt(_samples.map((s) => s.phoneSnr)),
      apSnr: _medianInt(_samples.map((s) => s.apSnr)),
      phoneSnrEstimated: _majority(_samples.map((s) => s.phoneSnrEstimated)),
      apSnrEstimated: _majority(_samples.map((s) => s.apSnrEstimated)),
      delta: _medianInt(_samples.map((s) => s.delta)),
      txCcq: _medianInt(_samples.map((s) => s.txCcq)),
      rxCcq: _medianInt(_samples.map((s) => s.rxCcq)),
      phoneRateMbps: _medianDouble(_samples.map((s) => s.phoneRateMbps)),
      apTxRateMbps: _medianDouble(_samples.map((s) => s.apTxRateMbps)),
      apRxRateMbps: _medianDouble(_samples.map((s) => s.apRxRateMbps)),
      pThroughputKbps: _medianInt(_samples.map((s) => s.pThroughputKbps)),
      pingAvgMs: _medianInt(_samples.map((s) => s.pingAvgMs)),
      pingLossPct: _medianInt(_samples.map((s) => s.pingLossPct)),
      pingSamples: _samples.isEmpty
          ? 0
          : _samples.map((s) => s.pingSamples).reduce((a, b) => a > b ? a : b),
      cpuLoad: _medianInt(_samples.map((s) => s.cpuLoad)),
    );

    final seconds = _samples.length < 2
        ? 0
        : _samples.last.timestamp
            .difference(_samples.first.timestamp)
            .inSeconds
            .abs();
    if (_samples.length < requiredSamples) {
      return LinkDiagnosticReport(
        sampleCount: _samples.length,
        requiredSamples: requiredSamples,
        windowSeconds: seconds,
        summary: summary,
        findings: const [],
      );
    }

    final findings = <LinkDiagnosticFinding>[];
    final phoneStrong = (summary.phoneRssi ?? -100) >= -67;
    final apStrong = summary.apSignal == null || summary.apSignal! >= -67;
    final linkStrong = phoneStrong && apStrong;
    final pingReliable = summary.pingSamples >= requiredSamples;
    final highLatency = pingReliable && (summary.pingAvgMs ?? 0) >= 80;
    final estimatedLostPings =
        ((summary.pingLossPct ?? 0) * summary.pingSamples / 100).round();
    final packetLoss = pingReliable && estimatedLostPings >= 2;
    final cpuObserved = _samples.where((s) => s.cpuLoad != null).length >= 3;
    final ccqObserved =
        _samples.where((s) => s.txCcq != null || s.rxCcq != null).length >= 3;
    final snrObserved =
        _samples.where((s) => s.phoneSnr != null || s.apSnr != null).length >=
            3;
    final rateObserved = _samples
            .where((s) =>
                s.phoneRateMbps != null ||
                s.apTxRateMbps != null ||
                s.apRxRateMbps != null ||
                s.pThroughputKbps != null)
            .length >=
        3;
    final deltaObserved = _samples.where((s) => s.delta != null).length >= 3;

    // High router load is only a likely cause when it coincides with degraded
    // gateway latency/loss. CPU load alone is not a Wi-Fi fault.
    if (linkStrong &&
        cpuObserved &&
        (summary.cpuLoad ?? 0) >= 85 &&
        (highLatency || packetLoss)) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.routerLoad,
        _criticalPing(summary)
            ? LinkIssueSeverity.critical
            : LinkIssueSeverity.warning,
      ));
    }

    if (linkStrong && packetLoss) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.packetLoss,
        (summary.pingLossPct ?? 0) >= 20
            ? LinkIssueSeverity.critical
            : LinkIssueSeverity.warning,
      ));
    }

    final ccq = summary.lowestCcq;
    if (linkStrong && ccqObserved && ccq != null && ccq < 70) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.lowCcq,
        ccq < 50 ? LinkIssueSeverity.critical : LinkIssueSeverity.warning,
      ));
    }

    final snrs = [summary.phoneSnr, summary.apSnr].whereType<int>().toList();
    if (linkStrong && snrObserved && snrs.isNotEmpty) {
      snrs.sort();
      if (snrs.first < 20) {
        findings.add(LinkDiagnosticFinding(
          LinkIssueKind.strongSignalLowSnr,
          snrs.first < 15
              ? LinkIssueSeverity.critical
              : LinkIssueSeverity.warning,
        ));
      }
    }

    final lowNegotiatedRate = (summary.lowestRateMbps ?? double.infinity) < 24;
    final lowEstimatedThroughput =
        summary.pThroughputKbps != null && summary.pThroughputKbps! < 10000;
    if (linkStrong &&
        rateObserved &&
        (lowNegotiatedRate || lowEstimatedThroughput)) {
      findings.add(const LinkDiagnosticFinding(
        LinkIssueKind.lowRate,
        LinkIssueSeverity.warning,
      ));
    }

    final delta = summary.delta;
    if (deltaObserved && delta != null && delta <= -12) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.uplinkAsymmetry,
        delta <= -18 ? LinkIssueSeverity.critical : LinkIssueSeverity.warning,
      ));
    } else if (deltaObserved && delta != null && delta >= 12) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.downlinkAsymmetry,
        delta >= 18 ? LinkIssueSeverity.critical : LinkIssueSeverity.warning,
      ));
    }

    if (linkStrong && highLatency) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.highLatency,
        (summary.pingAvgMs ?? 0) >= 150
            ? LinkIssueSeverity.critical
            : LinkIssueSeverity.warning,
      ));
    }

    final weakestSignal = [summary.phoneRssi, summary.apSignal]
        .whereType<int>()
        .fold<int?>(null, (v, e) => v == null || e < v ? e : v);
    if (weakestSignal != null && weakestSignal < -75) {
      findings.add(LinkDiagnosticFinding(
        LinkIssueKind.weakCoverage,
        weakestSignal < -82
            ? LinkIssueSeverity.critical
            : LinkIssueSeverity.warning,
      ));
    }

    return LinkDiagnosticReport(
      sampleCount: _samples.length,
      requiredSamples: requiredSamples,
      windowSeconds: seconds,
      summary: summary,
      findings: List.unmodifiable(findings),
    );
  }

  static bool _criticalPing(LinkDiagnosticSummary s) =>
      (s.pingLossPct ?? 0) >= 20 || (s.pingAvgMs ?? 0) >= 150;

  static int? _medianInt(Iterable<int?> source) {
    final values = source.whereType<int>().toList()..sort();
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return ((values[middle - 1] + values[middle]) / 2).round();
  }

  static double? _medianDouble(Iterable<double?> source) {
    final values = source.whereType<double>().toList()..sort();
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  static bool _majority(Iterable<bool> source) {
    var yes = 0;
    var total = 0;
    for (final value in source) {
      total++;
      if (value) yes++;
    }
    return total > 0 && yes * 2 >= total;
  }

  /// Parses RouterOS values such as `866.6Mbps-80MHz/2S/SGI`, `54Mbps` or
  /// `1Gbps` into Mbps. Returns null instead of guessing unknown formats.
  static double? parseRateMbps(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*([gmk])?bps', caseSensitive: false)
        .firstMatch(raw);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    return switch (match.group(2)?.toLowerCase()) {
      'g' => value * 1000,
      'k' => value / 1000,
      _ => value,
    };
  }
}
