/// Access-list menus used by the three RouterOS wireless generations.
const List<String> kDeviceAccessListPaths = [
  '/caps-man/access-list',
  '/interface/wireless/access-list',
  '/interface/wifi/access-list',
];

/// Human-readable identity collected for one currently associated Wi-Fi client.
///
/// RouterOS operators commonly document devices in an access-list or in a DHCP
/// lease. Keep the source fields separate so the UI can show where a label came
/// from instead of silently discarding useful metadata.
class DeviceIdentity {
  final String macAddress;
  final String? ipAddress;
  final String? dhcpHostName;
  final String? dhcpComment;
  final String? accessListComment;

  const DeviceIdentity({
    required this.macAddress,
    this.ipAddress,
    this.dhcpHostName,
    this.dhcpComment,
    this.accessListComment,
  });

  /// Operator-authored labels are more useful than a device-generated DHCP
  /// hostname. Access-list wins because it is tied directly to the Wi-Fi MAC.
  String get displayName =>
      accessListComment ?? dhcpComment ?? dhcpHostName ?? macAddress;

  bool matches(String query) {
    final needle = query.toLowerCase();
    return [
      macAddress,
      ipAddress,
      dhcpHostName,
      dhcpComment,
      accessListComment,
    ].whereType<String>().any((v) => v.toLowerCase().contains(needle));
  }

  /// RouterOS CLI renders comments as `-= label =-` in some configurations.
  static String? clean(String? raw) {
    if (raw == null) return null;
    final value = raw.replaceAll(RegExp(r'^-=\s*|\s*=-$'), '').trim();
    return value.isEmpty ? null : value;
  }

  /// Combines comments found in several applicable access-list menus/routers,
  /// preserving order and removing duplicates.
  static String? mergeComments(Iterable<String?> values) {
    final unique = <String>[];
    for (final raw in values) {
      final value = clean(raw);
      if (value != null && !unique.contains(value)) unique.add(value);
    }
    return unique.isEmpty ? null : unique.join(' · ');
  }
}
