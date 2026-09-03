import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import '../zabbix/zabbix_api_client.dart';
import '../zabbix/zabbix_binding.dart';
import '../zabbix/zabbix_binding_store.dart';
import '../zabbix/zabbix_credentials_store.dart';
import '../zabbix/zabbix_models.dart';
import 'widgets/app_safe_area.dart';
import 'zabbix_screen.dart';

class ZabbixBindingScreen extends StatefulWidget {
  final ZabbixBindingScope scope;
  final String subjectKey;
  final String subjectLabel;

  const ZabbixBindingScreen({
    super.key,
    required this.scope,
    required this.subjectKey,
    required this.subjectLabel,
  });

  @override
  State<ZabbixBindingScreen> createState() => _ZabbixBindingScreenState();
}

class _ZabbixBindingScreenState extends State<ZabbixBindingScreen> {
  final _credentials = ZabbixCredentialsStore();
  final _bindings = ZabbixBindingStore();
  List<ZabbixConnection> _profiles = const [];
  String? _profileUrl;
  ZabbixBinding? _existing;
  ZabbixApiClient? _client;
  List<ZabbixHost> _hosts = const [];
  ZabbixHost? _host;
  List<ZabbixItem> _items = const [];
  final Map<ZabbixMetricKind, ZabbixItem> _mapped = {};
  bool _loading = true;
  bool _connecting = false;
  String? _error;

  List<ZabbixMetricKind> get _kinds => ZabbixMetricKind.values
      .where((kind) => kind.supports(widget.scope))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object?>([
      _credentials.loadAll(),
      _bindings.load(widget.scope, widget.subjectKey),
    ]);
    if (!mounted) return;
    final profiles = values[0] as List<ZabbixConnection>;
    final existing = values[1] as ZabbixBinding?;
    setState(() {
      _profiles = profiles;
      _existing = existing;
      _profileUrl = existing?.profileUrl ??
          (profiles.isEmpty ? null : profiles.first.url);
      _loading = false;
    });
    if (existing != null && profiles.isNotEmpty) await _connect();
  }

  ZabbixConnection? get _profile {
    for (final profile in _profiles) {
      if (_sameUrl(profile.url, _profileUrl)) return profile;
    }
    return null;
  }

  Future<void> _connect() async {
    final profile = _profile;
    if (profile == null) return;
    setState(() {
      _connecting = true;
      _error = null;
      _hosts = const [];
      _items = const [];
      _host = null;
      _mapped.clear();
    });
    final client =
        ZabbixApiClient(url: profile.url, apiToken: profile.apiToken);
    try {
      final probe = await client.probe();
      if (!mounted) {
        client.close();
        return;
      }
      _client?.close();
      _client = client;
      ZabbixHost? selected;
      final existing = _existing;
      if (existing != null && _sameUrl(existing.profileUrl, profile.url)) {
        for (final host in probe.hosts) {
          if (host.hostId == existing.hostId) selected = host;
        }
      }
      setState(() {
        _hosts = probe.hosts;
        _host = selected;
        _connecting = false;
      });
      if (selected != null) await _loadItems(selected);
    } catch (error) {
      client.close();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadItems(ZabbixHost host) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _host = host;
      _items = const [];
      _mapped.clear();
      _connecting = true;
      _error = null;
    });
    try {
      final items = await client.numericItems(host.hostId);
      if (!mounted) return;
      final existingByKind = <ZabbixMetricKind, ZabbixBoundMetric>{
        if (_existing?.hostId == host.hostId)
          for (final metric in _existing!.metrics) metric.kind: metric,
      };
      final mapped = <ZabbixMetricKind, ZabbixItem>{};
      for (final kind in _kinds) {
        final old = existingByKind[kind];
        ZabbixItem? item;
        if (old != null) {
          for (final candidate in items) {
            if (candidate.itemId == old.itemId) item = candidate;
          }
        }
        item ??= suggestZabbixItem(kind, items);
        if (item != null &&
            !mapped.values.any(
              (candidate) => candidate.itemId == item!.itemId,
            )) {
          mapped[kind] = item;
        }
      }
      setState(() {
        _items = items;
        _mapped.addAll(mapped);
        _connecting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _chooseItem(ZabbixMetricKind kind, L10n l) async {
    final search = TextEditingController();
    final selected = await showDialog<ZabbixItem?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.text.trim().toLowerCase();
          final visible = _items.where((item) {
            if (query.isEmpty) return true;
            return '${item.name} ${item.key} ${item.units}'
                .toLowerCase()
                .contains(query);
          }).toList(growable: false);
          return AlertDialog(
            title: Text(kind.label(l.ru)),
            content: SizedBox(
              width: 560,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l.t('Search item', 'Поиск метрики'),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final item = visible[index];
                        return ListTile(
                          dense: true,
                          title: Text(item.name),
                          subtitle: Text('${item.key} · ${item.units}'),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, const _ClearItem()),
                child: Text(l.t('Clear mapping', 'Убрать привязку')),
              ),
            ],
          );
        },
      ),
    );
    search.dispose();
    if (!mounted) return;
    setState(() {
      if (selected is _ClearItem) {
        _mapped.remove(kind);
      } else if (selected != null) {
        _mapped[kind] = selected;
      }
    });
  }

  Future<void> _save(L10n l) async {
    final profile = _profile;
    final host = _host;
    if (profile == null || host == null || _mapped.isEmpty) return;
    await _bindings.save(ZabbixBinding(
      scope: widget.scope,
      subjectKey: widget.subjectKey,
      profileUrl: profile.url,
      hostId: host.hostId,
      hostName: host.label,
      metrics: [
        for (final entry in _mapped.entries)
          ZabbixBoundMetric.fromItem(entry.key, entry.value),
      ],
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.t('Zabbix context linked.', 'Контекст Zabbix привязан.')),
    ));
    Navigator.pop(context, true);
  }

  Future<void> _remove(L10n l) async {
    await _bindings.remove(widget.scope, widget.subjectKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.t('Zabbix link removed.', 'Привязка Zabbix удалена.')),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Link Zabbix context', 'Привязать контекст Zabbix')),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: l.t('Remove link', 'Удалить привязку'),
              onPressed: () => _remove(l),
              icon: const Icon(Icons.link_off),
            ),
        ],
      ),
      body: AppSafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(widget.subjectLabel,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(l.t(
                    'Choose the Zabbix host that represents this router, then map only useful numeric items. Suggestions are guesses and must be checked before saving.',
                    'Выбери узел Zabbix, соответствующий этому роутеру, затем сопоставь нужные числовые метрики. Автоподбор — лишь предположение, его нужно проверить перед сохранением.',
                  )),
                  const SizedBox(height: 16),
                  if (_profiles.isEmpty) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(l.t('No saved Zabbix profile',
                            'Нет сохранённого профиля Zabbix')),
                        subtitle: Text(l.t(
                          'Create and test one in the Zabbix explorer first.',
                          'Сначала создай и проверь профиль в обозревателе Zabbix.',
                        )),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ZabbixScreen(),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _profiles.any(
                        (profile) => _sameUrl(profile.url, _profileUrl),
                      )
                          ? _profileUrl
                          : null,
                      decoration: InputDecoration(
                        labelText: l.t('Zabbix profile', 'Профиль Zabbix'),
                      ),
                      items: [
                        for (final profile in _profiles)
                          DropdownMenuItem(
                            value: profile.url,
                            child: Text(profile.name.isEmpty
                                ? profile.url
                                : profile.name),
                          ),
                      ],
                      onChanged: _connecting
                          ? null
                          : (value) => setState(() {
                                _profileUrl = value;
                                _hosts = const [];
                                _host = null;
                                _items = const [];
                                _mapped.clear();
                              }),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _connecting ? null : _connect,
                      icon: _connecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_sync_outlined),
                      label: Text(l.t('Read hosts', 'Прочитать узлы')),
                    ),
                    if (_profile != null && _usesHttp(_profile!)) ...[
                      const SizedBox(height: 10),
                      Text(
                        l.t(
                          'HTTP sends the API token and metrics without encryption. Use only on a trusted LAN or VPN.',
                          'HTTP передаёт API-токен и метрики без шифрования. Используй только в доверенной LAN или VPN.',
                        ),
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ],
                    if (_hosts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _host?.hostId,
                        decoration: InputDecoration(
                          labelText: l.t('Zabbix host', 'Узел Zabbix'),
                        ),
                        items: [
                          for (final host in _hosts)
                            DropdownMenuItem(
                              value: host.hostId,
                              child: Text(host.label),
                            ),
                        ],
                        onChanged: _connecting
                            ? null
                            : (id) {
                                if (id == null) return;
                                _loadItems(_hosts.firstWhere(
                                  (host) => host.hostId == id,
                                ));
                              },
                      ),
                    ],
                    if (_items.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(l.t('Metric mapping', 'Сопоставление метрик'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      for (final kind in _kinds)
                        Card(
                          child: ListTile(
                            title: Text(kind.label(l.ru)),
                            subtitle: Text(_mapped[kind] == null
                                ? l.t('Not mapped', 'Не привязано')
                                : '${_mapped[kind]!.name}\n${_mapped[kind]!.key}'),
                            isThreeLine: _mapped[kind] != null,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _chooseItem(kind, l),
                          ),
                        ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _mapped.isEmpty ? null : () => _save(l),
                        icon: const Icon(Icons.link),
                        label: Text(l.t('Save link', 'Сохранить привязку')),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ClearItem extends ZabbixItem {
  const _ClearItem()
      : super(
          itemId: '',
          name: '',
          key: '',
          valueType: 0,
          units: '',
          lastValue: null,
          lastReceivedAt: null,
        );
}

bool _sameUrl(String left, String? right) =>
    right != null &&
    left.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '') ==
        right.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

bool _usesHttp(ZabbixConnection profile) {
  try {
    return ZabbixApiClient.normalizeEndpoint(profile.url).scheme == 'http';
  } catch (_) {
    return false;
  }
}
