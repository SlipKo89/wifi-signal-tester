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

  String get lang => _lang;
  ThemeMode get themeMode => _themeMode;
  int get pollSeconds => _pollSeconds;
  int get historyLength => _historyLength;

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
