import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../keenetic/keenetic_compatibility.dart';
import '../../l10n/l10n.dart';
import '../../mikrotik/mikrotik_service.dart';
import '../../mikrotik/port_knocking.dart';
import '../../services/credentials_store.dart';
import '../../settings/settings_controller.dart';
import '../../sites/wifi_site.dart';
import '../theme.dart';
import 'port_knocking_editor.dart';

/// Router connection form supporting several routers (e.g. a central CAPsMAN
/// box plus a standalone AP). Loads the saved list and hands it back on connect.
class ConnectionForm extends StatefulWidget {
  final void Function(List<RouterConnection> routers) onConnect;
  final VoidCallback? onPhoneOnly;
  final bool busy;
  final RouterVendor vendor;
  final WifiSite? site;
  final bool quickConnection;
  final ValueChanged<WifiSite>? onSiteChanged;

  const ConnectionForm({
    super.key,
    required this.onConnect,
    this.onPhoneOnly,
    this.busy = false,
    this.vendor = RouterVendor.mikrotik,
    this.site,
    this.quickConnection = false,
    this.onSiteChanged,
  });

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final _store = CredentialsStore();
  final _host = TextEditingController();
  final _user = TextEditingController(text: 'monitor');
  final _pass = TextEditingController();
  final _port = TextEditingController();

  final List<RouterConnection> _routers = [];

  late final RouterVendor _vendor;
  TransportPreference _transport = TransportPreference.auto;
  bool _useTls = true;
  bool _obscure = true;
  PortKnockConfig _portKnocking = const PortKnockConfig.disabled();

  @override
  void initState() {
    super.initState();
    _vendor = widget.vendor;
    final site = widget.site;
    if (site != null) {
      _routers.addAll(site.routers);
      if (_routers.isNotEmpty) _applyRouter(_routers.first);
    } else if (_vendor == RouterVendor.keenetic) {
      _store.loadKeeneticProfiles().then((saved) {
        if (saved.isEmpty || !mounted) return;
        setState(() {
          _routers
            ..clear()
            ..addAll(saved);
          _applyRouter(saved.first);
        });
      });
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    _port.dispose();
    super.dispose();
  }

  RouterConnection? _currentInput() {
    final host = _host.text.trim();
    if (host.isEmpty) return null;
    return RouterConnection(
      vendor: _vendor,
      host: host,
      username: _user.text.trim(),
      password: _pass.text,
      transport: _transport,
      useTls: _useTls,
      port: int.tryParse(_port.text.trim()),
      portKnocking: _vendor == RouterVendor.mikrotik
          ? _portKnocking
          : const PortKnockConfig.disabled(),
    );
  }

  Future<void> _addRouter() async {
    final cfg = _currentInput();
    if (cfg == null) return;
    if (!_validatePortKnocking(cfg)) return;
    setState(() {
      _routers.removeWhere(
        (router) => router.vendor == cfg.vendor && router.host == cfg.host,
      );
      _routers.add(cfg);
      if (_vendor == RouterVendor.mikrotik) {
        _host.clear();
        _pass.clear();
        _port.clear();
        _portKnocking = const PortKnockConfig.disabled();
      }
    });
    await _persistRouters();
  }

  Future<void> _removeRouter(RouterConnection r) async {
    setState(() {
      _routers.removeWhere(
        (x) => x.vendor == r.vendor && x.host == r.host,
      );
      if (_host.text.trim() == r.host) {
        _host.clear();
        _pass.clear();
        _port.clear();
        _portKnocking = const PortKnockConfig.disabled();
      }
    });
    await _persistRouters();
  }

  Future<void> _connect() async {
    // Include whatever is typed but not yet added. If it names a host already in
    // the list, the fields win — otherwise editing the transport or password of
    // a saved router would silently do nothing.
    final list = [..._routers];
    final current = _currentInput();
    if (current != null) {
      final at = list.indexWhere(
        (router) =>
            router.vendor == current.vendor && router.host == current.host,
      );
      if (at >= 0) {
        list[at] = current;
      } else {
        list.add(current);
      }
    }
    if (_vendor == RouterVendor.keenetic) {
      final selected = current ?? (list.isEmpty ? null : list.first);
      list
        ..clear()
        ..addAll(selected == null ? const [] : [selected]);
    }
    if (list.isEmpty) return;
    if (list.any((router) => !_validatePortKnocking(router))) return;
    if (widget.site != null) {
      final used = widget.site!.copyWith(
        routers: List.unmodifiable(list),
        lastUsedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _store.upsertSite(used);
      widget.onSiteChanged?.call(used);
    } else if (_vendor == RouterVendor.keenetic) {
      final saved = [..._routers];
      final selected = list.first;
      final at = saved.indexWhere((router) => router.host == selected.host);
      if (at < 0) {
        saved.add(selected);
      } else {
        saved[at] = selected;
      }
      await _store.saveKeeneticProfiles(saved);
    }
    if (!mounted) return;
    widget.onConnect(list);
  }

  Future<void> _persistRouters() async {
    if (widget.site != null) {
      final changed = widget.site!.copyWith(
        routers: List.unmodifiable(_routers),
      );
      await _store.upsertSite(changed);
      widget.onSiteChanged?.call(changed);
    } else if (_vendor == RouterVendor.keenetic) {
      await _store.saveKeeneticProfiles(_routers);
    }
  }

  void _applyRouter(RouterConnection router) {
    _host.text = router.host;
    _user.text = router.username;
    _pass.text = router.password;
    _transport = router.transport;
    _useTls = router.useTls;
    _port.text = router.port?.toString() ?? '';
    _portKnocking = router.portKnocking;
  }

  void _editRouter(RouterConnection router) {
    setState(() => _applyRouter(router));
  }

  bool _validatePortKnocking(RouterConnection connection) {
    if (connection.vendor != RouterVendor.mikrotik ||
        !connection.portKnocking.enabled) {
      return true;
    }
    final l = context.read<SettingsController>().l;
    String? message;
    if (connection.transport == TransportPreference.auto) {
      message = l.t(
        'Choose one transport before using port knocking.',
        'Перед использованием port knocking выбери один конкретный транспорт.',
      );
    } else if (connection.portKnocking.validationError != null) {
      message = l.t(
        'Add 1–${PortKnockConfig.maxSteps} valid port-knocking steps.',
        'Добавь от 1 до ${PortKnockConfig.maxSteps} корректных шагов port knocking.',
      );
    }
    if (message == null) return true;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_formTitle(l),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _vendor == RouterVendor.mikrotik
                  ? l.t(
                      widget.quickConnection
                          ? 'Temporary read-only connection. Nothing entered here is saved.'
                          : 'Read-only. Add every router whose APs belong to this site '
                              '(central CAPsMAN + standalone APs).',
                      widget.quickConnection
                          ? 'Временное подключение только для чтения. Введённые здесь данные не сохраняются.'
                          : 'Только чтение. Добавь каждый роутер с точками этого объекта '
                              '(центральный CAPsMAN + отдельные точки).')
                  : l.t(
                      'Read-only Keenetic Alpha over HTTPS RCI. The first build '
                          'monitors the current phone only.',
                      'Keenetic Alpha только для чтения через HTTPS RCI. Первая '
                          'версия отслеживает только текущий телефон.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF7D8590)),
            ),
            if (_routers.isNotEmpty) ...[
              const SizedBox(height: 14),
              ..._routers.map(_routerChip),
            ],
            const SizedBox(height: 14),
            InputDecorator(
              decoration: InputDecoration(
                labelText: l.t('Mode', 'Режим'),
              ),
              child: Text(
                _vendor == RouterVendor.mikrotik
                    ? 'MikroTik Wi-Fi'
                    : 'Keenetic Wi-Fi · Alpha',
              ),
            ),
            if (_vendor == RouterVendor.keenetic) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.apAccent.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.apAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  l.t(
                    'Alpha compatibility baseline: $kKeeneticAlphaModel, '
                        'KeeneticOS $kKeeneticAlphaRelease. Other models and '
                        'versions may return different fields.',
                    'База совместимости Alpha: $kKeeneticAlphaModel, '
                        'KeeneticOS $kKeeneticAlphaRelease. Другие модели и '
                        'версии могут возвращать отличающиеся поля.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC9D1D9),
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Host / IP',
                prefixIcon: const Icon(Icons.router_outlined),
                hintText: _vendor == RouterVendor.keenetic
                    ? 'router.keenetic.pro'
                    : '192.168.88.1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: InputDecoration(
                labelText: l.t('Username', 'Пользователь'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l.t('Password', 'Пароль'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_vendor == RouterVendor.mikrotik)
              DropdownButtonFormField<TransportPreference>(
                key: ValueKey(_transport),
                initialValue: _transport,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: l.t('Transport', 'Транспорт')),
                items: [
                  DropdownMenuItem(
                    value: TransportPreference.auto,
                    enabled: !_portKnocking.enabled,
                    child: Text(l.t(
                        'Auto (REST → API → SSH)', 'Авто (REST → API → SSH)')),
                  ),
                  DropdownMenuItem(
                      value: TransportPreference.rest,
                      child: Text(l.t('REST only', 'Только REST'))),
                  DropdownMenuItem(
                      value: TransportPreference.binary,
                      child:
                          Text(l.t('Binary API only', 'Только бинарный API'))),
                  DropdownMenuItem(
                      value: TransportPreference.ssh,
                      child: Text(l.t(
                          'SSH (RouterOS console)', 'SSH (консоль RouterOS)'))),
                ],
                onChanged: (v) =>
                    setState(() => _transport = v ?? TransportPreference.auto),
              )
            else
              InputDecorator(
                decoration:
                    InputDecoration(labelText: l.t('Transport', 'Транспорт')),
                child: const Text('HTTPS RCI · x-ndw2'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _port,
                    enabled: _vendor == RouterVendor.keenetic ||
                        _transport != TransportPreference.auto,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.t('Port', 'Порт'),
                      prefixIcon: const Icon(Icons.numbers),
                      hintText: _portHint(l),
                    ),
                  ),
                ),
                if (_vendor == RouterVendor.keenetic ||
                    _transport != TransportPreference.ssh) ...[
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      const Text('TLS',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF7D8590))),
                      Switch(
                        value: _useTls,
                        onChanged: (v) => setState(() => _useTls = v),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (_vendor == RouterVendor.mikrotik &&
                _transport == TransportPreference.ssh) ...[
              const SizedBox(height: 8),
              Text(
                l.t(
                    'SSH runs only `print` and `monitor once` on the console — '
                        'still read-only. The RouterOS user needs the `ssh` '
                        'policy.',
                    'По SSH выполняются только `print` и `monitor once` в '
                        'консоли — по-прежнему только чтение. Пользователю '
                        'RouterOS нужна политика `ssh`.'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
              ),
            ],
            if (_vendor == RouterVendor.mikrotik) ...[
              const SizedBox(height: 12),
              PortKnockingEditor(
                value: _portKnocking,
                l: l,
                enabled: !widget.busy,
                requiresExplicitTransport: _portKnocking.enabled &&
                    _transport == TransportPreference.auto,
                onChanged: (value) => setState(() => _portKnocking = value),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addRouter,
              icon: const Icon(Icons.add, size: 18),
              label: Text(_addLabel(l)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: widget.busy ? null : _connect,
              icon: widget.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: Text(widget.busy
                  ? l.t('Connecting…', 'Подключение…')
                  : _connectLabel(l)),
            ),
            if (widget.onPhoneOnly != null)
              Center(
                child: TextButton.icon(
                  onPressed: widget.busy ? null : widget.onPhoneOnly,
                  icon: const Icon(Icons.smartphone, size: 18),
                  label: Text(l.t('Just view my network (no router)',
                      'Просто смотреть свою сеть (без роутера)')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Default port of the selected transport, so the empty field is self-explanatory.
  String _portHint(L10n l) {
    if (_vendor == RouterVendor.keenetic) return _useTls ? '443' : '80';
    switch (_transport) {
      case TransportPreference.auto:
        return l.t('default per transport', 'по умолчанию для транспорта');
      case TransportPreference.rest:
        return _useTls ? '443' : '80';
      case TransportPreference.binary:
        return _useTls ? '8729' : '8728';
      case TransportPreference.ssh:
        return '22';
    }
  }

  String _connectLabel(L10n l) {
    if (_vendor == RouterVendor.keenetic) {
      return l.t('Connect to Keenetic', 'Подключиться к Keenetic');
    }
    final n = _routers.length +
        (_currentInput() != null &&
                !_routers.any((router) =>
                    router.vendor == _currentInput()!.vendor &&
                    router.host == _currentInput()!.host)
            ? 1
            : 0);
    return n > 1
        ? l.t('Connect ($n routers)', 'Подключить ($n роутеров)')
        : l.t('Connect', 'Подключить');
  }

  String _formTitle(L10n l) {
    if (_vendor == RouterVendor.keenetic) {
      return l.t('Keenetic connection', 'Подключение к Keenetic');
    }
    if (widget.quickConnection) {
      return l.t('Quick connection', 'Быстрое подключение');
    }
    final site = widget.site;
    final name = site?.imported == true
        ? l.t('Imported routers', 'Импортированные роутеры')
        : site?.name;
    return site == null
        ? l.t('MikroTik connection', 'Подключение к MikroTik')
        : l.t('Site: $name', 'Объект: $name');
  }

  String _addLabel(L10n l) => _vendor == RouterVendor.keenetic
      ? l.t('Save this profile', 'Сохранить этот профиль')
      : widget.quickConnection
          ? l.t('Add another temporary router', 'Добавить временный роутер')
          : l.t('Add router to site', 'Добавить роутер в объект');

  /// `192.168.88.1 · monitor · SSH:2222` — the transport only shows when it was
  /// pinned, since `auto` is the norm.
  String _chipLabel(RouterConnection r) {
    final parts = [
      r.vendor == RouterVendor.keenetic ? 'Keenetic Alpha' : 'MikroTik',
      '${r.host}  ·  ${r.username}',
    ];
    if (r.vendor == RouterVendor.keenetic) {
      parts.add(r.port == null ? 'RCI' : 'RCI:${r.port}');
    } else if (r.transport != TransportPreference.auto) {
      final name = r.transport == TransportPreference.binary
          ? 'API'
          : r.transport.name.toUpperCase();
      parts.add(r.port == null ? name : '$name:${r.port}');
    }
    if (r.portKnocking.enabled) parts.add('Knock');
    return parts.join('  ·  ');
  }

  Widget _routerChip(RouterConnection r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.router, size: 16, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _editRouter(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  _chipLabel(r),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () => _removeRouter(r),
            child: const Icon(Icons.close, size: 16, color: Color(0xFF7D8590)),
          ),
        ],
      ),
    );
  }
}
