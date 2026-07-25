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

  /// Negotiated link speed (Mbps) and per-direction speeds where available.
  final int? linkSpeedMbps;
  final int? txLinkSpeedMbps;
  final int? rxLinkSpeedMbps;

  /// 802.11 generation, e.g. "Wi-Fi 6 (ax)".
  final String? wifiStandard;

  /// Security of the connection, e.g. "WPA2/WPA3-PSK", "Open".
  final String? security;

  const PhoneSignal({
    this.rssiDbm,
    this.ssid,
    this.bssid,
    this.ipAddress,
    this.gatewayIp,
    this.frequencyMhz,
    this.linkSpeedMbps,
    this.txLinkSpeedMbps,
    this.rxLinkSpeedMbps,
    this.wifiStandard,
    this.security,
  });

  /// 2.4 GHz channel number, when on 2.4 GHz.
  int? get channel24 {
    final f = frequencyMhz;
    if (f == null || f < 2400 || f > 2500) return null;
    if (f == 2484) return 14;
    return ((f - 2412) ~/ 5) + 1;
  }

  /// Channel number for any band (2.4 / 5 / 6 GHz) from the frequency.
  int? get channel {
    final f = frequencyMhz;
    if (f == null) return null;
    if (f == 2484) return 14;
    if (f >= 2412 && f <= 2472) return ((f - 2412) ~/ 5) + 1;
    if (f >= 5000 && f < 5900) return (f - 5000) ~/ 5; // 5 GHz
    if (f >= 5955 && f <= 7115) return ((f - 5950) ~/ 5); // 6 GHz
    return null;
  }

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
