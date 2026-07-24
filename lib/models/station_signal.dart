import 'wireless_stack.dart';

/// How the access point sees *our* station — pulled read-only from the
/// registration table. Field names differ between RouterOS stacks, so
/// [fromRecord] is tolerant and tries several keys.
class StationSignal {
  final String macAddress;

  /// Overall signal as the AP receives us, in dBm (negative, e.g. -55).
  final int? signalDbm;

  /// Signal-to-noise ratio in dB (higher is better).
  final int? snr;

  /// Per-MIMO-chain signal, when the stack reports it.
  final int? signalCh0;
  final int? signalCh1;

  final String? txRate;
  final String? rxRate;

  /// Client Connection Quality, 0..100 (legacy wireless only).
  final int? txCcq;
  final int? rxCcq;

  final String? interfaceName;
  final String? ssid;
  final String? uptime;

  const StationSignal({
    required this.macAddress,
    this.signalDbm,
    this.snr,
    this.signalCh0,
    this.signalCh1,
    this.txRate,
    this.rxRate,
    this.txCcq,
    this.rxCcq,
    this.interfaceName,
    this.ssid,
    this.uptime,
  });

  factory StationSignal.fromRecord(
    Map<String, String> r,
    WirelessStack stack,
  ) {
    return StationSignal(
      macAddress: _first(r, ['mac-address']) ?? '',
      // WifiWave2 uses `signal`; classic wireless `signal-strength`;
      // legacy CAPsMAN `rx-signal`.
      signalDbm: _int(_first(r, ['signal', 'signal-strength', 'rx-signal'])),
      snr: _int(_first(r, ['signal-to-noise', 'snr'])),
      signalCh0: _int(_first(r, ['signal-strength-ch0', 'signal-ch0'])),
      signalCh1: _int(_first(r, ['signal-strength-ch1', 'signal-ch1'])),
      txRate: _first(r, ['tx-rate']),
      rxRate: _first(r, ['rx-rate']),
      txCcq: _int(_first(r, ['tx-ccq'])),
      rxCcq: _int(_first(r, ['rx-ccq'])),
      interfaceName: _first(r, ['interface', 'name']),
      ssid: _first(r, ['ssid']),
      uptime: _first(r, ['uptime']),
    );
  }

  static String? _first(Map<String, String> r, List<String> keys) {
    for (final k in keys) {
      final v = r[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Pulls the first signed integer out of values like `-55`, `-55@6Mbps`,
  /// or `-55dBm`.
  static int? _int(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'-?\d+').firstMatch(raw);
    return m == null ? null : int.tryParse(m.group(0)!);
  }
}
