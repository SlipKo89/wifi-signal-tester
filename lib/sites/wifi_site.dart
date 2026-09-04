import '../router/router_connection.dart';

/// A physical/customer location whose MikroTik routers must be monitored as
/// one Wi-Fi system. Credentials remain inside platform secure storage.
class WifiSite {
  final String id;
  final String name;
  final String notes;
  final List<RouterConnection> routers;
  final int? lastUsedAtMs;
  final bool imported;

  const WifiSite({
    required this.id,
    required this.name,
    this.notes = '',
    this.routers = const [],
    this.lastUsedAtMs,
    this.imported = false,
  });

  WifiSite copyWith({
    String? name,
    String? notes,
    List<RouterConnection>? routers,
    int? lastUsedAtMs,
    bool? imported,
  }) =>
      WifiSite(
        id: id,
        name: name ?? this.name,
        notes: notes ?? this.notes,
        routers: routers ?? this.routers,
        lastUsedAtMs: lastUsedAtMs ?? this.lastUsedAtMs,
        imported: imported ?? this.imported,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'routers': routers.map((router) => router.toJson()).toList(),
        if (lastUsedAtMs != null) 'lastUsedAtMs': lastUsedAtMs,
        'imported': imported,
      };

  factory WifiSite.fromJson(Map<String, dynamic> json) {
    final rawRouters = json['routers'] as List? ?? const [];
    return WifiSite(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      routers: rawRouters
          .whereType<Map>()
          .map((raw) => RouterConnection.fromJson(
                Map<String, dynamic>.from(raw),
              ))
          .where((router) => router.vendor == RouterVendor.mikrotik)
          .toList(),
      lastUsedAtMs: (json['lastUsedAtMs'] as num?)?.toInt(),
      imported: json['imported'] as bool? ?? false,
    );
  }
}
