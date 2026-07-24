import 'package:flutter/material.dart';

/// Dark, instrument-panel look. Signal quality maps to colour so you can read
/// the dashboard at a glance while walking around.
class AppTheme {
  static const bg = Color(0xFF0E1116);
  static const surface = Color(0xFF161B22);
  static const surfaceAlt = Color(0xFF1C2530);
  static const accent = Color(0xFF2F81F7);
  static const phoneAccent = Color(0xFF3FB950);
  static const apAccent = Color(0xFFD29922);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        surface: surface,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF232B36)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Green (strong) → amber (usable) → red (poor) for an RSSI/signal in dBm.
  static Color signalColor(int? dbm) {
    if (dbm == null) return Colors.grey;
    if (dbm >= -60) return const Color(0xFF3FB950);
    if (dbm >= -72) return const Color(0xFFD29922);
    return const Color(0xFFF85149);
  }

  /// Green (>25) → amber (>15) → red for SNR in dB.
  static Color snrColor(int? snr) {
    if (snr == null) return Colors.grey;
    if (snr >= 25) return const Color(0xFF3FB950);
    if (snr >= 15) return const Color(0xFFD29922);
    return const Color(0xFFF85149);
  }
}
