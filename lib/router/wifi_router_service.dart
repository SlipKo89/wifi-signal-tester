import '../models/station_signal.dart';
import 'router_connection.dart';

/// Vendor-neutral read-only operations needed by the two-sided dashboard.
///
/// Vendor-specific audits, device inventory and log analysis deliberately stay
/// outside this small contract until their semantics have been field-tested.
abstract interface class WifiRouterService {
  RouterVendor get vendor;
  String? get host;
  String? get transportKind;
  String? get stackLabel;
  String get platformLabel;
  bool get alphaIntegration;
  String? get deviceModel;
  String? get softwareVersion;
  bool get compatibilityVerified;

  String? apNameForBssid(String? bssid);
  int? noiseFloorForFreq(int? mhz);

  Future<void> connect(RouterConnection connection);
  Future<String?> resolveMacForIp(String ip);
  Future<StationSignal?> fetchStation(String mac);
  Future<Map<String, String>?> readResource();
  Future<void> close();
}

/// Vendor-neutral connection/read failure. It deliberately carries no raw
/// response body because router responses may contain private network data.
class RouterAccessException implements Exception {
  final String message;

  const RouterAccessException(this.message);

  @override
  String toString() => 'RouterAccessException: $message';
}
