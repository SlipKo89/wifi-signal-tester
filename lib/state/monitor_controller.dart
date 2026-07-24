import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../mikrotik/mikrotik_service.dart';
import '../models/phone_signal.dart';
import '../models/station_signal.dart';
import '../models/wireless_stack.dart';
import '../services/phone_wifi_service.dart';

enum MonitorState { idle, connecting, connected, error }

/// Drives one measurement loop across one or more routers: read the phone side,
/// resolve our MAC, find the AP side on whichever router currently serves the
/// client, and keep a short history for the sparkline.
class MonitorController extends ChangeNotifier {
  final List<MikrotikService> _routers = [];
  final PhoneWifiService _phone = PhoneWifiService();

  MonitorState state = MonitorState.idle;
  String? error;

  PhoneSignal? phoneSignal;
  StationSignal? stationSignal;

  /// The router that currently has our client (for labelling).
  MikrotikService? _serving;

  /// AP name derived from the phone's BSSID (works even before the client shows
  /// up in a registration table, and lets us name a foreign AP too).
  String? connectedApName;

  /// Our MAC as last resolved from ARP (re-resolved every poll).
  String? _ourMac;

  /// True when the phone isn't on Wi-Fi (e.g. switched to mobile data).
  bool offWifi = false;

  /// On Wi-Fi with an IP, but no router has this client in a registration
  /// table — a non-managed / standalone AP, so there's no AP-side signal.
  bool apUnmanaged = false;

  /// Whether we have the location access Android needs to reveal SSID/BSSID.
  bool locationGranted = true;
  bool locationServiceOn = true;

  /// Rolling RSSI (phone) / signal (AP) history, newest last.
  final List<int> phoneHistory = [];
  final List<int> apHistory = [];
  static const int historyLength = 60;

  Timer? _timer;
  Duration pollInterval = const Duration(seconds: 2);
  bool get isLive => _timer != null;

  int get routerCount => _routers.length;
  MikrotikService? get _primary => _serving ?? (_routers.isEmpty ? null : _routers.first);
  String? get stackLabel => _primary?.stack?.label;
  String? get transportKind => _primary?.transportKind;

  /// Host of the router currently serving the client — shown as "via …".
  String? get servingHost => _serving?.host;

  /// Signal delta (AP − phone) in dB — how differently the two sides hear.
  int? get signalDelta {
    final ap = stationSignal?.signalDbm;
    final ph = phoneSignal?.rssiDbm;
    if (ap == null || ph == null) return null;
    return ap - ph;
  }

  /// Connects to every configured router (best-effort — at least one must
  /// succeed). SSID/BSSID need location access, so we ask first.
  Future<void> connect(List<RouterConnection> cfgs) async {
    state = MonitorState.connecting;
    error = null;
    notifyListeners();

    final access = await _phone.ensureLocationAccess();
    locationGranted = access.granted;
    locationServiceOn = access.serviceOn;

    await _closeRouters();
    final failures = <String>[];
    for (final cfg in cfgs) {
      final svc = MikrotikService();
      try {
        await svc.connect(cfg);
        _routers.add(svc);
      } catch (e) {
        failures.add('${cfg.host}: ${_short(e)}');
        await svc.close();
      }
    }

    if (_routers.isEmpty) {
      state = MonitorState.error;
      error = 'Could not connect to any router — ${failures.join('; ')}';
      notifyListeners();
      return;
    }

    state = MonitorState.connected;
    _serving = null;
    _ourMac = null;
    error = failures.isEmpty
        ? null
        : 'Connected to ${_routers.length}/${cfgs.length}. '
            'Failed: ${failures.join('; ')}';
    notifyListeners();
    await refresh();
    startLive();
  }

  void startLive() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    notifyListeners();
  }

  void stopLive() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// One measurement pass. Never throws — failures land in [error].
  Future<void> refresh() async {
    try {
      final phone = await _phone.read();
      phoneSignal = phone;

      // No Wi-Fi (mobile data / disconnected): don't hammer unreachable routers.
      if (phone.ssid == null && phone.ipAddress == null) {
        offWifi = true;
        stationSignal = null;
        connectedApName = null;
        error = 'Phone is off Wi-Fi (mobile data?). Connect to a network '
            'served by one of your MikroTiks to see the AP side.';
        notifyListeners();
        return;
      }
      offWifi = false;

      // Which AP does the phone say it's on? (BSSID → AP name across routers.)
      connectedApName = _apNameForBssid(phone.bssid);

      // Re-resolve the MAC and search every router for the client — the phone
      // roams between APs/routers and gets a new randomized MAC per SSID.
      stationSignal = null;
      _serving = null;
      _ourMac = null;
      if (phone.ipAddress != null) {
        for (final svc in _routers) {
          final mac = await svc.resolveMacForIp(phone.ipAddress!);
          if (mac == null) continue;
          final station = await svc.fetchStation(mac);
          if (station != null) {
            stationSignal = station;
            _serving = svc;
            _ourMac = mac;
            break;
          }
          _ourMac ??= mac;
        }
      }
      apUnmanaged = phone.ipAddress != null && stationSignal == null;

      _push(phoneHistory, phone.rssiDbm);
      _push(apHistory, stationSignal?.signalDbm);
      error = null;
    } catch (e) {
      error = _friendlyError(e);
    }
    notifyListeners();
  }

  String? _apNameForBssid(String? bssid) {
    if (bssid == null) return null;
    for (final svc in _routers) {
      final name = svc.apNameForBssid(bssid);
      if (name != null) return name;
    }
    return null;
  }

  /// Turns raw exceptions into something a human can act on.
  String _friendlyError(Object e) {
    if (e is SocketException || e is TimeoutException) {
      return 'Router unreachable — check you are on its Wi-Fi and the host is '
          'correct.';
    }
    final s = e.toString();
    if (s.contains('401') || s.toLowerCase().contains('auth')) {
      return 'Authentication failed — check the username and password.';
    }
    if (s.contains('timed out') ||
        s.contains('Connection refused') ||
        s.contains('Network is unreachable') ||
        s.contains('Connection closed')) {
      return 'Router unreachable — check you are on its Wi-Fi and the host is '
          'correct.';
    }
    return s.replaceFirst('RouterOsException: ', '');
  }

  String _short(Object e) =>
      e.toString().replaceFirst('RouterOsException: ', '');

  void _push(List<int> buffer, int? value) {
    if (value == null) return;
    buffer.add(value);
    if (buffer.length > historyLength) buffer.removeAt(0);
  }

  Future<void> _closeRouters() async {
    for (final svc in _routers) {
      await svc.close();
    }
    _routers.clear();
  }

  Future<void> disconnect() async {
    stopLive();
    await _closeRouters();
    phoneSignal = null;
    stationSignal = null;
    _serving = null;
    connectedApName = null;
    _ourMac = null;
    phoneHistory.clear();
    apHistory.clear();
    state = MonitorState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _closeRouters();
    super.dispose();
  }
}
