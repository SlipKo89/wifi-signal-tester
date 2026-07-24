/// Read-only transport to a RouterOS device. Two implementations exist —
/// [RestTransport] and [BinaryApiTransport] — and the rest of the app never
/// cares which one is in use.
///
/// By contract, implementations MUST only ever issue read (`print` / GET)
/// operations. There is deliberately no write method on this interface.
abstract class RouterOsTransport {
  /// Opens the connection and authenticates. Throws on failure.
  Future<void> connect();

  /// Reads all records from a menu (e.g. `/ip/arp`).
  ///
  /// [filters] are equality filters (`key == value`). Implementations may
  /// apply them server-side or client-side; callers must not rely on which.
  Future<List<Map<String, String>>> read(
    String menuPath, {
    Map<String, String>? filters,
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

/// Thrown for any RouterOS-reported error (trap/fatal, HTTP error, auth).
class RouterOsException implements Exception {
  final String message;
  RouterOsException(this.message);
  @override
  String toString() => 'RouterOsException: $message';
}
