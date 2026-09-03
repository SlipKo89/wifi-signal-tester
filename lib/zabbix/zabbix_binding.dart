import 'zabbix_models.dart';

enum ZabbixBindingScope { wifi, lte }

enum ZabbixMetricKind {
  wifiSignal,
  wifiSnr,
  wifiCcq,
  lteRsrp,
  lteRsrq,
  lteSinr,
  lteRssi,
  lteCqi,
  cpu,
  ping,
  packetLoss,
  rxTraffic,
  txTraffic,
  clients,
}

extension ZabbixMetricKindInfo on ZabbixMetricKind {
  bool supports(ZabbixBindingScope scope) => switch (this) {
        ZabbixMetricKind.wifiSignal ||
        ZabbixMetricKind.wifiSnr ||
        ZabbixMetricKind.wifiCcq =>
          scope == ZabbixBindingScope.wifi,
        ZabbixMetricKind.lteRsrp ||
        ZabbixMetricKind.lteRsrq ||
        ZabbixMetricKind.lteSinr ||
        ZabbixMetricKind.lteRssi ||
        ZabbixMetricKind.lteCqi =>
          scope == ZabbixBindingScope.lte,
        _ => true,
      };

  String label(bool ru) => switch (this) {
        ZabbixMetricKind.wifiSignal => ru ? 'Сигнал Wi-Fi' : 'Wi-Fi signal',
        ZabbixMetricKind.wifiSnr => 'Wi-Fi SNR',
        ZabbixMetricKind.wifiCcq => 'Wi-Fi CCQ',
        ZabbixMetricKind.lteRsrp => 'LTE RSRP',
        ZabbixMetricKind.lteRsrq => 'LTE RSRQ',
        ZabbixMetricKind.lteSinr => 'LTE SINR',
        ZabbixMetricKind.lteRssi => 'LTE RSSI',
        ZabbixMetricKind.lteCqi => 'LTE CQI',
        ZabbixMetricKind.cpu => ru ? 'Загрузка CPU' : 'CPU load',
        ZabbixMetricKind.ping => ru ? 'Задержка' : 'Latency',
        ZabbixMetricKind.packetLoss => ru ? 'Потери пакетов' : 'Packet loss',
        ZabbixMetricKind.rxTraffic =>
          ru ? 'Входящий трафик' : 'Inbound traffic',
        ZabbixMetricKind.txTraffic =>
          ru ? 'Исходящий трафик' : 'Outbound traffic',
        ZabbixMetricKind.clients => ru ? 'Wi-Fi-клиенты' : 'Wi-Fi clients',
      };

  String get timelineKey => switch (this) {
        ZabbixMetricKind.wifiSignal => 'wifi_signal',
        ZabbixMetricKind.wifiSnr => 'wifi_snr',
        ZabbixMetricKind.wifiCcq => 'wifi_ccq',
        ZabbixMetricKind.lteRsrp => 'lte_rsrp',
        ZabbixMetricKind.lteRsrq => 'lte_rsrq',
        ZabbixMetricKind.lteSinr => 'lte_sinr',
        ZabbixMetricKind.lteRssi => 'lte_rssi',
        ZabbixMetricKind.lteCqi => 'lte_cqi',
        ZabbixMetricKind.cpu => 'cpu',
        ZabbixMetricKind.ping => 'ping',
        ZabbixMetricKind.packetLoss => 'loss',
        ZabbixMetricKind.rxTraffic => 'rx_traffic',
        ZabbixMetricKind.txTraffic => 'tx_traffic',
        ZabbixMetricKind.clients => 'clients',
      };
}

class ZabbixBoundMetric {
  final ZabbixMetricKind kind;
  final String itemId;
  final String name;
  final String key;
  final int valueType;
  final String units;

  const ZabbixBoundMetric({
    required this.kind,
    required this.itemId,
    required this.name,
    required this.key,
    required this.valueType,
    required this.units,
  });

  factory ZabbixBoundMetric.fromItem(ZabbixMetricKind kind, ZabbixItem item) =>
      ZabbixBoundMetric(
        kind: kind,
        itemId: item.itemId,
        name: item.name,
        key: item.key,
        valueType: item.valueType,
        units: item.units,
      );

  ZabbixItem get item => ZabbixItem(
        itemId: itemId,
        name: name,
        key: key,
        valueType: valueType,
        units: units,
        lastValue: null,
        lastReceivedAt: null,
      );

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'item_id': itemId,
        'name': name,
        'key': key,
        'value_type': valueType,
        'units': units,
      };

  factory ZabbixBoundMetric.fromJson(Map<String, dynamic> json) =>
      ZabbixBoundMetric(
        kind: ZabbixMetricKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => ZabbixMetricKind.cpu,
        ),
        itemId: json['item_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        key: json['key']?.toString() ?? '',
        valueType: (json['value_type'] as num?)?.toInt() ?? 0,
        units: json['units']?.toString() ?? '',
      );
}

class ZabbixBinding {
  final ZabbixBindingScope scope;
  final String subjectKey;
  final String profileUrl;
  final String hostId;
  final String hostName;
  final List<ZabbixBoundMetric> metrics;

  const ZabbixBinding({
    required this.scope,
    required this.subjectKey,
    required this.profileUrl,
    required this.hostId,
    required this.hostName,
    required this.metrics,
  });

  String get storageKey => '${scope.name}:$subjectKey';

  Map<String, Object?> toJson() => {
        'scope': scope.name,
        'subject_key': subjectKey,
        'profile_url': profileUrl,
        'host_id': hostId,
        'host_name': hostName,
        'metrics': metrics.map((metric) => metric.toJson()).toList(),
      };

  factory ZabbixBinding.fromJson(Map<String, dynamic> json) => ZabbixBinding(
        scope: ZabbixBindingScope.values.firstWhere(
          (value) => value.name == json['scope'],
          orElse: () => ZabbixBindingScope.wifi,
        ),
        subjectKey: json['subject_key']?.toString() ?? '',
        profileUrl: json['profile_url']?.toString() ?? '',
        hostId: json['host_id']?.toString() ?? '',
        hostName: json['host_name']?.toString() ?? '',
        metrics: (json['metrics'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => ZabbixBoundMetric.fromJson(
                  value.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .where((metric) => metric.itemId.isNotEmpty)
            .toList(growable: false),
      );
}

ZabbixItem? suggestZabbixItem(
  ZabbixMetricKind kind,
  Iterable<ZabbixItem> items,
) {
  int score(ZabbixItem item) {
    final text = '${item.key} ${item.name} ${item.units}'.toLowerCase();
    final terms = switch (kind) {
      ZabbixMetricKind.wifiSignal => ['wifi', 'signal', 'rssi'],
      ZabbixMetricKind.wifiSnr => ['wifi', 'snr'],
      ZabbixMetricKind.wifiCcq => ['wifi', 'ccq'],
      ZabbixMetricKind.lteRsrp => ['lte', 'rsrp'],
      ZabbixMetricKind.lteRsrq => ['lte', 'rsrq'],
      ZabbixMetricKind.lteSinr => ['lte', 'sinr'],
      ZabbixMetricKind.lteRssi => ['lte', 'rssi'],
      ZabbixMetricKind.lteCqi => ['lte', 'cqi'],
      ZabbixMetricKind.cpu => ['cpu', 'util'],
      ZabbixMetricKind.ping => ['icmppingsec', 'latency', 'ping time'],
      ZabbixMetricKind.packetLoss => ['icmppingloss', 'packet loss'],
      ZabbixMetricKind.rxTraffic => ['net.if.in', 'traffic in', 'received'],
      ZabbixMetricKind.txTraffic => ['net.if.out', 'traffic out', 'sent'],
      ZabbixMetricKind.clients => ['wireless', 'client', 'station count'],
    };
    var value = 0;
    for (final term in terms) {
      if (text.contains(term)) value += term.contains('.') ? 5 : 2;
    }
    if (kind.name.startsWith('lte') && !text.contains('lte')) value -= 3;
    if (kind.name.startsWith('wifi') &&
        !text.contains('wifi') &&
        !text.contains('wireless')) {
      value -= 2;
    }
    return value;
  }

  ZabbixItem? best;
  var bestScore = 0;
  for (final item in items) {
    final current = score(item);
    if (current > bestScore) {
      best = item;
      bestScore = current;
    }
  }
  return best;
}
