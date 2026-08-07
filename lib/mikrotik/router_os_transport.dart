/// Read-only transport to a RouterOS device. REST, binary API and SSH
/// implementations sit behind this contract, so the rest of the app never
/// cares which one is in use.
///
/// Implementations issue menu reads and a small whitelist of `monitor once`
/// commands. There is deliberately no write method on this interface.
abstract class RouterOsTransport {
  /// Opens the connection and authenticates. Throws on failure.
  Future<void> connect();

  /// Reads all records from a menu (e.g. `/ip/arp`).
  ///
  /// [filters] are equality filters (`key == value`). Implementations may
  /// apply them server-side or client-side; callers must not rely on which.
  /// [fields] limits returned properties. It is a performance hint only: all
  /// implementations still project the rows locally before returning them.
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
    List<String>? fields,
  });

  /// Runs a read-only command that isn't a plain print — e.g. `monitor once`
  /// to read a radio's noise floor. Params become `=key=value` / JSON fields.
  Future<List<Map<String, String>>> command(
    String path,
    Map<String, String> params,
  );

  Future<void> close();

  /// Human-readable transport name for the UI ("REST" / "API").
  String get kind;
}

final _readFieldName = RegExp(r'^[A-Za-z0-9._-]+$');

/// Keeps field projections safe for transports that place them in a RouterOS
/// command sentence. Callers only use constants, but the transport boundary
/// validates them as defence in depth.
void validateReadFields(List<String>? fields) {
  if (fields == null) return;
  if (fields.any((field) => field.isEmpty || !_readFieldName.hasMatch(field))) {
    throw RouterOsException('Invalid read field projection');
  }
}

Map<String, String> projectReadFields(
  Map<String, String> row,
  List<String>? fields,
) {
  if (fields == null || fields.isEmpty) return row;
  return {
    for (final field in fields)
      if (row.containsKey(field)) field: row[field]!,
  };
}

/// User preference for choosing one of the read-only RouterOS transports.
enum TransportPreference { auto, rest, binary, ssh }

const _readOnlyMonitorPaths = {
  '/interface/wireless/monitor',
  '/interface/wifi/monitor',
  '/interface/lte/monitor',
};

/// Shared safety gate for commands that are not plain menu reads.
///
/// REST and the binary API can technically execute writes, so relying on a
/// comment or on call-site discipline is not enough. Every transport calls this
/// validator and only these three `monitor <interface> once` reads pass.
void validateReadOnlyCommand(String path, Map<String, String> params) {
  if (!_readOnlyMonitorPaths.contains(path)) {
    throw RouterOsException('Command is not on the read-only whitelist: $path');
  }
  const allowedKeys = {'.id', 'numbers', 'once'};
  if (params.keys.any((key) => !allowedKeys.contains(key)) ||
      !params.containsKey('once') ||
      params['once']!.isNotEmpty) {
    throw RouterOsException('Only monitor once is allowed');
  }
  final id = params['.id'] ?? params['numbers'];
  if (id == null ||
      id.isEmpty ||
      (params.containsKey('.id') && params.containsKey('numbers'))) {
    throw RouterOsException('A single interface identifier is required');
  }
}

/// Controlled transport telemetry for the in-memory support log. Callers must
/// not put credentials or raw RouterOS responses into [details].
typedef TransportEventSink = void Function(
  String code,
  String message,
  Map<String, Object?> details,
);

/// Thrown for any RouterOS-reported error (trap/fatal, HTTP error, auth).
class RouterOsException implements Exception {
  final String message;
  RouterOsException(this.message);
  @override
  String toString() => 'RouterOsException: $message';
}
