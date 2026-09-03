import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

enum PollingProfile { fast, normal, economical, custom }

/// Independent read cadences used by the Wi-Fi monitor.
///
/// The registration table remains fast enough for walk tests, while router
/// health and IP-to-MAC discovery are intentionally read less often.
class PollingIntervals {
  final int signalSeconds;
  final int healthSeconds;
  final int identitySeconds;

  const PollingIntervals({
    required this.signalSeconds,
    required this.healthSeconds,
    required this.identitySeconds,
  });
}

extension PollingProfileDefaults on PollingProfile {
  PollingIntervals? get intervals => switch (this) {
        PollingProfile.fast => const PollingIntervals(
            signalSeconds: 1,
            healthSeconds: 10,
            identitySeconds: 15,
          ),
        PollingProfile.normal => const PollingIntervals(
            signalSeconds: 2,
            healthSeconds: 15,
            identitySeconds: 30,
          ),
        PollingProfile.economical => const PollingIntervals(
            signalSeconds: 5,
            healthSeconds: 30,
            identitySeconds: 60,
          ),
        PollingProfile.custom => null,
      };
}

/// App-wide preferences, persisted with SharedPreferences (non-secret).
class SettingsController extends ChangeNotifier {
  SharedPreferences? _prefs;

  // 'system' | 'en' | 'ru'
  String _lang = 'system';
  ThemeMode _themeMode = ThemeMode.dark;
  PollingProfile _pollingProfile = PollingProfile.normal;
  int _pollSeconds = 2;
  int _healthPollSeconds = 15;
  int _identityPollSeconds = 30;
  int _historyLength = 60;
  bool _alertsEnabled = false;
  int _alertThresholdDb = 12;
  int _minSignalDbm = -72;
  int _minSnrDb = 20;
  bool _autoLinkDiagnostics = true;
  int _linkDiagnosticDelaySeconds = 10;
  String _lastSeenVersion = '';

  String get lang => _lang;
  ThemeMode get themeMode => _themeMode;
  PollingProfile get pollingProfile => _pollingProfile;
  int get pollSeconds => _pollSeconds;
  int get healthPollSeconds => _healthPollSeconds;
  int get identityPollSeconds => _identityPollSeconds;
  int get historyLength => _historyLength;
  bool get alertsEnabled => _alertsEnabled;
  int get alertThresholdDb => _alertThresholdDb;

  /// Target signal / SNR: below these the dashboard warns (and alerts beep).
  int get minSignalDbm => _minSignalDbm;
  int get minSnrDb => _minSnrDb;
  bool get autoLinkDiagnostics => _autoLinkDiagnostics;
  int get linkDiagnosticDelaySeconds => _linkDiagnosticDelaySeconds;

  /// Last app version whose "What's new" the user has already seen ('' = never).
  String get lastSeenVersion => _lastSeenVersion;

  /// Resolved locale for MaterialApp (null = follow system).
  Locale? get locale => _lang == 'system' ? null : Locale(_lang);

  /// Translator for widgets. Resolves 'system' against the platform locale.
  L10n get l {
    final ru = _lang == 'ru' ||
        (_lang == 'system' &&
            WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
                'ru');
    return L10n(ru);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _lang = p.getString('lang') ?? 'system';
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == p.getString('themeMode'),
      orElse: () => ThemeMode.dark,
    );
    final legacyPollSeconds = (p.getInt('pollSeconds') ?? 2).clamp(1, 30);
    final savedProfile = p.getString('pollingProfile');
    _pollingProfile = PollingProfile.values.firstWhere(
      (profile) => profile.name == savedProfile,
      // Preserve a non-standard interval selected in older app versions.
      orElse: () => switch (legacyPollSeconds) {
        1 => PollingProfile.fast,
        2 => PollingProfile.normal,
        5 => PollingProfile.economical,
        _ => PollingProfile.custom,
      },
    );
    final preset = _pollingProfile.intervals;
    _pollSeconds = preset?.signalSeconds ?? legacyPollSeconds;
    _healthPollSeconds = preset?.healthSeconds ??
        (p.getInt('healthPollSeconds') ?? 15).clamp(5, 300);
    _identityPollSeconds = preset?.identitySeconds ??
        (p.getInt('identityPollSeconds') ?? 30).clamp(10, 600);
    _historyLength = p.getInt('historyLength') ?? 60;
    _alertsEnabled = p.getBool('alertsEnabled') ?? false;
    _alertThresholdDb = p.getInt('alertThresholdDb') ?? 12;
    _minSignalDbm = p.getInt('minSignalDbm') ?? -72;
    _minSnrDb = p.getInt('minSnrDb') ?? 20;
    _autoLinkDiagnostics = p.getBool('autoLinkDiagnostics') ?? true;
    _linkDiagnosticDelaySeconds =
        (p.getInt('linkDiagnosticDelaySeconds') ?? 10).clamp(0, 30);
    _lastSeenVersion = p.getString('lastSeenVersion') ?? '';
    notifyListeners();
  }

  Future<void> setMinSignalDbm(int v) async {
    _minSignalDbm = v.clamp(-90, -40);
    await _prefs?.setInt('minSignalDbm', _minSignalDbm);
    notifyListeners();
  }

  Future<void> setMinSnrDb(int v) async {
    _minSnrDb = v.clamp(5, 40);
    await _prefs?.setInt('minSnrDb', _minSnrDb);
    notifyListeners();
  }

  Future<void> setAutoLinkDiagnostics(bool v) async {
    _autoLinkDiagnostics = v;
    await _prefs?.setBool('autoLinkDiagnostics', v);
    notifyListeners();
  }

  Future<void> setLinkDiagnosticDelaySeconds(int v) async {
    _linkDiagnosticDelaySeconds = v.clamp(0, 30);
    await _prefs?.setInt(
        'linkDiagnosticDelaySeconds', _linkDiagnosticDelaySeconds);
    notifyListeners();
  }

  Future<void> setLastSeenVersion(String v) async {
    _lastSeenVersion = v;
    await _prefs?.setString('lastSeenVersion', v);
  }

  Future<void> setAlertsEnabled(bool v) async {
    _alertsEnabled = v;
    await _prefs?.setBool('alertsEnabled', v);
    notifyListeners();
  }

  Future<void> setAlertThresholdDb(int v) async {
    _alertThresholdDb = v.clamp(4, 30);
    await _prefs?.setInt('alertThresholdDb', _alertThresholdDb);
    notifyListeners();
  }

  Future<void> setLang(String v) async {
    _lang = v;
    await _prefs?.setString('lang', v);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode v) async {
    _themeMode = v;
    await _prefs?.setString('themeMode', v.name);
    notifyListeners();
  }

  Future<void> setPollingProfile(PollingProfile profile) async {
    _pollingProfile = profile;
    final preset = profile.intervals;
    if (preset != null) {
      _pollSeconds = preset.signalSeconds;
      _healthPollSeconds = preset.healthSeconds;
      _identityPollSeconds = preset.identitySeconds;
    }
    await _persistPollingSettings();
    notifyListeners();
  }

  Future<void> setPollSeconds(int v) async {
    _pollingProfile = PollingProfile.custom;
    _pollSeconds = v.clamp(1, 30);
    await _persistPollingSettings();
    notifyListeners();
  }

  Future<void> setHealthPollSeconds(int v) async {
    _pollingProfile = PollingProfile.custom;
    _healthPollSeconds = v.clamp(5, 300);
    await _persistPollingSettings();
    notifyListeners();
  }

  Future<void> setIdentityPollSeconds(int v) async {
    _pollingProfile = PollingProfile.custom;
    _identityPollSeconds = v.clamp(10, 600);
    await _persistPollingSettings();
    notifyListeners();
  }

  Future<void> _persistPollingSettings() async {
    await _prefs?.setString('pollingProfile', _pollingProfile.name);
    await _prefs?.setInt('pollSeconds', _pollSeconds);
    await _prefs?.setInt('healthPollSeconds', _healthPollSeconds);
    await _prefs?.setInt('identityPollSeconds', _identityPollSeconds);
  }

  Future<void> setHistoryLength(int v) async {
    _historyLength = v.clamp(20, 240);
    await _prefs?.setInt('historyLength', _historyLength);
    notifyListeners();
  }
}
