import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app_info.dart';
import '../diagnostics/app_failure.dart';
import '../diagnostics/device_info_service.dart';
import '../diagnostics/diagnostic_log.dart';
import '../diagnostics/link_diagnostics.dart';
import '../diagnostics/support_bundle.dart';
import '../history/history_store.dart';
import '../keenetic/keenetic_service.dart';
import '../mikrotik/mikrotik_service.dart';
import '../mikrotik/router_os_transport.dart' show RouterOsException;
import '../mikrotik/ssh_host_key_store.dart';
import '../models/phone_signal.dart';
import '../models/station_signal.dart';
import '../router/wifi_router_service.dart';
import '../services/beeper.dart';
import '../services/phone_wifi_service.dart';
import '../services/ping_service.dart';
import '../wifi_logs/wifi_log_analysis.dart';
import '../wifi_logs/wifi_log_service.dart';

enum MonitorState { idle, connecting, connected, error }

/// A metric that fell outside its configured target.
enum ThresholdBreach { phoneSignal, apSignal, phoneSnr, apSnr, asymmetry }

/// Drives one measurement loop across one or more routers: read the phone side,
/// resolve our MAC, find the AP side on whichever router currently serves the
/// client, and keep a short history for the sparkline.
class MonitorController extends ChangeNotifier with WidgetsBindingObserver {
  static const _cleanupTimeout = Duration(seconds: 3);
  static const _activeOperationShutdownTimeout = Duration(seconds: 12);

  final List<WifiRouterService> _routers = [];
  final PhoneWifiService _phone = PhoneWifiService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();
  final WifiLogService _wifiLogService = WifiLogService();
  final DateTime _startedAt = DateTime.now();
  final Beeper _beeper;
  final PingService _ping;

  MonitorController({
    HistoryStore? historyStore,
    Beeper? beeper,
    PingService? pingService,
  })  : history = historyStore ?? HistoryStore(),
        _beeper = beeper ?? Beeper(),
        _ping = pingService ?? PingService() {
    WidgetsBinding.instance.addObserver(this);
    diagnosticLog.record('APP-START', 'Monitoring controller started');
  }

  MonitorState state = MonitorState.idle;
  AppFailure? failure;
  AppFailure? _connectionWarning;
  SshHostKeyChangedException? _pendingSshHostKeyChange;
  final DiagnosticLog diagnosticLog = DiagnosticLog();
  List<RouterConnection> _lastConfigs = const [];
  int _stationMisses = 0;
  bool _refreshing = false;
  Completer<void>? _refreshDone;
  Completer<void>? _connectDone;
  bool _shuttingDown = false;
  Future<void>? _shutdownFuture;
  int _sessionGeneration = 0;
  DateTime? lastSuccessfulPoll;
  DateTime? lastFailedPoll;

  PhoneSignal? phoneSignal;
  StationSignal? stationSignal;

  /// The router that currently has our client (for labelling).
  WifiRouterService? _serving;

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
  String? lastRoamFrom;
  String? lastRoamTo;
  String? get lastRoam => lastRoamFrom == null || lastRoamTo == null
      ? null
      : '$lastRoamFrom → $lastRoamTo';

  /// Latency to the gateway (last RTT, plus a rolling window for avg / loss).
  int? pingMs;
  bool _pinging = false;
  final List<int?> _pingWindow = [];
  String? _pingHost;
  int _pingGeneration = 0;
  int _pingRequestId = 0;

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

  /// Correlates signal, SNR, CCQ, rates, gateway latency and router CPU during
  /// one bounded run. This never changes the router or Android settings.
  final LinkDiagnosticSession _diagnostics = LinkDiagnosticSession();
  String? _diagnosticLinkKey;
  Timer? _diagnosticDelayTimer;
  String? _scheduledDiagnosticLinkKey;
  bool autoLinkDiagnostics = true;
  int linkDiagnosticDelaySeconds = 10;
  DateTime? diagnosticScheduledFor;
  DateTime? diagnosticStartedAt;
  DateTime? diagnosticCompletedAt;
  String? diagnosticApName;

  LinkDiagnosticReport get linkDiagnostics => _diagnostics.report;
  LinkDiagnosticPhase get linkDiagnosticPhase => _diagnostics.phase;
  bool get canStartLinkDiagnostic =>
      state == MonitorState.connected &&
      !offWifi &&
      phoneSignal?.rssiDbm != null &&
      _diagnosticLinkKey != null;

  int? get diagnosticWaitSecondsRemaining {
    final target = diagnosticScheduledFor;
    if (target == null || _diagnostics.phase != LinkDiagnosticPhase.waiting) {
      return null;
    }
    final milliseconds = target.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / 1000).ceil();
  }

  /// Our MAC as last resolved from ARP/DHCP. The result is cached between
  /// discovery polls and invalidated immediately when the Wi-Fi link changes.
  String? _ourMac;
  List<String> _macCandidates = const [];
  String? _identityIp;
  String? _identitySsid;
  String? _identityBssid;
  DateTime? _identityResolvedAt;
  bool _identityRetryScheduled = false;

  DateTime? _resourceReadAt;
  WifiRouterService? _resourceRouter;

  /// Last explicit, read-only RouterOS log analysis. Raw router logs are never
  /// retained here; the report contains normalized events for one selected MAC
  /// plus a small whitelist of AP infrastructure events.
  WifiLogReport? lastWifiLogReport;

  Future<WifiLogReport> analyzeWifiLogs({
    String? targetMac,
    String? targetLabel,
    String? targetInterface,
  }) async {
    final mikrotikRouters = routers;
    if (mikrotikRouters.isEmpty) {
      throw RouterOsException('Connect to a MikroTik first');
    }
    final selectedMac = targetMac ?? _ourMac;
    if (selectedMac == null || selectedMac.isEmpty) {
      throw RouterOsException(
          'Could not resolve the selected device MAC address');
    }
    final sources = await Future.wait(
      mikrotikRouters.map(_wifiLogService.readSource),
    );
    final report = WifiLogAnalyzer.analyze(
      targetMac: selectedMac,
      targetLabel: targetLabel,
      targetInterface: targetInterface ?? stationSignal?.interfaceName,
      sources: sources,
    );
    lastWifiLogReport = report;
    diagnosticLog.record(
      'WIFI-LOG-ANALYSIS',
      'Read-only Wi-Fi log analysis completed',
      details: {
        'router_count': sources.length,
        'rows_scanned': report.rowsScanned,
        'normalized_event_count': report.events.length,
        'severity': report.severity.name,
        'debug_logging_available': report.hasDebug,
      },
    );
    notifyListeners();
    return report;
  }

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
  DateTime? _lastBytesAt;

  /// Persistent recording (our own app data only).
  final HistoryStore history;
  int? _recordingSessionId;
  String? _recordingRouterHost;
  bool get recording => _recordingSessionId != null;

  Timer? _timer;
  Duration pollInterval = const Duration(seconds: 2);
  Duration healthPollInterval = const Duration(seconds: 15);
  Duration identityPollInterval = const Duration(seconds: 30);
  bool _lifecyclePaused = false;
  bool _resumeLiveAfterBackground = false;
  bool get isLive => _timer != null;

  int get routerCount => _routers.length;
  List<MikrotikService> get routers =>
      List.unmodifiable(_routers.whereType<MikrotikService>());
  bool get hasMikrotikRouters => routers.isNotEmpty;
  bool get hasKeeneticRouters => _routers.any(
        (router) => router.vendor == RouterVendor.keenetic,
      );
  WifiRouterService? get _primary =>
      _serving ?? (_routers.isEmpty ? null : _routers.first);
  String? get stackLabel => _primary?.stackLabel;
  String? get transportKind => _primary?.transportKind;
  String? get platformLabel => _primary?.platformLabel;
  bool get keeneticAlpha => _primary?.vendor == RouterVendor.keenetic;
  String? get keeneticModel => keeneticAlpha ? _primary?.deviceModel : null;
  String? get keeneticRelease =>
      keeneticAlpha ? _primary?.softwareVersion : null;
  bool get keeneticCompatibilityVerified =>
      keeneticAlpha && (_primary?.compatibilityVerified ?? false);

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
  Future<void> connect(List<RouterConnection> cfgs) {
    if (_shuttingDown) return Future.value();
    final done = Completer<void>();
    _connectDone = done;
    return _connectTracked(cfgs, done);
  }

  Future<void> _connectTracked(
    List<RouterConnection> cfgs,
    Completer<void> done,
  ) async {
    try {
      await _connectInternal(cfgs);
    } finally {
      if (!done.isCompleted) done.complete();
      if (identical(_connectDone, done)) _connectDone = null;
    }
  }

  Future<void> _connectInternal(List<RouterConnection> cfgs) async {
    _sessionGeneration++;
    final generation = _sessionGeneration;
    state = MonitorState.connecting;
    phoneOnly = false;
    failure = null;
    _connectionWarning = null;
    _pendingSshHostKeyChange = null;
    lastWifiLogReport = null;
    _lastConfigs = List.unmodifiable(cfgs);
    diagnosticLog.record(
      'CONNECT-START',
      'Connecting to configured routers',
      details: {'router_count': cfgs.length},
    );
    _resetDiagnostics();
    notifyListeners();

    final access = await _phone.ensureLocationAccess();
    if (_shuttingDown || generation != _sessionGeneration) return;
    locationGranted = access.granted;
    locationServiceOn = access.serviceOn;

    await _closeRouters();
    if (_shuttingDown || generation != _sessionGeneration) return;
    final failures = <({RouterConnection config, Object error})>[];
    for (final cfg in cfgs) {
      final WifiRouterService svc = switch (cfg.vendor) {
        RouterVendor.mikrotik =>
          MikrotikService(onEvent: _recordTransportEvent),
        RouterVendor.keenetic => KeeneticService(),
      };
      try {
        await svc.connect(cfg);
        if (_shuttingDown || generation != _sessionGeneration) {
          await _closeRouter(svc);
          return;
        }
        _routers.add(svc);
        diagnosticLog.record(
          'CONNECT-OK',
          'Router connected',
          details: {
            'host': cfg.host,
            'vendor': svc.vendor.name,
            'transport': svc.transportKind,
            'wireless_stack': svc.stackLabel,
          },
        );
      } catch (e) {
        if (_shuttingDown || generation != _sessionGeneration) {
          await _closeRouter(svc);
          return;
        }
        if (e is SshHostKeyChangedException) {
          _pendingSshHostKeyChange ??= e;
        }
        failures.add((config: cfg, error: e));
        final classified = AppFailure.classify(e);
        diagnosticLog.record(
          classified.code,
          'Router connection failed',
          details: {
            'host': cfg.host,
            'vendor': cfg.vendor.name,
            'transport_preference': cfg.transport.name,
            'failure_kind': classified.kind.name,
            'technical': classified.technical,
          },
        );
        await _closeRouter(svc);
      }
    }

    if (_shuttingDown || generation != _sessionGeneration) return;

    if (_routers.isEmpty) {
      state = MonitorState.error;
      failure = failures.isEmpty
          ? AppFailure.classify('No router configuration supplied')
          : AppFailure.classify(
              _pendingSshHostKeyChange ?? failures.last.error,
            );
      lastFailedPoll = DateTime.now();
      notifyListeners();
      return;
    }

    state = MonitorState.connected;
    _serving = null;
    _resetPollingCaches();
    lastWifiLogReport = null;
    _connectionWarning = _pendingSshHostKeyChange != null
        ? AppFailure.classify(_pendingSshHostKeyChange!)
        : failures.isEmpty
            ? null
            : AppFailure.partial(failures.length, cfgs.length);
    failure = _connectionWarning;
    notifyListeners();
    await refresh();
    startLive();
  }

  /// Monitor only the phone's own Wi-Fi, no router connection.
  Future<void> startPhoneOnly() async {
    if (_shuttingDown) return;
    _sessionGeneration++;
    final generation = _sessionGeneration;
    lastWifiLogReport = null;
    final access = await _phone.ensureLocationAccess();
    if (_shuttingDown || generation != _sessionGeneration) return;
    locationGranted = access.granted;
    locationServiceOn = access.serviceOn;
    await _closeRouters();
    if (_shuttingDown || generation != _sessionGeneration) return;
    _resetDiagnostics();
    _resetPollingCaches();
    _serving = null;
    phoneOnly = true;
    _lastConfigs = const [];
    state = MonitorState.connected;
    failure = null;
    _connectionWarning = null;
    _pendingSshHostKeyChange = null;
    diagnosticLog.record('PHONE-ONLY', 'Phone-only monitoring started');
    notifyListeners();
    await refresh();
    startLive();
  }

  void startLive() {
    if (_shuttingDown) return;
    if (_lifecyclePaused) {
      _resumeLiveAfterBackground = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    if (autoLinkDiagnostics &&
        _diagnostics.phase == LinkDiagnosticPhase.idle &&
        _diagnosticLinkKey != null) {
      _scheduleLinkDiagnostic(_diagnosticLinkKey!);
    }
    notifyListeners();
  }

  void stopLive() {
    _resumeLiveAfterBackground = false;
    _timer?.cancel();
    _timer = null;
    if (_diagnostics.phase == LinkDiagnosticPhase.waiting ||
        _diagnostics.phase == LinkDiagnosticPhase.collecting) {
      _cancelDiagnosticRun(logEvent: false);
    }
    notifyListeners();
  }

  /// One measurement pass. Never throws — failures land in [failure].
  Future<void> refresh() async {
    if (_refreshing || _shuttingDown) return;
    _refreshing = true;
    final done = Completer<void>();
    _refreshDone = done;
    final generation = _sessionGeneration;
    try {
      final phone = await _phone.read();
      if (generation != _sessionGeneration) return;
      phoneSignal = phone;

      // No Wi-Fi (mobile data / disconnected): don't hammer unreachable routers.
      if (phone.ssid == null && phone.ipAddress == null) {
        offWifi = true;
        stationSignal = null;
        _serving = null;
        connectedApName = null;
        _resetPollingCaches();
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

      // A network/BSSID change makes the cached randomized MAC untrustworthy.
      // In steady state, ARP/DHCP is intentionally read at a slower cadence
      // than the registration table used for the live signal.
      final networkChanged = _syncIdentityNetwork(phone);
      final now = DateTime.now();
      final orderedRouters = _orderedRouters(phone.bssid);
      if (!phoneOnly &&
          phone.ipAddress != null &&
          _identityDiscoveryDue(now, force: networkChanged)) {
        await _resolveOurMac(
          phone.ipAddress!,
          orderedRouters,
          now,
          generation,
        );
        if (generation != _sessionGeneration) return;
      }

      // Registration tables remain on the fast signal cadence. Start with the
      // BSSID-owning / previously serving router to avoid querying every router
      // after the serving AP is known.
      stationSignal = null;
      _serving = null;
      if (!phoneOnly && _macCandidates.isNotEmpty) {
        for (final candidateMac in List<String>.of(_macCandidates)) {
          for (final svc in orderedRouters) {
            final station = await svc.fetchStation(candidateMac);
            if (generation != _sessionGeneration) return;
            if (station != null) {
              stationSignal = station;
              _serving = svc;
              _ourMac = candidateMac;
              _macCandidates = [
                candidateMac,
                ..._macCandidates.where(
                  (mac) => mac.toLowerCase() != candidateMac.toLowerCase(),
                ),
              ];
              if (_identityRetryScheduled) {
                _identityResolvedAt = now;
                _identityRetryScheduled = false;
              }
              break;
            }
          }
          if (stationSignal != null) break;
        }
      }
      if (!phoneOnly && stationSignal == null && _ourMac != null) {
        // A stale ARP entry or an Android randomized-MAC change should recover
        // soon, but not by re-reading every router on every signal tick.
        _scheduleIdentityRetry(now);
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
      final previousLinkKey = _diagnosticLinkKey;
      final linkChanged = linkKey != null && linkKey != previousLinkKey;
      if (linkChanged) {
        pingMs = null;
        _pingWindow.clear();
        _pingGeneration++;
      }
      _diagnosticLinkKey = linkKey;

      // Roaming: detect when the serving AP changes.
      final apNow = stationSignal?.interfaceName ?? connectedApName;
      final roamed =
          apNow != null && _lastApName != null && apNow != _lastApName;
      if (roamed) {
        roamCount++;
        lastRoamFrom = _lastApName;
        lastRoamTo = apNow;
        diagnosticLog.record(
          'WIFI-ROAM',
          'Serving access point changed',
          details: {'from_ap_name': _lastApName, 'to_ap_name': apNow},
        );
      }
      if (apNow != null) _lastApName = apNow;

      // Wait for the new radio link to settle before taking the six samples.
      // A changed BSSID is the primary trigger; AP-name detection is a fallback
      // for Android builds that hide the BSSID.
      if (linkKey != null && (linkChanged || (roamed && !linkChanged))) {
        _scheduleLinkDiagnostic(linkKey);
      }

      // Router health is useful context, but not part of the live RF graph.
      // Keep the last sample and refresh it on its own slower cadence.
      await _refreshRouterResource(_serving, now);
      if (generation != _sessionGeneration) return;

      // Latency to the gateway (non-blocking).
      _pingTarget(phone.gatewayIp ?? _serving?.host);

      _computeThroughput(DateTime.now());
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
      if (!done.isCompleted) done.complete();
      if (identical(_refreshDone, done)) _refreshDone = null;
    }
    if (_shuttingDown || generation != _sessionGeneration) return;
    notifyListeners();
  }

  /// Live throughput from the AP's cumulative byte counters between polls.
  void _computeThroughput(DateTime sampledAt) {
    final s = stationSignal;
    if (s == null || s.apTxBytes == null || s.apRxBytes == null) {
      downKbps = upKbps = null;
      _lastTxBytes = _lastRxBytes = _lastBytesMac = null;
      _lastBytesAt = null;
      return;
    }
    final secs = _lastBytesAt == null
        ? 0.0
        : sampledAt.difference(_lastBytesAt!).inMilliseconds / 1000.0;
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
    _lastBytesAt = sampledAt;
  }

  Future<void> _recordIfNeeded() async {
    final id = _recordingSessionId;
    if (id == null) return;
    final currentServingHost = servingHost;
    if (_recordingRouterHost == null && currentServingHost != null) {
      await history.setRouterHostIfEmpty(id, currentServingHost);
      _recordingRouterHost = currentServingHost;
    }
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
    _recordingRouterHost = servingHost ??
        (_lastConfigs.length == 1 ? _lastConfigs.first.host : null);
    _recordingSessionId = await history.startSession(
      DateTime.now().millisecondsSinceEpoch,
      routerHost: _recordingRouterHost,
    );
    notifyListeners();
  }

  void stopRecording() {
    _recordingSessionId = null;
    _recordingRouterHost = null;
    notifyListeners();
  }

  /// Applies changed settings (poll interval / history length / alerts) live.
  void applySettings({
    required int pollSeconds,
    required int healthPollSeconds,
    required int identityPollSeconds,
    required int historyLength,
    bool? alertsEnabled,
    int? alertThresholdDb,
    int? minSignalDbm,
    int? minSnrDb,
    bool? autoLinkDiagnostics,
    int? linkDiagnosticDelaySeconds,
  }) {
    historyLimit = historyLength;
    if (alertsEnabled != null) this.alertsEnabled = alertsEnabled;
    if (alertThresholdDb != null) this.alertThresholdDb = alertThresholdDb;
    if (minSignalDbm != null) this.minSignalDbm = minSignalDbm;
    if (minSnrDb != null) this.minSnrDb = minSnrDb;
    final autoChanged = autoLinkDiagnostics != null &&
        autoLinkDiagnostics != this.autoLinkDiagnostics;
    final delayChanged = linkDiagnosticDelaySeconds != null &&
        linkDiagnosticDelaySeconds != this.linkDiagnosticDelaySeconds;
    if (autoLinkDiagnostics != null) {
      this.autoLinkDiagnostics = autoLinkDiagnostics;
    }
    if (linkDiagnosticDelaySeconds != null) {
      this.linkDiagnosticDelaySeconds = linkDiagnosticDelaySeconds.clamp(0, 30);
    }
    while (phoneHistory.length > historyLimit) {
      phoneHistory.removeAt(0);
    }
    while (apHistory.length > historyLimit) {
      apHistory.removeAt(0);
    }
    final next = Duration(seconds: pollSeconds.clamp(1, 30));
    healthPollInterval = Duration(seconds: healthPollSeconds.clamp(5, 300));
    identityPollInterval =
        Duration(seconds: identityPollSeconds.clamp(10, 600));
    if (next != pollInterval) {
      pollInterval = next;
      if (isLive) startLive();
    }
    if (!this.autoLinkDiagnostics &&
        _diagnostics.phase == LinkDiagnosticPhase.waiting) {
      _cancelDiagnosticRun(logEvent: false);
    } else if (this.autoLinkDiagnostics &&
        isLive &&
        _diagnosticLinkKey != null &&
        (_diagnostics.phase == LinkDiagnosticPhase.idle ||
            (delayChanged &&
                _diagnostics.phase == LinkDiagnosticPhase.waiting))) {
      _scheduleLinkDiagnostic(_diagnosticLinkKey!);
    } else if (autoChanged && !this.autoLinkDiagnostics) {
      _cancelDiagnosticTimer();
    }
    notifyListeners();
  }

  /// Starts a focused diagnosis now. If live polling was paused, it is resumed
  /// because the run needs fresh measurements to finish.
  void startLinkDiagnostic() {
    if (!canStartLinkDiagnostic) return;
    if (!isLive) startLive();
    _beginLinkDiagnostic(automatic: false);
  }

  void cancelLinkDiagnostic() {
    _cancelDiagnosticRun(logEvent: true);
    notifyListeners();
  }

  void _scheduleLinkDiagnostic(String linkKey) {
    _cancelDiagnosticTimer();
    if (!autoLinkDiagnostics) {
      _diagnostics.reset();
      diagnosticScheduledFor = null;
      diagnosticStartedAt = null;
      diagnosticCompletedAt = null;
      diagnosticApName = null;
      notifyListeners();
      return;
    }
    _diagnostics.waitForStableLink();
    _scheduledDiagnosticLinkKey = linkKey;
    diagnosticScheduledFor =
        DateTime.now().add(Duration(seconds: linkDiagnosticDelaySeconds));
    diagnosticStartedAt = null;
    diagnosticCompletedAt = null;
    diagnosticApName = _currentDiagnosticApName;

    diagnosticLog.record(
      'LINK-DIAG-WAIT',
      'Connection diagnosis scheduled after link stabilization',
      details: {
        'delay_seconds': linkDiagnosticDelaySeconds,
        'ap_name': diagnosticApName,
      },
    );

    if (linkDiagnosticDelaySeconds == 0) {
      _beginLinkDiagnostic(automatic: true);
      return;
    }
    _diagnosticDelayTimer = Timer(
      Duration(seconds: linkDiagnosticDelaySeconds),
      () {
        if (_scheduledDiagnosticLinkKey != _diagnosticLinkKey ||
            state != MonitorState.connected ||
            offWifi ||
            !isLive) {
          return;
        }
        _beginLinkDiagnostic(automatic: true);
      },
    );
    notifyListeners();
  }

  void _beginLinkDiagnostic({required bool automatic}) {
    if (!canStartLinkDiagnostic) return;
    _cancelDiagnosticTimer();
    _diagnostics.start();
    diagnosticScheduledFor = null;
    diagnosticStartedAt = DateTime.now();
    diagnosticCompletedAt = null;
    diagnosticApName = _currentDiagnosticApName;
    diagnosticLog.record(
      'LINK-DIAG-START',
      automatic
          ? 'Automatic connection diagnosis started'
          : 'Manual connection diagnosis started',
      details: {
        'automatic': automatic,
        'ap_name': diagnosticApName,
      },
    );
    notifyListeners();
  }

  String? get _currentDiagnosticApName =>
      stationSignal?.interfaceName ?? connectedApName ?? phoneSignal?.ssid;

  void _cancelDiagnosticTimer() {
    _diagnosticDelayTimer?.cancel();
    _diagnosticDelayTimer = null;
    _scheduledDiagnosticLinkKey = null;
  }

  void _cancelDiagnosticRun({required bool logEvent}) {
    final wasActive = _diagnostics.phase == LinkDiagnosticPhase.waiting ||
        _diagnostics.phase == LinkDiagnosticPhase.collecting;
    _cancelDiagnosticTimer();
    _diagnostics.reset();
    diagnosticScheduledFor = null;
    diagnosticStartedAt = null;
    diagnosticCompletedAt = null;
    diagnosticApName = null;
    if (logEvent && wasActive) {
      diagnosticLog.record(
          'LINK-DIAG-CANCEL', 'Connection diagnosis cancelled by user');
    }
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

    final completed = _diagnostics.add(LinkDiagnosticSample(
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
    if (completed) {
      diagnosticCompletedAt = DateTime.now();
      final report = _diagnostics.report;
      diagnosticLog.record(
        'LINK-DIAG-COMPLETE',
        'Connection diagnosis completed',
        details: {
          'ap_name': diagnosticApName,
          'sample_count': report.sampleCount,
          'window_seconds': report.windowSeconds,
          'findings': report.findings.map((f) => f.kind.name).toList(),
        },
      );
    }
  }

  void _pingTarget(String? host) {
    if (_shuttingDown ||
        _lifecyclePaused ||
        host == null ||
        !_ping.isSupported) {
      return;
    }
    if (_pingHost != host) {
      unawaited(_cancelPing());
      _pingHost = host;
      pingMs = null;
      _pingWindow.clear();
      _pingGeneration++;
    }
    if (_pinging) return;
    final requestedHost = host;
    final requestedGeneration = _pingGeneration;
    final requestId = ++_pingRequestId;
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
    }).whenComplete(() {
      if (requestId == _pingRequestId) {
        _pinging = false;
        notifyListeners();
      }
    });
  }

  Future<void> _cancelPing() async {
    _pingRequestId++;
    _pinging = false;
    await _ping.cancel();
  }

  void _resetDiagnostics() {
    unawaited(_cancelPing());
    _cancelDiagnosticTimer();
    _diagnostics.reset();
    _diagnosticLinkKey = null;
    diagnosticScheduledFor = null;
    diagnosticStartedAt = null;
    diagnosticCompletedAt = null;
    diagnosticApName = null;
    _pingHost = null;
    _pingGeneration++;
    pingMs = null;
    _pingWindow.clear();
  }

  bool _syncIdentityNetwork(PhoneSignal phone) {
    final bssid = phone.bssid?.toLowerCase();
    final previousBssid = _identityBssid?.toLowerCase();
    final changed = phone.ipAddress != _identityIp ||
        (phone.ssid != null && phone.ssid != _identitySsid) ||
        (bssid != null && previousBssid != null && bssid != previousBssid) ||
        (bssid != null && _identityIp == null);
    if (changed) {
      _ourMac = null;
      _macCandidates = const [];
      _identityResolvedAt = null;
      _identityRetryScheduled = false;
    }
    _identityIp = phone.ipAddress;
    if (phone.ssid != null) _identitySsid = phone.ssid;
    if (phone.bssid != null) _identityBssid = phone.bssid;
    return changed;
  }

  bool _identityDiscoveryDue(DateTime now, {required bool force}) {
    if (force || _identityResolvedAt == null) return true;
    return now.difference(_identityResolvedAt!) >= identityPollInterval;
  }

  Future<void> _resolveOurMac(
    String ip,
    List<WifiRouterService> routers,
    DateTime now,
    int generation,
  ) async {
    _identityResolvedAt = now;
    _identityRetryScheduled = false;
    final candidates = <String>[];
    for (final router in routers) {
      final resolved = await router.resolveMacForIp(ip);
      if (generation != _sessionGeneration) return;
      if (resolved != null &&
          !candidates.any(
            (candidate) => candidate.toLowerCase() == resolved.toLowerCase(),
          )) {
        candidates.add(resolved);
      }
    }
    if (candidates.isNotEmpty) {
      _macCandidates = candidates;
      _ourMac = candidates.first;
      return;
    }
    _scheduleIdentityRetry(now);
  }

  void _scheduleIdentityRetry(DateTime now) {
    if (_identityRetryScheduled) return;
    const retryAfter = Duration(seconds: 5);
    _identityResolvedAt = now.subtract(identityPollInterval - retryAfter);
    _identityRetryScheduled = true;
  }

  List<WifiRouterService> _orderedRouters(String? bssid) {
    final result = <WifiRouterService>[];

    void add(WifiRouterService router) {
      if (!result.any((candidate) => identical(candidate, router))) {
        result.add(router);
      }
    }

    if (bssid != null) {
      for (final router in _routers) {
        if (router.apNameForBssid(bssid) != null) add(router);
      }
    }
    final serving = _serving;
    if (serving != null) add(serving);
    for (final router in _routers) {
      add(router);
    }
    return result;
  }

  Future<void> _refreshRouterResource(
    WifiRouterService? serving,
    DateTime now,
  ) async {
    if (serving == null) {
      routerResource = null;
      _resourceRouter = null;
      _resourceReadAt = null;
      return;
    }
    final routerChanged = !identical(serving, _resourceRouter);
    if (routerChanged) {
      _resourceRouter = serving;
      _resourceReadAt = null;
      routerResource = null;
    }
    final lastRead = _resourceReadAt;
    if (lastRead != null && now.difference(lastRead) < healthPollInterval) {
      return;
    }
    _resourceReadAt = now;
    try {
      final resource = await serving.readResource();
      if (resource != null) routerResource = resource;
    } catch (error) {
      diagnosticLog.record(
        'ROUTER-HEALTH-READ',
        'Optional router health read failed',
        details: {'host': serving.host, 'error': error.toString()},
      );
    }
  }

  void _resetPollingCaches() {
    _ourMac = null;
    _macCandidates = const [];
    _identityIp = null;
    _identitySsid = null;
    _identityBssid = null;
    _identityResolvedAt = null;
    _identityRetryScheduled = false;
    routerResource = null;
    _resourceRouter = null;
    _resourceReadAt = null;
    downKbps = upKbps = null;
    _lastTxBytes = _lastRxBytes = _lastBytesMac = null;
    _lastBytesAt = null;
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
    final services = List<WifiRouterService>.of(_routers);
    _routers.clear();
    await Future.wait(services.map(_closeRouter));
  }

  Future<void> _closeRouter(WifiRouterService service) => _cleanupResource(
        'router:${service.host ?? service.vendor.name}',
        service.close,
      );

  Future<void> _cleanupResource(
    String resource,
    Future<void> Function() close,
  ) async {
    try {
      await close().timeout(_cleanupTimeout);
    } catch (error) {
      diagnosticLog.record(
        'CLEANUP-ERROR',
        'Resource cleanup failed',
        details: {'resource': resource, 'error': error.toString()},
      );
    }
  }

  Future<void> disconnect() async {
    if (_shuttingDown) {
      await shutdown();
      return;
    }
    _sessionGeneration++;
    stopLive();
    phoneOnly = false;
    _recordingSessionId = null;
    _recordingRouterHost = null;
    await _closeRouters();
    phoneSignal = null;
    stationSignal = null;
    _serving = null;
    connectedApName = null;
    lastWifiLogReport = null;
    _resetPollingCaches();
    _lastApName = null;
    roamCount = 0;
    lastRoamFrom = null;
    lastRoamTo = null;
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
    _pendingSshHostKeyChange = null;
    _stationMisses = 0;
    diagnosticLog.record('DISCONNECT', 'Monitoring disconnected');
    notifyListeners();
  }

  Future<void> retry() async {
    if (_shuttingDown) return;
    diagnosticLog.record('RETRY', 'User requested a retry');
    if (state == MonitorState.error && _lastConfigs.isNotEmpty) {
      await connect(_lastConfigs);
    } else {
      await refresh();
    }
  }

  Future<void> trustNewSshHostKey() async {
    if (_shuttingDown) return;
    final change = _pendingSshHostKeyChange;
    if (change == null) return;
    await trustChangedSshHostKey(change);
    diagnosticLog.record(
      'SSH-KEY-TRUSTED',
      'User explicitly trusted a changed SSH host key',
      details: {
        'host': change.presented.host,
        'port': change.presented.port,
        'fingerprint': change.presented.fingerprint,
      },
    );
    _pendingSshHostKeyChange = null;
    await connect(_lastConfigs);
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
          'health_poll_interval_seconds': healthPollInterval.inSeconds,
          'identity_poll_interval_seconds': identityPollInterval.inSeconds,
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
                'vendor': router.vendor.name,
                'transport': router.transportKind,
                'wireless_stack': router.stackLabel,
                'platform': router.platformLabel,
                'model': router.deviceModel,
                'software_version': router.softwareVersion,
                'alpha_integration': router.alphaIntegration,
                'compatibility_verified': router.compatibilityVerified,
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
          'platform': platformLabel,
          'software_version': routerVersion,
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
          'phase': linkDiagnosticPhase.name,
          'ap_name': diagnosticApName,
          'scheduled_for': diagnosticScheduledFor?.toUtc().toIso8601String(),
          'started_at': diagnosticStartedAt?.toUtc().toIso8601String(),
          'completed_at': diagnosticCompletedAt?.toUtc().toIso8601String(),
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
        if (lastWifiLogReport != null)
          'wifi_log_analysis': {
            'severity': lastWifiLogReport!.severity.name,
            'rows_scanned': lastWifiLogReport!.rowsScanned,
            'debug_logging_available': lastWifiLogReport!.hasDebug,
            'event_count': lastWifiLogReport!.events.length,
            'handoff_count': lastWifiLogReport!.handoffs.length,
            'event_kinds': [
              for (final event in lastWifiLogReport!.events) event.kind.name,
            ],
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
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _pauseForLifecycle();
      case AppLifecycleState.resumed:
        _resumeFromLifecycle();
      case AppLifecycleState.detached:
        unawaited(_cancelPing());
      case AppLifecycleState.inactive:
        // Permission dialogs and the notification shade may report inactive;
        // they should not interrupt a walk test.
        break;
    }
  }

  void _pauseForLifecycle() {
    if (_lifecyclePaused || _shuttingDown) return;
    _lifecyclePaused = true;
    _resumeLiveAfterBackground = isLive;
    _timer?.cancel();
    _timer = null;
    if (_diagnostics.phase == LinkDiagnosticPhase.waiting ||
        _diagnostics.phase == LinkDiagnosticPhase.collecting) {
      _cancelDiagnosticRun(logEvent: false);
    }
    unawaited(_cancelPing());
    notifyListeners();
  }

  void _resumeFromLifecycle() {
    if (!_lifecyclePaused || _shuttingDown) return;
    _lifecyclePaused = false;
    final shouldResume =
        _resumeLiveAfterBackground && state == MonitorState.connected;
    _resumeLiveAfterBackground = false;
    if (shouldResume) {
      startLive();
      unawaited(refresh());
    } else {
      notifyListeners();
    }
  }

  /// Terminal, idempotent cleanup that callers and tests may await.
  ///
  /// Flutter's [ChangeNotifier.dispose] is synchronous, so it starts this
  /// Future in the background. Screens that own a controller directly can
  /// await [shutdown] before discarding it when their lifecycle allows that.
  Future<void> shutdown() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;
    _shuttingDown = true;
    _resumeLiveAfterBackground = false;
    _sessionGeneration++;
    _timer?.cancel();
    _timer = null;
    _diagnosticDelayTimer?.cancel();
    _diagnosticDelayTimer = null;
    _recordingSessionId = null;
    _recordingRouterHost = null;
    _pingRequestId++;
    _pinging = false;
    final future = _shutdownResources();
    _shutdownFuture = future;
    return future;
  }

  Future<void> _shutdownResources() async {
    final connect = _connectDone?.future;
    final refresh = _refreshDone?.future;
    if (connect != null || refresh != null) {
      try {
        await Future.wait([
          if (connect != null) connect,
          if (refresh != null) refresh,
        ]).timeout(_activeOperationShutdownTimeout);
      } catch (error) {
        diagnosticLog.record(
          'CLEANUP-TIMEOUT',
          'Active operation did not finish before cleanup',
          details: {'error': error.toString()},
        );
      }
    }
    await Future.wait([
      _cleanupResource('ping', _ping.cancel),
      _cleanupResource('beeper', _beeper.dispose),
      _closeRouters(),
      _cleanupResource('wifi-history', history.close),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(shutdown());
    super.dispose();
  }
}
