import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

import '../models/phone_signal.dart';

/// Result of asking for the location access that Android requires before it
/// will reveal SSID/BSSID.
class LocationAccess {
  final bool granted;
  final bool serviceOn;
  const LocationAccess(this.granted, this.serviceOn);

  bool get ok => granted && serviceOn;
}

/// Reads the local Wi-Fi chip's view of the current connection.
///
/// SSID/BSSID/IP/gateway come from network_info_plus; RSSI and frequency from
/// wifi_iot. All values are best-effort — OEM ROMs and permission states vary,
/// so any field may be null.
///
/// READ-ONLY contract: from wifi_iot we call ONLY the two getters below
/// (getCurrentSignalStrength, getFrequency). We never call any state-changing
/// method (connect / disconnect / removeWifiNetwork / setEnabled / forget).
/// The app must not modify or delete anything on the device.
class PhoneWifiService {
  final NetworkInfo _info = NetworkInfo();
  static const _native = MethodChannel('wifi_apk/phone');

  Future<PhoneSignal> read() async {
    final ssid = _clean(await _safe(_info.getWifiName));
    final bssid = _clean(await _safe(_info.getWifiBSSID));
    final ip = await _safe(_info.getWifiIP);
    final gateway = await _safe(_info.getWifiGatewayIP);
    final rssiPlugin = await _safe(WiFiForIoTPlugin.getCurrentSignalStrength);
    final freqPlugin = await _safe(WiFiForIoTPlugin.getFrequency);

    // Richer facts from the native WifiManager (link speed, standard, security).
    final n = await _nativeInfo();
    int? ni(String k) => (n?[k] as num?)?.toInt();

    return PhoneSignal(
      rssiDbm: ni('rssi') ?? rssiPlugin,
      ssid: ssid,
      bssid: bssid,
      ipAddress: ip,
      gatewayIp: gateway,
      frequencyMhz: ni('frequency') ?? freqPlugin,
      linkSpeedMbps: _pos(ni('linkSpeed')),
      txLinkSpeedMbps: _pos(ni('txLinkSpeed')),
      rxLinkSpeedMbps: _pos(ni('rxLinkSpeed')),
      wifiStandard: _standard(ni('standard')),
      security: _security(ni('security')),
    );
  }

  Future<Map?> _nativeInfo() async {
    try {
      return await _native.invokeMapMethod<String, dynamic>('info');
    } catch (_) {
      return null;
    }
  }

  int? _pos(int? v) => (v == null || v <= 0) ? null : v;

  String? _standard(int? s) {
    switch (s) {
      case 1:
        return 'Wi-Fi 4 legacy (a/b/g)';
      case 4:
        return 'Wi-Fi 4 (n)';
      case 5:
        return 'Wi-Fi 5 (ac)';
      case 6:
        return 'Wi-Fi 6 (ax)';
      case 7:
        return '802.11ad';
      case 8:
        return 'Wi-Fi 7 (be)';
      default:
        return null;
    }
  }

  String? _security(int? s) {
    switch (s) {
      case 0:
        return 'Open';
      case 1:
        return 'WEP';
      case 2:
        return 'WPA/WPA2-PSK';
      case 3:
        return 'WPA/WPA2-EAP';
      case 4:
        return 'WPA3-SAE';
      case 5:
        return 'WPA3-EAP-192';
      case 6:
        return 'Enhanced Open (OWE)';
      default:
        return null;
    }
  }

  /// Requests location permission (needed for SSID/BSSID) and reports whether
  /// the location master switch is on. Never changes anything else on the phone.
  Future<LocationAccess> ensureLocationAccess() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      final serviceOn = await Permission.location.serviceStatus.isEnabled;
      return LocationAccess(status.isGranted, serviceOn);
    } catch (_) {
      return const LocationAccess(false, false);
    }
  }

  Future<T?> _safe<T>(Future<T?> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  /// SSID comes back quoted on some platforms; BSSID may be empty/unknown.
  String? _clean(String? raw) {
    if (raw == null) return null;
    var s = raw;
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    // Android returns these placeholders when location permission is missing.
    if (s.isEmpty ||
        s == '<unknown ssid>' ||
        s == '00:00:00:00:00:00' ||
        s == '02:00:00:00:00:00') {
      return null;
    }
    return s;
  }
}
