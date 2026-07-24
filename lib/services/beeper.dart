import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Plays a short beep (plus a haptic tick) as an alert. The tone is synthesised
/// in memory, so there's no bundled audio asset.
class Beeper {
  final AudioPlayer _player = AudioPlayer();
  Uint8List? _wav;

  Future<void> beep() async {
    try {
      _wav ??= _makeBeepWav();
      await _player.stop();
      await _player.play(BytesSource(_wav!, mimeType: 'audio/wav'));
    } catch (_) {
      // Audio may be unavailable (silent mode / no output) — the haptic still
      // fires below.
    }
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  /// A 16-bit mono PCM WAV of a short sine tone with a tiny fade to avoid clicks.
  static Uint8List _makeBeepWav({
    int freq = 880,
    int ms = 130,
    int rate = 44100,
    double amp = 0.55,
  }) {
    final n = (rate * ms / 1000).round();
    final dataSize = n * 2;
    final b = BytesBuilder();
    void str(String s) => b.add(s.codeUnits);
    void u32(int v) =>
        b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);

    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16); // PCM chunk size
    u16(1); // PCM
    u16(1); // mono
    u32(rate);
    u32(rate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits per sample
    str('data');
    u32(dataSize);

    final fade = (rate * 0.006).round();
    for (var i = 0; i < n; i++) {
      var env = 1.0;
      if (i < fade) {
        env = i / fade;
      } else if (i > n - fade) {
        env = (n - i) / fade;
      }
      final s = (sin(2 * pi * freq * i / rate) * amp * env * 32767).round();
      u16(s & 0xFFFF);
    }
    return b.toBytes();
  }
}
