import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import '../zabbix/zabbix_api_client.dart';
import '../zabbix/zabbix_credentials_store.dart';
import '../zabbix/zabbix_models.dart';
import 'widgets/app_safe_area.dart';
import 'zabbix_access_help_screen.dart';

const _blue = Color(0xFF58A6FF);
const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);
const _muted = Color(0xFF7D8590);

enum _HistoryRange {
  hour(Duration(hours: 1), false),
  day(Duration(hours: 24), false),
  week(Duration(days: 7), true),
  month(Duration(days: 30), true);

  final Duration duration;
  final bool preferTrends;
  const _HistoryRange(this.duration, this.preferTrends);
}

class ZabbixScreen extends StatefulWidget {
  const ZabbixScreen({super.key});

  @override
  State<ZabbixScreen> createState() => _ZabbixScreenState();
}

class _ZabbixScreenState extends State<ZabbixScreen> {
  final _store = ZabbixCredentialsStore();
  final _profileName = TextEditingController();
  final _url = TextEditingController();
  final _port = TextEditingController();
  final _token = TextEditingController();

  List<ZabbixConnection> _profiles = const [];
  ZabbixApiClient? _client;
  String? _version;
  List<ZabbixHost> _hosts = const [];
  ZabbixHost? _host;
  List<ZabbixItem> _items = const [];
  ZabbixItem? _item;
  ZabbixSeries? _series;
  _HistoryRange _range = _HistoryRange.day;
  bool _obscureToken = true;
  bool _connecting = false;
  bool _loadingItems = false;
  bool _loadingHistory = false;
  String? _error;
  String _scheme = 'https';
  String? _loadedProfileUrl;

  bool get _connected => _client != null && _version != null;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      if (profiles.isNotEmpty) _applyProfile(profiles.first);
    });
  }

  void _applyProfile(ZabbixConnection profile) {
    _profileName.text = profile.name;
    _token.text = profile.apiToken;
    _loadedProfileUrl = profile.url;
    try {
      final endpoint = ZabbixApiClient.normalizeEndpoint(profile.url);
      _scheme = endpoint.scheme;
      _port.text = endpoint.hasPort ? endpoint.port.toString() : '';
      var path = endpoint.path;
      if (path.endsWith('/api_jsonrpc.php')) {
        path = path.substring(0, path.length - '/api_jsonrpc.php'.length);
      }
      final host =
          endpoint.host.contains(':') ? '[${endpoint.host}]' : endpoint.host;
      _url.text = '$host$path';
    } on FormatException {
      _scheme = 'https';
      _port.clear();
      _url.text = profile.url;
    }
  }

  Future<void> _connectAndSave(L10n l) async {
    final token = _token.text.trim();
    if (_url.text.trim().isEmpty || token.isEmpty) {
      _show(l.t(
        'Enter the Zabbix address and API token.',
        'Укажи адрес Zabbix и API-токен.',
      ));
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    ZabbixApiClient? next;
    try {
      next = ZabbixApiClient(
        url: _url.text,
        apiToken: token,
        scheme: _scheme,
        port: _portValue,
      );
      final probe = await next.probe();
      final profile = ZabbixConnection(
        name: _profileName.text.trim().isEmpty
            ? next.endpoint.host
            : _profileName.text.trim(),
        url: _frontendUrl(next.endpoint),
        apiToken: token,
      );
      await _store.save(profile);
      final profiles = await _store.loadAll();
      if (!mounted) {
        next.close();
        return;
      }
      final previous = _client;
      setState(() {
        _client = next;
        _version = probe.version;
        _hosts = probe.hosts;
        _host = null;
        _items = const [];
        _item = null;
        _series = null;
        _profiles = profiles;
        _profileName.text = profile.name;
        _loadedProfileUrl = profile.url;
        _connecting = false;
      });
      previous?.close();
      next = null;
      if (probe.hosts.isNotEmpty) {
        await _selectHost(
          probe.hosts.firstWhere(
            (host) => host.enabled,
            orElse: () => probe.hosts.first,
          ),
          l,
        );
      }
    } catch (error) {
      next?.close();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = _friendlyError(error, l);
      });
    }
  }

  Future<void> _selectHost(ZabbixHost host, L10n l) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _host = host;
      _loadingItems = true;
      _error = null;
      _items = const [];
      _item = null;
      _series = null;
    });
    try {
      final items = await client.numericItems(host.hostId);
      if (!mounted || _client != client || _host?.hostId != host.hostId) {
        return;
      }
      setState(() {
        _items = items;
        _loadingItems = false;
      });
    } catch (error) {
      if (!mounted || _client != client || _host?.hostId != host.hostId) {
        return;
      }
      setState(() {
        _loadingItems = false;
        _error = _friendlyError(error, l);
      });
    }
  }

  Future<void> _selectItem(ZabbixItem item, L10n l) async {
    setState(() {
      _item = item;
      _series = null;
    });
    await _loadHistory(l);
  }

  Future<void> _loadHistory(L10n l) async {
    final client = _client;
    final item = _item;
    if (client == null || item == null) return;
    final range = _range;
    setState(() {
      _loadingHistory = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final series = await client.history(
        item: item,
        from: now.subtract(range.duration),
        till: now,
        preferTrends: range.preferTrends,
      );
      if (!mounted ||
          _client != client ||
          _item?.itemId != item.itemId ||
          _range != range) {
        return;
      }
      setState(() {
        _series = series;
        _loadingHistory = false;
      });
    } catch (error) {
      if (!mounted ||
          _client != client ||
          _item?.itemId != item.itemId ||
          _range != range) {
        return;
      }
      setState(() {
        _loadingHistory = false;
        _error = _friendlyError(error, l);
      });
    }
  }

  void _disconnect() {
    _client?.close();
    setState(() {
      _client = null;
      _version = null;
      _hosts = const [];
      _host = null;
      _items = const [];
      _item = null;
      _series = null;
      _error = null;
    });
  }

  Future<void> _forget(ZabbixConnection profile, L10n l) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t(
                'Forget this Zabbix profile?', 'Забыть этот профиль Zabbix?')),
            content: Text(l.t(
              'Only the local URL and token copy will be deleted. The API token remains active in Zabbix until you revoke it there.',
              'Будут удалены только локальные адрес и копия токена. API-токен останется активным, пока ты не отзовёшь его в самом Zabbix.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.t('Forget locally', 'Забыть локально')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _store.remove(profile.url);
    final profiles = await _store.loadAll();
    if (!mounted) return;
    if (_sameUrl(profile.url, _loadedProfileUrl ?? '')) {
      _disconnect();
      _profileName.clear();
      _url.clear();
      _port.clear();
      _token.clear();
      _loadedProfileUrl = null;
    }
    setState(() => _profiles = profiles);
  }

  Future<void> _pickHost(L10n l) async {
    final selected = await _pick<ZabbixHost>(
      title: l.t('Select Zabbix host', 'Выбери узел Zabbix'),
      values: _hosts,
      label: (host) => host.label,
      details: (host) => host.enabled
          ? host.technicalName
          : '${host.technicalName} · ${l.t('disabled', 'отключён')}',
    );
    if (selected != null) await _selectHost(selected, l);
  }

  Future<void> _pickItem(L10n l) async {
    final selected = await _pick<ZabbixItem>(
      title: l.t('Select numeric item', 'Выбери числовую метрику'),
      values: _items,
      label: (item) => item.name,
      details: (item) => [item.key, item.units]
          .where((value) => value.trim().isNotEmpty)
          .join(' · '),
    );
    if (selected != null) await _selectItem(selected, l);
  }

  Future<T?> _pick<T>({
    required String title,
    required List<T> values,
    required String Function(T value) label,
    required String Function(T value) details,
  }) async {
    final search = TextEditingController();
    var query = '';
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = values.where((value) {
            final haystack = '${label(value)} ${details(value)}'.toLowerCase();
            return haystack.contains(query.toLowerCase());
          }).toList(growable: false);
          return AppSafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.76,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'RSSI, CPU, icmpping…',
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value.trim()),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final value = filtered[index];
                        return ListTile(
                          title: Text(label(value),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: details(value).isEmpty
                              ? null
                              : Text(details(value),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    search.dispose();
    return result;
  }

  @override
  void dispose() {
    _client?.close();
    _profileName.dispose();
    _url.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('Zabbix history', 'История из Zabbix')),
            Text(
              _connected
                  ? 'Zabbix $_version · ${_hosts.length} ${l.t('hosts', 'узлов')}'
                  : l.t('Optional read-only integration',
                      'Необязательная интеграция только для чтения'),
              style: const TextStyle(
                fontSize: 10,
                color: _muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.t('Access setup help', 'Настройка прав доступа'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ZabbixAccessHelpScreen(),
              ),
            ),
            icon: const Icon(Icons.help_outline),
          ),
          if (_connected)
            IconButton(
              tooltip: l.t('Disconnect', 'Отключить'),
              onPressed: _disconnect,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: AppSafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              _ErrorCard(message: _error!),
              const SizedBox(height: 12),
            ],
            if (!_connected) _connectionCard(l),
            if (_connected) ...[
              _sourceCard(l),
              const SizedBox(height: 12),
              _historyCard(l),
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectionCard(L10n l) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.monitor_heart_outlined, color: _blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.t('Connect to Zabbix', 'Подключение к Zabbix'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l.t(
                  'Bring an existing API token. The app reads hosts, numeric items and their history; it does not create users, tokens or Zabbix objects.',
                  'Используй готовый API-токен. Приложение читает узлы, числовые метрики и их историю; пользователей, токены и объекты Zabbix оно не создаёт.',
                ),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              if (_profiles.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(l.t('Saved profiles', 'Сохранённые профили'),
                    style: const TextStyle(
                        fontSize: 11,
                        color: _muted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                for (final profile in _profiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      _profileUsesHttp(profile)
                          ? Icons.lock_open_outlined
                          : Icons.storage_outlined,
                      size: 21,
                      color: _profileUsesHttp(profile) ? _amber : null,
                    ),
                    title: Text(profile.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(profile.url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => setState(() => _applyProfile(profile)),
                    trailing: IconButton(
                      tooltip: l.t('Forget locally', 'Забыть локально'),
                      onPressed: () => _forget(profile, l),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _profileName,
                decoration: InputDecoration(
                  labelText: l.t('Profile name (optional)',
                      'Название профиля (необязательно)'),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_scheme),
                      initialValue: _scheme,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.t('Protocol', 'Протокол'),
                        prefixIcon: Icon(
                          _scheme == 'https'
                              ? Icons.lock_outline
                              : Icons.lock_open_outlined,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'https', child: Text('HTTPS')),
                        DropdownMenuItem(value: 'http', child: Text('HTTP')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _scheme = value;
                          _loadedProfileUrl = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      autocorrect: false,
                      onChanged: (_) => _loadedProfileUrl = null,
                      decoration: InputDecoration(
                        labelText: l.t('Port (optional)', 'Порт (необяз.)'),
                        hintText: _scheme == 'https' ? '443' : '80',
                        prefixIcon: const Icon(Icons.numbers),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => _loadedProfileUrl = null,
                decoration: InputDecoration(
                  labelText: l.t('Zabbix host / path', 'Хост / путь Zabbix'),
                  hintText: 'zabbix.example.com/zabbix',
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: _obscureToken,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'API token',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                    icon: Icon(_obscureToken
                        ? Icons.visibility_off
                        : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_scheme == 'http')
                _CleartextWarning(l: l)
              else
                Text(
                  l.t(
                    'HTTPS validates the server certificate. The token is stored in platform secure storage and excluded from support reports.',
                    'HTTPS проверяет сертификат сервера. Токен хранится в защищённом хранилище платформы и исключён из отчётов в поддержку.',
                  ),
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _connecting ? null : () => _connectAndSave(l),
                icon: _connecting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_connecting
                    ? l.t('Checking…', 'Проверяем…')
                    : l.t('Test and save', 'Проверить и сохранить')),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ZabbixAccessHelpScreen(),
                  ),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: Text(l.t(
                  'How to create a read-only user and token',
                  'Как создать пользователя и токен только для чтения',
                )),
              ),
            ],
          ),
        ),
      );

  Widget _sourceCard(L10n l) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage_outlined, color: _green),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      l.t('History source', 'Источник истории'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('Zabbix $_version',
                      style: const TextStyle(fontSize: 11, color: _muted)),
                ],
              ),
              if (_client?.usesCleartext ?? false) ...[
                const SizedBox(height: 10),
                _CleartextWarning(l: l, compact: true),
              ],
              const SizedBox(height: 12),
              _PickerField(
                label: l.t('Host', 'Узел'),
                value: _host?.label,
                placeholder: _hosts.isEmpty
                    ? l.t('No readable hosts', 'Нет доступных узлов')
                    : l.t('Select host', 'Выбери узел'),
                busy: false,
                onTap: _hosts.isEmpty ? null : () => _pickHost(l),
              ),
              const SizedBox(height: 10),
              _PickerField(
                label: l.t('Numeric item', 'Числовая метрика'),
                value: _item?.name,
                subtitle: _item == null
                    ? null
                    : [_item!.key, _item!.units]
                        .where((value) => value.trim().isNotEmpty)
                        .join(' · '),
                placeholder: _host == null
                    ? l.t('Select a host first', 'Сначала выбери узел')
                    : _items.isEmpty && !_loadingItems
                        ? l.t('No active numeric items',
                            'Нет активных числовых метрик')
                        : l.t('Select metric', 'Выбери метрику'),
                busy: _loadingItems,
                onTap: _items.isEmpty ? null : () => _pickItem(l),
              ),
              if (_hosts.isEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  l.t(
                    'The token is valid, but its user cannot read any hosts. Grant Read access to the required host groups.',
                    'Токен действителен, но его пользователь не видит узлы. Выдай Read-доступ к нужным группам узлов.',
                  ),
                  style: const TextStyle(fontSize: 11, color: _amber),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _historyCard(L10n l) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.timeline, color: _blue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(l.t('Metric history', 'История метрики'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: l.t('Refresh', 'Обновить'),
                    onPressed: _item == null || _loadingHistory
                        ? null
                        : () => _loadHistory(l),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final range in _HistoryRange.values)
                    ChoiceChip(
                      label: Text(_rangeLabel(range, l)),
                      selected: _range == range,
                      onSelected: (selected) {
                        if (!selected || _range == range) return;
                        setState(() => _range = range);
                        if (_item != null) _loadHistory(l);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loadingHistory)
                const SizedBox(
                  height: 230,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_item == null)
                _empty(l.t(
                  'Select a host and metric to load its history.',
                  'Выбери узел и метрику, чтобы загрузить историю.',
                ))
              else if (_series == null || _series!.points.isEmpty)
                _empty(l.t(
                  'Zabbix has no values for this metric and period. Check item retention and trend settings.',
                  'В Zabbix нет значений этой метрики за выбранный период. Проверь сроки хранения history и trends.',
                ))
              else ...[
                _SeriesSummary(item: _item!, series: _series!, l: l),
                const SizedBox(height: 12),
                SizedBox(
                  height: 245,
                  child: _ZabbixHistoryChart(
                    series: _series!,
                    item: _item!,
                    range: _range,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _sourceText(_series!, l),
                  style: TextStyle(
                    fontSize: 10,
                    color: _series!.possiblyTruncated ? _amber : _muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _empty(String text) => SizedBox(
        height: 150,
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _muted)),
        ),
      );

  String _rangeLabel(_HistoryRange value, L10n l) => switch (value) {
        _HistoryRange.hour => l.t('1 hour', '1 час'),
        _HistoryRange.day => l.t('24 hours', '24 часа'),
        _HistoryRange.week => l.t('7 days', '7 дней'),
        _HistoryRange.month => l.t('30 days', '30 дней'),
      };

  String _sourceText(ZabbixSeries series, L10n l) {
    final base = switch (series.source) {
      ZabbixHistorySource.history => l.t(
          'Raw Zabbix history. ${series.points.length} points.',
          'Исходная history Zabbix. Точек: ${series.points.length}.'),
      ZabbixHistorySource.trends => l.t(
          'Hourly Zabbix trends: the line is value_avg; summary min/max uses hourly value_min/value_max. ${series.points.length} points.',
          'Часовые trends Zabbix: линия — value_avg, min/max в сводке учитывают часовые value_min/value_max. Точек: ${series.points.length}.'),
      ZabbixHistorySource.historyFallback => l.t(
          'No trends were returned; showing a bounded raw-history fallback. ${series.points.length} points.',
          'Trends не вернулись; показана ограниченная выборка исходной history. Точек: ${series.points.length}.'),
    };
    if (!series.possiblyTruncated) return base;
    return '$base ${l.t('The API limit was reached; older raw points may be omitted.', 'Достигнут лимит API; более старые исходные точки могли не попасть в выборку.')}';
  }

  String _friendlyError(Object error, L10n l) {
    if (error is FormatException) {
      return l.t(
        'Check the host, protocol, port and token. The port must be from 1 to 65535.',
        'Проверь хост, протокол, порт и токен. Порт должен быть от 1 до 65535.',
      );
    }
    if (error is TimeoutException) {
      return l.t(
        'Zabbix did not respond before the timeout.',
        'Zabbix не ответил за отведённое время.',
      );
    }
    if (error is HandshakeException) {
      return l.t(
        'TLS certificate validation failed. Install a trusted certificate for the Zabbix frontend.',
        'Не удалось проверить TLS-сертификат. Установи доверенный сертификат для веб-интерфейса Zabbix.',
      );
    }
    if (error is SocketException || error is http.ClientException) {
      return l.t(
        'Cannot reach the Zabbix frontend. Check its address, VPN and network access.',
        'Не удалось подключиться к веб-интерфейсу Zabbix. Проверь адрес, VPN и доступность сети.',
      );
    }
    if (error is ZabbixApiException) {
      final lower = error.message.toLowerCase();
      if (error.authorizationFailure ||
          error.code == 401 ||
          error.code == 403 ||
          lower.contains('not authorized') ||
          lower.contains('permission')) {
        return l.t(
          'Zabbix rejected the token or its permissions. Check token expiry, API access, method allow-list and host-group Read access.',
          'Zabbix отклонил токен или его права. Проверь срок токена, доступ к API, allow-list методов и Read-доступ к группам узлов.',
        );
      }
      return l.t('Zabbix API error: ${error.message}',
          'Ошибка Zabbix API: ${error.message}');
    }
    return l.t(
        'Could not read Zabbix data.', 'Не удалось прочитать данные Zabbix.');
  }

  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  int? get _portValue {
    final value = _port.text.trim();
    if (value.isEmpty) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      throw const FormatException('Invalid Zabbix port.');
    }
    return parsed;
  }

  String _frontendUrl(Uri endpoint) {
    var path = endpoint.path;
    if (path.endsWith('/api_jsonrpc.php')) {
      path = path.substring(0, path.length - '/api_jsonrpc.php'.length);
    }
    return endpoint.replace(path: path, query: null, fragment: null).toString();
  }

  bool _profileUsesHttp(ZabbixConnection profile) {
    try {
      return ZabbixApiClient.normalizeEndpoint(profile.url).scheme == 'http';
    } on FormatException {
      return false;
    }
  }

  bool _sameUrl(String left, String right) =>
      left.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '') ==
      right.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
}

class _CleartextWarning extends StatelessWidget {
  final L10n l;
  final bool compact;

  const _CleartextWarning({required this.l, this.compact = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(compact ? 9 : 11),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _amber.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _amber, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.t(
                  'HTTP is not encrypted: the API token and returned metrics can be read or changed in transit. Use it only on a trusted LAN or through a VPN.',
                  'HTTP не шифруется: API-токен и полученные метрики можно перехватить или изменить по пути. Используй только в доверенной локальной сети или через VPN.',
                ),
                style: TextStyle(
                  fontSize: compact ? 10.5 : 11,
                  color: _amber,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String? subtitle;
  final String placeholder;
  final bool busy;
  final VoidCallback? onTap;

  const _PickerField({
    required this.label,
    required this.value,
    this.subtitle,
    required this.placeholder,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value ?? placeholder,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: value == null ? _muted : null)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: _muted)),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF85149).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF85149).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFF85149)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}

class _SeriesSummary extends StatelessWidget {
  final ZabbixItem item;
  final ZabbixSeries series;
  final L10n l;

  const _SeriesSummary({
    required this.item,
    required this.series,
    required this.l,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SummaryValue(
              label: l.t('Latest', 'Последнее'),
              value: _formatMetric(series.latest, item.units)),
          _SummaryValue(
              label: l.t('Average', 'Среднее'),
              value: _formatMetric(series.average, item.units)),
          _SummaryValue(
              label: 'MIN', value: _formatMetric(series.minimum, item.units)),
          _SummaryValue(
              label: 'MAX', value: _formatMetric(series.maximum, item.units)),
        ],
      );
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 115),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1116),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 9, color: _muted)),
            const SizedBox(height: 3),
            Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _ZabbixHistoryChart extends StatelessWidget {
  final ZabbixSeries series;
  final ZabbixItem item;
  final _HistoryRange range;

  const _ZabbixHistoryChart({
    required this.series,
    required this.item,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    final points = series.points;
    final minimum = series.minimum!;
    final maximum = series.maximum!;
    final span = (maximum - minimum).abs();
    final pad = span == 0 ? math.max(minimum.abs() * 0.05, 1.0) : span * 0.12;
    final spots = <FlSpot>[
      for (var index = 0; index < points.length; index++)
        FlSpot(index.toDouble(), points[index].value),
    ];
    return ClipRect(
      child: LineChart(LineChartData(
        minX: 0,
        maxX: math.max(1, points.length - 1).toDouble(),
        minY: minimum - pad,
        maxY: maximum + pad,
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        gridData: const FlGridData(
          show: true,
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(_compact(value),
                    style: const TextStyle(fontSize: 9, color: _muted)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 27,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                final middle = (points.length - 1) ~/ 2;
                if ((value - index).abs() > 0.01 ||
                    (index != 0 &&
                        index != middle &&
                        index != points.length - 1) ||
                    index < 0 ||
                    index >= points.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    _timeLabel(points[index].timestamp, range),
                    style: const TextStyle(fontSize: 9, color: _muted),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((spot) {
              final index = spot.x.round().clamp(0, points.length - 1);
              final point = points[index];
              return LineTooltipItem(
                '${_fullTime(point.timestamp)}\n${_formatMetric(point.value, item.units)}',
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: _blue,
            barWidth: 2,
            dotData: FlDotData(show: points.length <= 60),
            belowBarData: BarAreaData(
              show: true,
              color: _blue.withValues(alpha: 0.10),
            ),
          ),
        ],
      )),
    );
  }
}

String _formatMetric(double? value, String units) {
  if (value == null) return '—';
  final absolute = value.abs();
  final decimals = absolute >= 100 || value == value.roundToDouble() ? 0 : 2;
  final suffix = units.trim().isEmpty ? '' : ' ${units.trim()}';
  return '${value.toStringAsFixed(decimals)}$suffix';
}

String _compact(double value) {
  final absolute = value.abs();
  if (absolute >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)}G';
  }
  if (absolute >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (absolute >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return value.toStringAsFixed(absolute >= 100 ? 0 : 1);
}

String _timeLabel(DateTime value, _HistoryRange range) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  if (range == _HistoryRange.hour || range == _HistoryRange.day) {
    return '${two(local.hour)}:${two(local.minute)}';
  }
  return '${two(local.day)}.${two(local.month)}';
}

String _fullTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
