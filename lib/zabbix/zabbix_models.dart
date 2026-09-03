class ZabbixConnection {
  final String name;
  final String url;
  final String apiToken;

  const ZabbixConnection({
    required this.name,
    required this.url,
    required this.apiToken,
  });

  factory ZabbixConnection.fromJson(Map<String, dynamic> json) =>
      ZabbixConnection(
        name: json['name']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        apiToken: json['api_token']?.toString() ?? '',
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'url': url,
        'api_token': apiToken,
      };
}

class ZabbixProbe {
  final String version;
  final List<ZabbixHost> hosts;

  const ZabbixProbe({required this.version, required this.hosts});
}

class ZabbixHost {
  final String hostId;
  final String technicalName;
  final String visibleName;
  final bool enabled;

  const ZabbixHost({
    required this.hostId,
    required this.technicalName,
    required this.visibleName,
    required this.enabled,
  });

  String get label =>
      visibleName.trim().isNotEmpty ? visibleName.trim() : technicalName.trim();
}

class ZabbixItem {
  final String itemId;
  final String name;
  final String key;
  final int valueType;
  final String units;
  final double? lastValue;
  final DateTime? lastReceivedAt;

  const ZabbixItem({
    required this.itemId,
    required this.name,
    required this.key,
    required this.valueType,
    required this.units,
    required this.lastValue,
    required this.lastReceivedAt,
  });

  bool get isFloat => valueType == 0;
}

enum ZabbixHistorySource { history, trends, historyFallback }

class ZabbixHistoryPoint {
  final DateTime timestamp;
  final double value;
  final double minimum;
  final double maximum;
  final int samples;

  const ZabbixHistoryPoint({
    required this.timestamp,
    required this.value,
    required this.minimum,
    required this.maximum,
    this.samples = 1,
  });
}

class ZabbixSeries {
  final ZabbixHistorySource source;
  final List<ZabbixHistoryPoint> points;
  final bool possiblyTruncated;

  const ZabbixSeries({
    required this.source,
    required this.points,
    this.possiblyTruncated = false,
  });

  double? get latest => points.isEmpty ? null : points.last.value;

  double? get minimum {
    if (points.isEmpty) return null;
    return points
        .map((point) => point.minimum)
        .reduce((left, right) => left < right ? left : right);
  }

  double? get maximum {
    if (points.isEmpty) return null;
    return points
        .map((point) => point.maximum)
        .reduce((left, right) => left > right ? left : right);
  }

  double? get average {
    if (points.isEmpty) return null;
    var weighted = 0.0;
    var count = 0;
    for (final point in points) {
      final samples = point.samples < 1 ? 1 : point.samples;
      weighted += point.value * samples;
      count += samples;
    }
    return count == 0 ? null : weighted / count;
  }
}
