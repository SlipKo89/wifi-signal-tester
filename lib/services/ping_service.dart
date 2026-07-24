import 'package:dart_ping/dart_ping.dart';

/// One-shot ICMP ping via the platform `ping` tool. Read-only: it only sends a
/// single echo request and measures the round-trip.
class PingService {
  Future<int?> pingOnce(String host) async {
    try {
      final ping = Ping(host, count: 1, timeout: 1);
      final data = await ping.stream
          .firstWhere((e) => e.response != null || e.error != null,
              orElse: () => const PingData())
          .timeout(const Duration(seconds: 3),
              onTimeout: () => const PingData());
      return data.response?.time?.inMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
