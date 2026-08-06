import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../diagnostics/link_diagnostics.dart';
import '../history/history_store.dart';
import '../mikrotik/mikrotik_service.dart';
import '../models/phone_signal.dart';
import '../models/station_signal.dart';
import '../models/wireless_stack.dart';
import '../services/beeper.dart';
import '../services/phone_wifi_service.dart';
import '../services/ping_service.dart';

enum MonitorState { idle, connecting, connected, error }

/// A metric that fell outside its configured target.
enum ThresholdBreach { phoneSignal, apSignal, phoneSnr, apSnr, asymmetry }

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

  /// Health of the serving router (cpu-load, version, board, uptime).
  Map<String, String>? routerResource;
  int? get cpuLoad => int.tryParse(routerResource?['cpu-load'] ?? '');
  String? get routerBoard => routerResource?['board-name'];
  String? get routerVersion => routerResource?['version'];
  String? get routerUptime => routerResource?['uptime'];

  /// Roaming: which AP the client sits on, and how many times it has switched.
  String? _lastApName;
  int roamCount = 0;
  String? lastRoam;

  /// Latency to the gateway (last RTT, plus a rolling window for avg / loss).
  final PingService _ping = PingService();
  int? pingMs;
  bool _pinging = false;
  final List<int?> _pingWindow = [];
  String? _pingHost;
  int _pingGeneration = 0;

  int? get pingAvgMs {
    final ok = _pingWindow.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return (ok.reduce((a, b) => a + b) / ok.length).round();
  }

  int? get pingLossPct {
    if (_pingWindow.isEmpty) return null;
    final lost = _pingWindow.where((e) => e == null).length;
    return (lost * 100 / _pingWindow.length).round();
  }

  int get pingSampleCount => _pingWindow.length;

  /// Correlates signal, SNR, CCQ, rates, gateway latency and router CPU over a
  /// short rolling window. This never changes the router or Android settings.
  final LinkDiagnosticsEngine _diagnostics = LinkDiagnosticsEngine();
  String? _diagnosticLinkKey;
  LinkDiagnosticReport get linkDiagnostics => _diagnostics.report;

  /// Our MAC as last resolved from ARP (re-resolved every poll).
  String? _ourMac;

  /// True when the phone isn't on Wi-Fi (e.g. switched to mobile data).
  bool offWifi = false;

  /// On Wi-Fi with an IP, but no router has this client in a registration
  /// table — a non-managed / standalone AP, so there's no AP-side signal.
  bool apUnmanaged = false;

  /// Phone-only mode: monitor the device's own Wi-Fi without any router.
  bool phoneOnly = false;

  /// Whether we have the location access Android needs to reveal SSID/BSSID.
  bool locationGranted = true;
  bool locationServiceOn = true;

  /// Audible alert when the AP−phone asymmetry exceeds [alertThresholdDb].
  final Beeper _beeper = Beeper();
  bool alertsEnabled = false;
  int alertThresholdDb = 12;
  int minSignalDbm = -72;
  int minSnrDb = 20;

  /// Which targets are currently breached (empty = everything within target).
  List<ThresholdBreach> breaches = const [];

  /// Overall pass/warn state for the walk test: green when nothing is breached.
  bool get thresholdsOk => breaches.isEmpty;

  /// Rolling RSSI (phone) / signal (AP) history, newest last.
  final List<int> phoneHistory = [];
  final List<int> apHistory = [];
  int historyLimit = 60;

  /// Live throughput derived from the AP's byte counters (kbps).
  int? downKbps;
  int? upKbps;
  int? _lastTxBytes;
  int? _lastRxBytes;
  String? _lastBytesMac;

  /// Persistent recording (our own app data only).
  final HistoryStore history = HistoryStore();
  int? _recordingSessionId;
  bool get recording => _recordingSessionId != null;

  Timer? _timer;
  Duration pollInterval = const Duration(seconds: 2);
  bool get isLive => _timer != null;

  int get routerCount => _routers.length;
  List<MikrotikService> get routers => List.unmodifiable(_routers);
  MikrotikService? get _primary =>
      _serving ?? (_routers.isEmpty ? null : _routers.first);
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

  /// AP-side SNR: from the registration table if reported, otherwise estimated
  /// as rx-signal − the serving router's measured noise floor (CAPsMAN doesn't
  /// report SNR directly).
  int? get apSnr {
    final s = stationSignal;
    if (s == null) return null;
    if (s.snr != null) return s.snr;
    final nf = _serving?.noiseFloorForFreq(phoneSignal?.frequencyMhz);
    if (s.signalDbm != null && nf != null) return s.signalDbm! - nf;
    return null;
  }

  bool get apSnrIsEstimate => stationSignal?.snr == null;

  /// Phone-side SNR using the router's real noise floor when we have it, else
  /// a −95 dBm assumption.
  int? get phoneSnr {
    final rssi = phoneSignal?.rssiDbm;
    if (rssi == null) return null;
    final nf = _primary?.noiseFloorForFreq(phoneSignal?.frequencyMhz) ?? -95;
    return rssi - nf;
  }

  bool get phoneSnrIsEstimate =>
      (_primary?.noiseFloorForFreq(phoneSignal?.frequencyMhz)) == null;

  /// Connects to every configured router (best-effort — at least one must
  /// succeed). SSID/BSSID need location access, so we ask first.
  Future<void> connect(List<RouterConnection> cfgs) async {
    state = MonitorState.connecting;
    phoneOnly = false;
    error = null;
    _resetDiagnostics();
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

  /// Monitor only the phone's own Wi-Fi, no router connection.
  Future<void> startPhoneOnly() async {
    final access = await _phone.ensureLocationAccess();
    locationGranted = access.granted;
    locationServiceOn = access.serviceOn;
    await _closeRouters();
    _resetDiagnostics();
    phoneOnly = true;
    state = MonitorState.connected;
    error = null;
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
        _resetDiagnostics();
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
      apUnmanaged =
          !phoneOnly && phone.ipAddress != null && stationSignal == null;

      // Never mix samples from different APs. BSSID is the most reliable link
      // identity; interface/SSID are fallbacks when Android hides it.
      final linkKey = phone.bssid ??
          stationSignal?.interfaceName ??
          phone.ssid ??
          phone.ipAddress;
      if (_diagnosticLinkKey != null &&
          linkKey != null &&
          linkKey != _diagnosticLinkKey) {
        _diagnostics.clear();
        pingMs = null;
        _pingWindow.clear();
        _pingGeneration++;
      }
      _diagnosticLinkKey = linkKey;

      // Roaming: detect when the serving AP changes.
      final apNow = stationSignal?.interfaceName ?? connectedApName;
      if (apNow != null && _lastApName != null && apNow != _lastApName) {
        roamCount++;
        lastRoam = '$_lastApName → $apNow';
      }
      if (apNow != null) _lastApName = apNow;

      // Router health from whichever router serves the client.
      routerResource = _serving == null ? null : await _serving!.readResource();

      // Latency to the gateway (non-blocking).
      _pingTarget(phone.gatewayIp ?? _serving?.host);

      _computeThroughput();
      _push(phoneHistory, phone.rssiDbm);
      _push(apHistory, stationSignal?.signalDbm);

      _evaluateThresholds();
      _evaluateLinkDiagnostics();

      await _recordIfNeeded();
      error = null;
    } catch (e) {
      error = _friendlyError(e);
    }
    notifyListeners();
  }

  /// Live throughput from the AP's cumulative byte counters between polls.
  void _computeThroughput() {
    final s = stationSignal;
    if (s == null || s.apTxBytes == null || s.apRxBytes == null) {
      downKbps = upKbps = null;
      _lastTxBytes = _lastRxBytes = _lastBytesMac = null;
      return;
    }
    final secs = pollInterval.inMilliseconds / 1000.0;
    if (_lastBytesMac == s.macAddress &&
        _lastTxBytes != null &&
        _lastRxBytes != null &&
        secs > 0) {
      final dTx = s.apTxBytes! - _lastTxBytes!;
      final dRx = s.apRxBytes! - _lastRxBytes!;
      // Ignore counter resets (roam / reconnect).
      downKbps = dTx >= 0 ? (dTx * 8 / 1000 / secs).round() : null;
      upKbps = dRx >= 0 ? (dRx * 8 / 1000 / secs).round() : null;
    } else {
      downKbps = upKbps = null;
    }
    _lastTxBytes = s.apTxBytes;
    _lastRxBytes = s.apRxBytes;
    _lastBytesMac = s.macAddress;
  }

  Future<void> _recordIfNeeded() async {
    final id = _recordingSessionId;
    if (id == null) return;
    final ph = phoneSignal;
    final ap = stationSignal;
    await history.addSample(
      id,
      Sample(
        tsMs: DateTime.now().millisecondsSinceEpoch,
        ssid: ph?.ssid,
        apName: ap?.interfaceName ?? connectedApName,
        phoneRssi: ph?.rssiDbm,
        apSignal: ap?.signalDbm,
        apSnr: apSnr,
        delta: signalDelta,
        txRate: ap?.txRate,
        rxRate: ap?.rxRate,
        downKbps: downKbps,
        upKbps: upKbps,
      ),
    );
  }

  Future<void> startRecording() async {
    _recordingSessionId =
        await history.startSession(DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  void stopRecording() {
    _recordingSessionId = null;
    notifyListeners();
  }

  /// Applies changed settings (poll interval / history length / alerts) live.
  void applySettings({
    required int pollSeconds,
    required int historyLength,
    bool? alertsEnabled,
    int? alertThresholdDb,
    int? minSignalDbm,
    int? minSnrDb,
  }) {
    historyLimit = historyLength;
    if (alertsEnabled != null) this.alertsEnabled = alertsEnabled;
    if (alertThresholdDb != null) this.alertThresholdDb = alertThresholdDb;
    if (minSignalDbm != null) this.minSignalDbm = minSignalDbm;
    if (minSnrDb != null) this.minSnrDb = minSnrDb;
    while (phoneHistory.length > historyLimit) {
      phoneHistory.removeAt(0);
    }
    while (apHistory.length > historyLimit) {
      apHistory.removeAt(0);
    }
    final next = Duration(seconds: pollSeconds);
    if (next != pollInterval) {
      pollInterval = next;
      if (isLive) startLive();
    }
    notifyListeners();
  }

  /// Compares the live metrics against the configured targets and beeps when
  /// something is out of spec (hands-free walk testing).
  void _evaluateThresholds() {
    final found = <ThresholdBreach>[];

    final ph = phoneSignal?.rssiDbm;
    if (ph != null && ph < minSignalDbm) found.add(ThresholdBreach.phoneSignal);

    final ap = stationSignal?.signalDbm;
    if (ap != null && ap < minSignalDbm) found.add(ThresholdBreach.apSignal);

    final phSnr = phoneSnr;
    if (phSnr != null && phSnr < minSnrDb) found.add(ThresholdBreach.phoneSnr);

    final apS = apSnr;
    if (apS != null && apS < minSnrDb) found.add(ThresholdBreach.apSnr);

    final d = signalDelta;
    if (d != null && d.abs() >= alertThresholdDb) {
      found.add(ThresholdBreach.asymmetry);
    }

    breaches = found;
    if (alertsEnabled && found.isNotEmpty) _beeper.beep();
  }

  void _evaluateLinkDiagnostics() {
    final phone = phoneSignal;
    if (phone == null || phone.rssiDbm == null) return;
    final station = stationSignal;
    final phoneRates = [
      phone.linkSpeedMbps,
      phone.txLinkSpeedMbps,
      phone.rxLinkSpeedMbps,
    ].whereType<int>().toList();
    final phoneRate = phoneRates.isEmpty
        ? null
        : phoneRates.reduce((a, b) => a < b ? a : b).toDouble();

    _diagnostics.add(LinkDiagnosticSample(
      timestamp: DateTime.now(),
      phoneRssi: phone.rssiDbm,
      apSignal: station?.signalDbm,
      phoneSnr: phoneSnr,
      apSnr: apSnr,
      phoneSnrEstimated: phoneSnrIsEstimate,
      apSnrEstimated: apSnrIsEstimate,
      delta: signalDelta,
      txCcq: station?.txCcq,
      rxCcq: station?.rxCcq,
      phoneRateMbps: phoneRate,
      apTxRateMbps: LinkDiagnosticsEngine.parseRateMbps(station?.txRate),
      apRxRateMbps: LinkDiagnosticsEngine.parseRateMbps(station?.rxRate),
      pThroughputKbps: station?.pThroughputKbps,
      pingAvgMs: pingAvgMs,
      pingLossPct: pingLossPct,
      pingSamples: pingSampleCount,
      cpuLoad: cpuLoad,
    ));
  }

  void _pingTarget(String? host) {
    if (host == null) return;
    if (_pingHost != host) {
      _pingHost = host;
      pingMs = null;
      _pingWindow.clear();
      _pingGeneration++;
    }
    if (_pinging) return;
    final requestedHost = host;
    final requestedGeneration = _pingGeneration;
    _pinging = true;
    _ping.pingOnce(host).then((ms) {
      // A ping started on the previous network may finish after a roam. Do not
      // contaminate the new AP's diagnostics with that result.
      if (_pingHost == requestedHost &&
          _pingGeneration == requestedGeneration) {
        pingMs = ms;
        _pingWindow.add(ms);
        if (_pingWindow.length > 20) _pingWindow.removeAt(0);
      }
      _pinging = false;
      notifyListeners();
    });
  }

  void _resetDiagnostics() {
    _diagnostics.clear();
    _diagnosticLinkKey = null;
    _pingHost = null;
    _pingGeneration++;
    pingMs = null;
    _pingWindow.clear();
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
    if (buffer.length > historyLimit) buffer.removeAt(0);
  }

  Future<void> _closeRouters() async {
    for (final svc in _routers) {
      await svc.close();
    }
    _routers.clear();
  }

  Future<void> disconnect() async {
    stopLive();
    phoneOnly = false;
    _recordingSessionId = null;
    await _closeRouters();
    phoneSignal = null;
    stationSignal = null;
    _serving = null;
    connectedApName = null;
    _ourMac = null;
    downKbps = upKbps = null;
    _lastTxBytes = _lastRxBytes = _lastBytesMac = null;
    routerResource = null;
    _lastApName = null;
    roamCount = 0;
    lastRoam = null;
    pingMs = null;
    _pingWindow.clear();
    _pingHost = null;
    _pinging = false;
    _resetDiagnostics();
    breaches = const [];
    phoneHistory.clear();
    apHistory.clear();
    state = MonitorState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _beeper.dispose();
    _closeRouters();
    super.dispose();
  }
}
