import 'dart:io';

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
  final bool _isMacOS;
  final Duration queryTimeout;
  final Future<String?> Function()? _wifiNameReader;
  final Future<String?> Function()? _wifiBssidReader;
  final Future<String?> Function()? _wifiIpReader;
  final Future<String?> Function()? _gatewayReader;

  PhoneWifiService({
    bool? isMacOS,
    this.queryTimeout = const Duration(seconds: 2),
    Future<String?> Function()? wifiNameReader,
    Future<String?> Function()? wifiBssidReader,
    Future<String?> Function()? wifiIpReader,
    Future<String?> Function()? gatewayReader,
  })  : _isMacOS = isMacOS ?? Platform.isMacOS,
        _wifiNameReader = wifiNameReader,
        _wifiBssidReader = wifiBssidReader,
        _wifiIpReader = wifiIpReader,
        _gatewayReader = gatewayReader;

  Future<PhoneSignal> read() async {
    if (_isMacOS) return _readMacOS();

    // Run independent platform calls together. A stuck OEM/plugin call is
    // bounded by [_safe], so one poll can never freeze live monitoring.
    final facts = await Future.wait<Object?>([
      _safe<String>(_wifiNameReader ?? _info.getWifiName),
      _safe<String>(_wifiBssidReader ?? _info.getWifiBSSID),
      _safe<String>(_wifiIpReader ?? _info.getWifiIP),
      _safe<String>(_gatewayReader ?? _info.getWifiGatewayIP),
      _safe<int>(WiFiForIoTPlugin.getCurrentSignalStrength),
      _safe<int>(WiFiForIoTPlugin.getFrequency),
    ]);
    final ssid = _clean(facts[0] as String?);
    final bssid = _clean(facts[1] as String?);
    final ip = facts[2] as String?;
    final gateway = facts[3] as String?;
    final rssiPlugin = facts[4] as int?;
    final freqPlugin = facts[5] as int?;

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

  Future<PhoneSignal> _readMacOS() async {
    // wifi_iot and the Android MethodChannel do not exist on macOS. CoreWLAN
    // SSID/BSSID are best-effort; resolve the Wi-Fi IP in Dart and deliberately
    // skip network_info_plus's synchronous gateway sysctl path.
    final facts = await Future.wait<String?>([
      _safe<String>(_wifiNameReader ?? _info.getWifiName),
      _safe<String>(_wifiBssidReader ?? _info.getWifiBSSID),
      _safe<String>(_wifiIpReader ?? _macWifiIp),
    ]);
    return PhoneSignal(
      ssid: _clean(facts[0]),
      bssid: _clean(facts[1]),
      ipAddress: facts[2],
    );
  }

  Future<String?> _macWifiIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final ordered = [
      ...interfaces.where((i) => i.name == 'en0'),
      ...interfaces.where((i) => i.name != 'en0' && i.name.startsWith('en')),
    ];
    for (final interface in ordered) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.address.startsWith('169.254.')) {
          return address.address;
        }
      }
    }
    return null;
  }

  Future<Map?> _nativeInfo() async {
    try {
      return await _native
          .invokeMapMethod<String, dynamic>('info')
          .timeout(queryTimeout);
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
    // permission_handler does not register a macOS plugin in this project.
    // NetworkInfo remains best-effort there, without an Android GPS warning.
    if (_isMacOS) return const LocationAccess(true, true);
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
      return await fn().timeout(queryTimeout);
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
