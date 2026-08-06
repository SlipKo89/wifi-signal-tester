import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app_info.dart';
import '../diagnostics/app_failure.dart';
import '../diagnostics/device_info_service.dart';
import '../diagnostics/diagnostic_log.dart';
import '../diagnostics/link_diagnostics.dart';
import '../diagnostics/support_bundle.dart';
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
class MonitorController extends ChangeNotifier with WidgetsBindingObserver {
  final List<MikrotikService> _routers = [];
  final PhoneWifiService _phone = PhoneWifiService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();
  final DateTime _startedAt = DateTime.now();

  MonitorController() {
    WidgetsBinding.instance.addObserver(this);
    diagnosticLog.record('APP-START', 'Monitoring controller started');
  }

  MonitorState state = MonitorState.idle;
  AppFailure? failure;
  AppFailure? _connectionWarning;
  final DiagnosticLog diagnosticLog = DiagnosticLog();
  List<RouterConnection> _lastConfigs = const [];
  int _stationMisses = 0;
  bool _refreshing = false;
  int _sessionGeneration = 0;
  DateTime? lastSuccessfulPoll;
  DateTime? lastFailedPoll;

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
    _sessionGeneration++;
    state = MonitorState.connecting;
    phoneOnly = false;
    failure = null;
    _connectionWarning = null;
    _lastConfigs = List.unmodifiable(cfgs);
    diagnosticLog.record(
      'CONNECT-START',
      'Connecting to configured routers',
      details: {'router_count': cfgs.length},
    );
    _resetDiagnostics();
    notifyListeners();

    final access = await _phone.ensureLocationAccess();
    locationGranted = access.granted;
    locationServiceOn = access.serviceOn;

    await _closeRouters();
    final failures = <({RouterConnection config, Object error})>[];
    for (final cfg in cfgs) {
      final svc = MikrotikService(onEvent: _recordTransportEvent);
      try {
        await svc.connect(cfg);
        _routers.add(svc);
        diagnosticLog.record(
          'CONNECT-OK',
          'Router connected',
          details: {
            'host': cfg.host,
            'transport': svc.transportKind,
            'wireless_stack': svc.stack?.label,
          },
        );
      } catch (e) {
        failures.add((config: cfg, error: e));
        final classified = AppFailure.classify(e);
        diagnosticLog.record(
          classified.code,
          'Router connection failed',
          details: {
            'host': cfg.host,
            'transport_preference': cfg.transport.name,
            'failure_kind': classified.kind.name,
            'technical': classified.technical,
          },
        );
        await svc.close();
      }
    }

    if (_routers.isEmpty) {
      state = MonitorState.error;
      failure = failures.isEmpty
          ? AppFailure.classify('No router configuration supplied')
          : AppFailure.classify(failures.last.error);
      lastFailedPoll = DateTime.now();
      notifyListeners();
      return;
    }

    state = MonitorState.connected;
    _serving = null;
    _ourMac = null;
    _connectionWarning = failures.isEmpty
        ? null
        : AppFailure.partial(failures.length, cfgs.length);
    failure = _connectionWarning;
    notifyListeners();
    await refresh();
    startLive();
  }

  /// Monitor only the phone's own Wi-Fi, no router connection.
  Future<void> startPhoneOnly() async {
    _sessionGeneration++;
    final access = await _phone.ensureLocationAccess();
    locationGranted = access.granted;
    locationServiceOn = access.serviceOn;
    await _closeRouters();
    _resetDiagnostics();
    phoneOnly = true;
    _lastConfigs = const [];
    state = MonitorState.connected;
    failure = null;
    _connectionWarning = null;
    diagnosticLog.record('PHONE-ONLY', 'Phone-only monitoring started');
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

  /// One measurement pass. Never throws — failures land in [failure].
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final generation = _sessionGeneration;
    try {
      final phone = await _phone.read();
      if (generation != _sessionGeneration) return;
      phoneSignal = phone;

      // No Wi-Fi (mobile data / disconnected): don't hammer unreachable routers.
      if (phone.ssid == null && phone.ipAddress == null) {
        offWifi = true;
        stationSignal = null;
        connectedApName = null;
        _resetDiagnostics();
        failure = AppFailure.offWifi();
        lastFailedPoll = DateTime.now();
        diagnosticLog.record('WIFI-01', 'Phone is not connected to Wi-Fi');
        notifyListeners();
        return;
      }
      offWifi = false;
      failure = _connectionWarning;

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
          if (generation != _sessionGeneration) return;
          if (mac == null) continue;
          final station = await svc.fetchStation(mac);
          if (generation != _sessionGeneration) return;
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
      if (apUnmanaged) {
        _stationMisses++;
        if (_stationMisses >= 3) {
          failure = AppFailure.station(knownAp: connectedApName != null);
          if (_stationMisses == 3) {
            diagnosticLog.record(
              failure!.code,
              'Client is absent from registration tables',
              details: {
                'ap_name': connectedApName,
                'bssid': phone.bssid,
              },
            );
          }
        }
      } else {
        if (_stationMisses >= 3 && stationSignal != null) {
          diagnosticLog.record(
            'STATION-RECOVERED',
            'Client returned to a registration table',
          );
        }
        _stationMisses = 0;
        failure = _connectionWarning;
      }

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
        diagnosticLog.record(
          'WIFI-ROAM',
          'Serving access point changed',
          details: {'from_ap_name': _lastApName, 'to_ap_name': apNow},
        );
      }
      if (apNow != null) _lastApName = apNow;

      // Router health from whichever router serves the client.
      routerResource = _serving == null ? null : await _serving!.readResource();
      if (generation != _sessionGeneration) return;

      // Latency to the gateway (non-blocking).
      _pingTarget(phone.gatewayIp ?? _serving?.host);

      _computeThroughput();
      _push(phoneHistory, phone.rssiDbm);
      _push(apHistory, stationSignal?.signalDbm);

      _evaluateThresholds();
      _evaluateLinkDiagnostics();

      await _recordIfNeeded();
      if (generation != _sessionGeneration) return;
      lastSuccessfulPoll = DateTime.now();
      if (!apUnmanaged) failure = _connectionWarning;
    } catch (e) {
      if (generation != _sessionGeneration) return;
      failure = AppFailure.classify(e);
      lastFailedPoll = DateTime.now();
      diagnosticLog.record(
        failure!.code,
        'Monitoring poll failed',
        details: {
          'failure_kind': failure!.kind.name,
          'technical': failure!.technical,
        },
      );
    } finally {
      _refreshing = false;
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
    _sessionGeneration++;
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
    _lastConfigs = const [];
    failure = null;
    _connectionWarning = null;
    _stationMisses = 0;
    diagnosticLog.record('DISCONNECT', 'Monitoring disconnected');
    notifyListeners();
  }

  Future<void> retry() async {
    diagnosticLog.record('RETRY', 'User requested a retry');
    if (state == MonitorState.error && _lastConfigs.isNotEmpty) {
      await connect(_lastConfigs);
    } else {
      await refresh();
    }
  }

  void dismissFailure() {
    failure = _connectionWarning;
    notifyListeners();
  }

  void clearDiagnosticLog() {
    diagnosticLog.clear();
    diagnosticLog.record(
        'LOG-CLEARED', 'User cleared the diagnostic event log');
    notifyListeners();
  }

  Future<SupportSnapshot> createSupportSnapshot(
      {required String locale}) async {
    final phone = phoneSignal;
    final station = stationSignal;
    final report = linkDiagnostics;
    final summary = report.summary;
    final device = await _deviceInfo.read();
    device.putIfAbsent('app_version', () => kAppVersion);

    return SupportSnapshot(
      createdAt: DateTime.now(),
      events: diagnosticLog.events,
      report: {
        'app': {
          'name': kAppName,
          'version': kAppVersion,
          'locale': locale,
          'controller_uptime_seconds':
              DateTime.now().difference(_startedAt).inSeconds,
          'monitor_state': state.name,
          'phone_only': phoneOnly,
          'live_polling': isLive,
          'poll_interval_seconds': pollInterval.inSeconds,
        },
        'device': device,
        'permissions': {
          'location_granted': locationGranted,
          'location_service_on': locationServiceOn,
        },
        'connection': {
          'configured_router_count': _lastConfigs.length,
          'connected_router_count': routerCount,
          'routers': [
            for (final router in _routers)
              {
                'host': router.host,
                'transport': router.transportKind,
                'wireless_stack': router.stack?.label,
                'serving': identical(router, _serving),
              },
          ],
          'serving_host': servingHost,
          'connected_ap_name': connectedApName,
          'off_wifi': offWifi,
          'ap_unmanaged': apUnmanaged,
          'station_missed_polls': _stationMisses,
          'last_successful_poll': lastSuccessfulPoll?.toUtc().toIso8601String(),
          'last_failed_poll': lastFailedPoll?.toUtc().toIso8601String(),
        },
        'phone_wifi': {
          'ssid': phone?.ssid,
          'bssid': phone?.bssid,
          'ip_address': phone?.ipAddress,
          'gateway': phone?.gatewayIp,
          'rssi_dbm': phone?.rssiDbm,
          'frequency_mhz': phone?.frequencyMhz,
          'channel': phone?.channel,
          'band': phone?.band,
          'link_speed_mbps': phone?.linkSpeedMbps,
          'tx_link_speed_mbps': phone?.txLinkSpeedMbps,
          'rx_link_speed_mbps': phone?.rxLinkSpeedMbps,
          'wifi_standard': phone?.wifiStandard,
          'security': phone?.security,
          'snr_db': phoneSnr,
          'snr_estimated': phoneSnrIsEstimate,
        },
        'ap_view': {
          'client_mac': station?.macAddress,
          'interface': station?.interfaceName,
          'ssid': station?.ssid,
          'signal_dbm': station?.signalDbm,
          'snr_db': apSnr,
          'snr_estimated': apSnrIsEstimate,
          'signal_ch0_dbm': station?.signalCh0,
          'signal_ch1_dbm': station?.signalCh1,
          'tx_rate': station?.txRate,
          'rx_rate': station?.rxRate,
          'tx_ccq_pct': station?.txCcq,
          'rx_ccq_pct': station?.rxCcq,
          'estimated_throughput_kbps': station?.pThroughputKbps,
          'live_down_kbps': downKbps,
          'live_up_kbps': upKbps,
          'signal_delta_db': signalDelta,
        },
        'router_health': {
          'board': routerBoard,
          'routeros_version': routerVersion,
          'uptime': routerUptime,
          'cpu_load_pct': cpuLoad,
        },
        'latency': {
          'target_host': _pingHost,
          'last_ms': pingMs,
          'average_ms': pingAvgMs,
          'loss_pct': pingLossPct,
          'sample_count': pingSampleCount,
        },
        'link_diagnosis': {
          'ready': report.ready,
          'sample_count': report.sampleCount,
          'window_seconds': report.windowSeconds,
          'findings': [
            for (final finding in report.findings)
              {
                'kind': finding.kind.name,
                'severity': finding.severity.name,
              },
          ],
          'summary': {
            'phone_rssi_dbm': summary.phoneRssi,
            'ap_signal_dbm': summary.apSignal,
            'phone_snr_db': summary.phoneSnr,
            'ap_snr_db': summary.apSnr,
            'delta_db': summary.delta,
            'tx_ccq_pct': summary.txCcq,
            'rx_ccq_pct': summary.rxCcq,
            'phone_rate_mbps': summary.phoneRateMbps,
            'ap_tx_rate_mbps': summary.apTxRateMbps,
            'ap_rx_rate_mbps': summary.apRxRateMbps,
            'estimated_throughput_kbps': summary.pThroughputKbps,
            'ping_average_ms': summary.pingAvgMs,
            'ping_loss_pct': summary.pingLossPct,
            'cpu_load_pct': summary.cpuLoad,
          },
        },
        'thresholds': {
          'alerts_enabled': alertsEnabled,
          'min_signal_dbm': minSignalDbm,
          'min_snr_db': minSnrDb,
          'max_asymmetry_db': alertThresholdDb,
          'breaches': breaches.map((b) => b.name).toList(),
        },
        'session': {
          'roam_count': roamCount,
          'last_roam': lastRoam,
          'phone_rssi_history': List<int>.of(phoneHistory),
          'ap_rssi_history': List<int>.of(apHistory),
        },
        if (failure != null) 'last_failure': failure!.toJson(),
      },
    );
  }

  void _recordTransportEvent(
    String code,
    String message,
    Map<String, Object?> details,
  ) {
    diagnosticLog.record(code, message, details: details);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    diagnosticLog.record(
      'APP-LIFECYCLE',
      'Application lifecycle changed',
      details: {'state': state.name},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _beeper.dispose();
    _closeRouters();
    super.dispose();
  }
}
