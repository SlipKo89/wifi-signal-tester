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

  Future<PhoneSignal> read() async {
    final ssid = _clean(await _safe(_info.getWifiName));
    final bssid = _clean(await _safe(_info.getWifiBSSID));
    final ip = await _safe(_info.getWifiIP);
    final gateway = await _safe(_info.getWifiGatewayIP);
    final rssi = await _safe(WiFiForIoTPlugin.getCurrentSignalStrength);
    final freq = await _safe(WiFiForIoTPlugin.getFrequency);

    return PhoneSignal(
      rssiDbm: rssi,
      ssid: ssid,
      bssid: bssid,
      ipAddress: ip,
      gatewayIp: gateway,
      frequencyMhz: freq,
    );
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
