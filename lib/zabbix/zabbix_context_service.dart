import 'zabbix_api_client.dart';
import 'zabbix_binding.dart';
import 'zabbix_credentials_store.dart';
import 'zabbix_models.dart';

class ZabbixContextMetric {
  final ZabbixBoundMetric binding;
  final ZabbixSeries series;

  const ZabbixContextMetric({required this.binding, required this.series});
}

class ZabbixContextResult {
  final ZabbixBinding binding;
  final List<ZabbixContextMetric> metrics;

  const ZabbixContextResult({required this.binding, required this.metrics});
}

class ZabbixContextService {
  final ZabbixCredentialsStore credentials;

  ZabbixContextService({ZabbixCredentialsStore? credentials})
      : credentials = credentials ?? ZabbixCredentialsStore();

  Future<ZabbixContextResult> load(
    ZabbixBinding binding, {
    required DateTime from,
    required DateTime till,
  }) async {
    final profiles = await credentials.loadAll();
    ZabbixConnection? profile;
    for (final candidate in profiles) {
      if (_sameUrl(candidate.url, binding.profileUrl)) {
        profile = candidate;
        break;
      }
    }
    if (profile == null) {
      throw StateError(
        'The linked Zabbix profile is missing. Configure the link again.',
      );
    }
    final client = ZabbixApiClient(
      url: profile.url,
      apiToken: profile.apiToken,
    );
    try {
      await client.apiVersion();
      final metrics = await Future.wait([
        for (final metric in binding.metrics)
          client
              .history(
                item: metric.item,
                from: from,
                till: till,
                preferTrends: till.difference(from) > const Duration(days: 3),
              )
              .then((series) =>
                  ZabbixContextMetric(binding: metric, series: series)),
      ]);
      return ZabbixContextResult(binding: binding, metrics: metrics);
    } finally {
      client.close();
    }
  }
}

bool _sameUrl(String left, String right) =>
    left.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '') ==
    right.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
