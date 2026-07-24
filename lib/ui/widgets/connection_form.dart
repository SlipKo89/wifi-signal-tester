import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../mikrotik/mikrotik_service.dart';
import '../../services/credentials_store.dart';
import '../../settings/settings_controller.dart';
import '../theme.dart';

/// Router connection form supporting several routers (e.g. a central CAPsMAN
/// box plus a standalone AP). Loads the saved list and hands it back on connect.
class ConnectionForm extends StatefulWidget {
  final void Function(List<RouterConnection> routers) onConnect;
  final VoidCallback? onPhoneOnly;
  final bool busy;

  const ConnectionForm({
    super.key,
    required this.onConnect,
    this.onPhoneOnly,
    this.busy = false,
  });

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final _store = CredentialsStore();
  final _host = TextEditingController();
  final _user = TextEditingController(text: 'monitor');
  final _pass = TextEditingController();

  final List<RouterConnection> _routers = [];

  TransportPreference _transport = TransportPreference.auto;
  bool _useTls = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _store.loadRouters().then((saved) {
      if (saved.isEmpty || !mounted) return;
      setState(() {
        _routers
          ..clear()
          ..addAll(saved);
        // Prefill the editor with the first saved router for convenience.
        final first = saved.first;
        _host.text = first.host;
        _user.text = first.username;
        _pass.text = first.password;
        _transport = first.transport;
        _useTls = first.useTls;
      });
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  RouterConnection? _currentInput() {
    final host = _host.text.trim();
    if (host.isEmpty) return null;
    return RouterConnection(
      host: host,
      username: _user.text.trim(),
      password: _pass.text,
      transport: _transport,
      useTls: _useTls,
    );
  }

  void _addRouter() {
    final cfg = _currentInput();
    if (cfg == null) return;
    setState(() {
      _routers.removeWhere((r) => r.host == cfg.host); // de-dup by host
      _routers.add(cfg);
      _host.clear();
      _pass.clear();
    });
    _store.saveRouters(_routers);
  }

  void _removeRouter(RouterConnection r) {
    setState(() => _routers.removeWhere((x) => x.host == r.host));
    _store.saveRouters(_routers);
  }

  void _connect() {
    // Include whatever is typed but not yet added.
    final list = [..._routers];
    final current = _currentInput();
    if (current != null && !list.any((r) => r.host == current.host)) {
      list.add(current);
    }
    if (list.isEmpty) return;
    _store.saveRouters(list);
    widget.onConnect(list);
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
            Text(l.t('MikroTik connection', 'Подключение к MikroTik'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              l.t(
                  'Read-only. Add every router whose APs you want to see '
                      '(central CAPsMAN + standalone APs).',
                  'Только чтение. Добавь каждый роутер, чьи точки хочешь видеть '
                      '(центральный CAPsMAN + отдельные точки).'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF7D8590)),
            ),
            if (_routers.isNotEmpty) ...[
              const SizedBox(height: 14),
              ..._routers.map(_routerChip),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Host / IP',
                prefixIcon: Icon(Icons.router_outlined),
                hintText: '192.168.88.1',
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
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TransportPreference>(
                    initialValue: _transport,
                    decoration:
                        InputDecoration(labelText: l.t('Transport', 'Транспорт')),
                    items: [
                      DropdownMenuItem(
                          value: TransportPreference.auto,
                          child: Text(l.t('Auto (REST → API)',
                              'Авто (REST → API)'))),
                      DropdownMenuItem(
                          value: TransportPreference.rest,
                          child: Text(l.t('REST only', 'Только REST'))),
                      DropdownMenuItem(
                          value: TransportPreference.binary,
                          child: Text(
                              l.t('Binary API only', 'Только бинарный API'))),
                    ],
                    onChanged: (v) => setState(
                        () => _transport = v ?? TransportPreference.auto),
                  ),
                ),
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
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addRouter,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.t('Add another router', 'Добавить ещё роутер')),
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

  String _connectLabel(L10n l) {
    final n = _routers.length + (_currentInput() != null &&
            !_routers.any((r) => r.host == _currentInput()!.host)
        ? 1
        : 0);
    return n > 1
        ? l.t('Connect ($n routers)', 'Подключить ($n роутеров)')
        : l.t('Connect', 'Подключить');
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
            child: Text('${r.host}  ·  ${r.username}',
                style: const TextStyle(fontSize: 13)),
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
