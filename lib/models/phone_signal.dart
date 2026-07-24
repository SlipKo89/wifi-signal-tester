/// How *our device* hears the access point, read from the local Wi-Fi chip.
class PhoneSignal {
  /// RSSI in dBm as the phone measures it (negative, e.g. -48).
  final int? rssiDbm;

  final String? ssid;
  final String? bssid;

  /// Our IPv4 on the Wi-Fi interface — the key we use to find our MAC on the
  /// router (works around Android 10+ randomized MAC).
  final String? ipAddress;
  final String? gatewayIp;

  /// Channel frequency in MHz.
  final int? frequencyMhz;

  const PhoneSignal({
    this.rssiDbm,
    this.ssid,
    this.bssid,
    this.ipAddress,
    this.gatewayIp,
    this.frequencyMhz,
  });

  /// Rough SNR estimate: RSSI above an assumed noise floor. The AP-side SNR
  /// from MikroTik is the trustworthy one; this is only a hint.
  int? get estimatedSnr {
    if (rssiDbm == null) return null;
    const assumedNoiseFloor = -95;
    return rssiDbm! - assumedNoiseFloor;
  }

  String get band {
    if (frequencyMhz == null) return '—';
    if (frequencyMhz! >= 5925) return '6 GHz';
    if (frequencyMhz! >= 4900) return '5 GHz';
    return '2.4 GHz';
  }
}
