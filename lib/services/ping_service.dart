import 'dart:async';
import 'dart:io';

import 'package:dart_ping/dart_ping.dart';

/// One-shot ICMP ping via the platform `ping` tool. Read-only: it only sends a
/// single echo request and measures the round-trip.
class PingService {
  final bool _supported;
  Ping? _active;

  PingService({bool? supported}) : _supported = supported ?? !Platform.isMacOS;

  /// dart_ping uses a child `/sbin/ping` process on macOS and requires an
  /// incoming-network sandbox entitlement for ICMP replies. Do not broaden the
  /// app sandbox or leave subprocesses behind for an optional metric.
  bool get isSupported => _supported;

  Future<int?> pingOnce(String host) async {
    if (!isSupported) return null;
    await cancel();
    final ping = Ping(host, count: 1, timeout: 1);
    _active = ping;
    try {
      final data = await ping.stream
          .firstWhere((e) => e.response != null || e.error != null,
              orElse: () => const PingData())
          .timeout(const Duration(seconds: 3),
              onTimeout: () => const PingData());
      return data.response?.time?.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      if (identical(_active, ping)) _active = null;
      await _stop(ping);
    }
  }

  Future<void> cancel() async {
    final ping = _active;
    _active = null;
    if (ping != null) await _stop(ping);
  }

  Future<void> _stop(Ping ping) async {
    try {
      await ping.stop().timeout(const Duration(milliseconds: 750));
    } catch (_) {
      // The process may already have exited or may still be launching. The
      // current macOS build never starts it; Android will reap it normally.
    }
  }
}
