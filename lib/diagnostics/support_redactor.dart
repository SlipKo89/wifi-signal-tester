class SupportRedactor {
  final bool includeNetworkIdentifiers;
  final Set<String> networkIdentifiers;

  const SupportRedactor({
    required this.includeNetworkIdentifiers,
    this.networkIdentifiers = const {},
  });

  static final _ipv4 = RegExp(
      r'(?<!\d)(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?!\d)');
  static final _mac = RegExp(
    r'(?<![0-9a-f])(?:[0-9a-f]{2}:){5}[0-9a-f]{2}(?![0-9a-f])',
    caseSensitive: false,
  );

  Object? value(String key, Object? raw) {
    if (raw == null) return null;
    final lower = key.toLowerCase();
    if (_isSecretKey(lower)) return '[removed]';
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), value(k.toString(), v)));
    }
    if (raw is Iterable) {
      return raw.map((v) => value(key, v)).toList();
    }
    if (raw is! String) return raw;
    if (includeNetworkIdentifiers) return text(raw);
    if (lower.contains('ssid')) return _maskName(raw);
    if (lower.contains('bssid') || lower.contains('mac')) return maskMac(raw);
    if (lower == 'ip' ||
        lower.contains('ip_address') ||
        lower.contains('gateway') ||
        lower.contains('host')) {
      return maskHost(raw);
    }
    if (lower.contains('ap_name') || lower == 'access_point') {
      return _maskName(raw);
    }
    if (lower.contains('interface')) return _maskName(raw);
    if (lower == 'last_roam') return '[masked]';
    return text(raw);
  }

  Map<String, Object?> map(Map<String, Object?> source) => source.map(
        (key, value_) => MapEntry(key, value(key, value_)),
      );

  String text(String source) {
    var out = source;
    if (!includeNetworkIdentifiers) {
      final known = networkIdentifiers.where((v) => v.length >= 3).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final identifier in known) {
        out = out.replaceAll(
          RegExp(RegExp.escape(identifier), caseSensitive: false),
          '[network-identifier]',
        );
      }
      out = out.replaceAllMapped(_mac, (m) => maskMac(m.group(0)!));
      out = out.replaceAllMapped(_ipv4, (m) => maskIp(m.group(0)!));
    }
    // Defensive removal for accidental Basic/Bearer/Public-Token logging.
    out = out.replaceAll(
      RegExp(
        r'(authorization|public-token)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      r'$1=[removed]',
    );
    out = out.replaceAll(
      RegExp(
        r'(password|private[_ -]?key|token)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      r'$1=[removed]',
    );
    return out;
  }

  String maskHost(String value_) {
    if (includeNetworkIdentifiers) return value_;
    if (_ipv4.hasMatch(value_)) return maskIp(value_);
    return _maskName(value_);
  }

  String maskIp(String ip) {
    if (includeNetworkIdentifiers) return ip;
    final p = ip.split('.');
    return p.length == 4 ? '${p[0]}.${p[1]}.x.x' : '[network-address]';
  }

  String maskMac(String mac) {
    if (includeNetworkIdentifiers) return mac;
    final p = mac.split(':');
    return p.length == 6
        ? '${p[0]}:${p[1]}:${p[2]}:XX:XX:XX'
        : '[hardware-address]';
  }

  String _maskName(String name) {
    if (includeNetworkIdentifiers || name.isEmpty) return name;
    final visible = name.substring(0, name.length < 3 ? name.length : 3);
    return '$visible***';
  }

  bool _isSecretKey(String key) =>
      key.contains('password') ||
      key.contains('passphrase') ||
      key.contains('private_key') ||
      key.contains('private-key') ||
      key.contains('token') ||
      key == 'authorization' ||
      key == 'credential' ||
      key == 'credentials' ||
      key == 'secret';
}
