import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// App-wide preferences, persisted with SharedPreferences (non-secret).
class SettingsController extends ChangeNotifier {
  SharedPreferences? _prefs;

  // 'system' | 'en' | 'ru'
  String _lang = 'system';
  ThemeMode _themeMode = ThemeMode.dark;
  int _pollSeconds = 2;
  int _historyLength = 60;
  bool _alertsEnabled = false;
  int _alertThresholdDb = 12;
  int _minSignalDbm = -72;
  int _minSnrDb = 20;
  String _lastSeenVersion = '';

  String get lang => _lang;
  ThemeMode get themeMode => _themeMode;
  int get pollSeconds => _pollSeconds;
  int get historyLength => _historyLength;
  bool get alertsEnabled => _alertsEnabled;
  int get alertThresholdDb => _alertThresholdDb;

  /// Target signal / SNR: below these the dashboard warns (and alerts beep).
  int get minSignalDbm => _minSignalDbm;
  int get minSnrDb => _minSnrDb;

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
    _pollSeconds = p.getInt('pollSeconds') ?? 2;
    _historyLength = p.getInt('historyLength') ?? 60;
    _alertsEnabled = p.getBool('alertsEnabled') ?? false;
    _alertThresholdDb = p.getInt('alertThresholdDb') ?? 12;
    _minSignalDbm = p.getInt('minSignalDbm') ?? -72;
    _minSnrDb = p.getInt('minSnrDb') ?? 20;
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

  Future<void> setPollSeconds(int v) async {
    _pollSeconds = v.clamp(1, 30);
    await _prefs?.setInt('pollSeconds', _pollSeconds);
    notifyListeners();
  }

  Future<void> setHistoryLength(int v) async {
    _historyLength = v.clamp(20, 240);
    await _prefs?.setInt('historyLength', _historyLength);
    notifyListeners();
  }
}
