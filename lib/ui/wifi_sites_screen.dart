import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/router_connection.dart';
import '../services/credentials_store.dart';
import '../settings/settings_controller.dart';
import '../sites/wifi_site.dart';
import '../state/monitor_controller.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets/app_safe_area.dart';

class WifiSitesScreen extends StatefulWidget {
  final CredentialsStore? store;

  const WifiSitesScreen({super.key, this.store});

  @override
  State<WifiSitesScreen> createState() => _WifiSitesScreenState();
}

class _WifiSitesScreenState extends State<WifiSitesScreen> {
  late final CredentialsStore _store;
  List<WifiSite>? _sites;
  bool _storageFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? CredentialsStore();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _sites = null;
      _storageFailed = false;
    });
    try {
      final sites = await _store.loadSites();
      sites.sort(
        (a, b) => (b.lastUsedAtMs ?? 0).compareTo(a.lastUsedAtMs ?? 0),
      );
      if (mounted) setState(() => _sites = sites);
    } catch (_) {
      if (mounted) setState(() => _storageFailed = true);
    }
  }

  Future<bool> _writeSiteData(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) {
        final l = context.read<SettingsController>().l;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.t(
            'Could not save the site. Check macOS Keychain access and try again.',
            'Не удалось сохранить объект. Проверь доступ к Связке ключей macOS и повтори попытку.',
          )),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(WifiSite site) {
    final l = context.read<SettingsController>().l;
    return site.imported
        ? l.t('Imported routers', 'Импортированные роутеры')
        : site.name;
  }

  Future<bool> _prepareNewSession() async {
    final ctrl = context.read<MonitorController>();
    if (ctrl.state != MonitorState.connected) return true;
    final l = context.read<SettingsController>().l;
    final switchSession = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t('Switch site?', 'Сменить объект?')),
            content: Text(l.t(
              'The current Wi-Fi measurement will be disconnected before the '
                  'selected site opens.',
              'Текущий Wi-Fi-замер будет отключён перед открытием выбранного объекта.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.t('Switch', 'Переключить')),
              ),
            ],
          ),
        ) ??
        false;
    if (!switchSession) return false;
    await ctrl.disconnect();
    return mounted;
  }

  Future<void> _openSite(WifiSite site) async {
    if (!await _prepareNewSession()) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HomeScreen(
        vendor: RouterVendor.mikrotik,
        site: site,
      ),
    ));
    await _reload();
  }

  Future<void> _quickConnect() async {
    if (!await _prepareNewSession()) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const HomeScreen(
        vendor: RouterVendor.mikrotik,
        quickConnection: true,
      ),
    ));
    await _reload();
  }

  Future<void> _phoneOnly() async {
    final ctrl = context.read<MonitorController>();
    final settings = context.read<SettingsController>();
    if (!await _prepareNewSession()) return;
    if (!mounted) return;
    ctrl.applySettings(
      pollSeconds: settings.pollSeconds,
      healthPollSeconds: settings.healthPollSeconds,
      identityPollSeconds: settings.identityPollSeconds,
      historyLength: settings.historyLength,
      alertsEnabled: settings.alertsEnabled,
      alertThresholdDb: settings.alertThresholdDb,
      minSignalDbm: settings.minSignalDbm,
      minSnrDb: settings.minSnrDb,
      autoLinkDiagnostics: settings.autoLinkDiagnostics,
      linkDiagnosticDelaySeconds: settings.linkDiagnosticDelaySeconds,
    );
    await ctrl.startPhoneOnly();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const HomeScreen(vendor: RouterVendor.mikrotik),
    ));
  }

  Future<void> _continueSession() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const HomeScreen(vendor: RouterVendor.mikrotik),
    ));
    await _reload();
  }

  Future<void> _createSite() async {
    final result = await _editDialog();
    if (result == null) return;
    final site = WifiSite(
      id: 'site-${DateTime.now().microsecondsSinceEpoch}',
      name: result.$1,
      notes: result.$2,
    );
    if (!await _writeSiteData(() => _store.upsertSite(site))) return;
    if (!mounted) return;
    await _openSite(site);
  }

  Future<void> _editSite(WifiSite site) async {
    final result = await _editDialog(site: site);
    if (result == null) return;
    if (!await _writeSiteData(() => _store.upsertSite(site.copyWith(
          name: result.$1,
          notes: result.$2,
          imported: false,
        )))) {
      return;
    }
    await _reload();
  }

  Future<(String, String)?> _editDialog({WifiSite? site}) async {
    final l = context.read<SettingsController>().l;
    final name = TextEditingController(text: site == null ? '' : _name(site));
    final notes = TextEditingController(text: site?.notes ?? '');
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(site == null
            ? l.t('New site', 'Новый объект')
            : l.t('Edit site', 'Изменить объект')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.t('Site name', 'Название объекта'),
                hintText: l.t('Office', 'Офис'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.t('Notes (optional)', 'Примечание'),
                hintText:
                    l.t('Address, floor, customer…', 'Адрес, этаж, заказчик…'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('Cancel', 'Отмена')),
          ),
          FilledButton(
            onPressed: () {
              final value = name.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, (value, notes.text.trim()));
            },
            child: Text(l.t('Save', 'Сохранить')),
          ),
        ],
      ),
    );
    name.dispose();
    notes.dispose();
    return result;
  }

  Future<void> _deleteSite(WifiSite site) async {
    final l = context.read<SettingsController>().l;
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t('Delete site?', 'Удалить объект?')),
            content: Text(l.t(
              'Only this app\'s saved site and credentials will be deleted. '
                  'Nothing changes on the routers.',
              'Удалятся только сохранённый объект и его данные в приложении. '
                  'На роутерах ничего не изменится.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.t('Delete', 'Удалить')),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;
    if (!await _writeSiteData(() => _store.deleteSite(site.id))) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final ctrl = context.watch<MonitorController>();
    final sites = _sites;
    final active = ctrl.state == MonitorState.connected &&
        (ctrl.hasMikrotikRouters || ctrl.phoneOnly);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('MikroTik Wi-Fi sites', 'Объекты MikroTik Wi-Fi')),
        actions: [
          IconButton(
            tooltip: l.t('New site', 'Новый объект'),
            onPressed: _busy ? null : _createSite,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AppSafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _storageFailed
                  ? _SitesStorageError(onRetry: _reload)
                  : sites == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (active) ...[
                              _ActiveSessionCard(
                                phoneOnly: ctrl.phoneOnly,
                                onTap: _continueSession,
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              l.t(
                                'A site is one home, office or customer location with '
                                    'its own set of MikroTik routers and APs.',
                                'Объект — это дом, офис или площадка клиента со своим '
                                    'набором роутеров и точек MikroTik.',
                              ),
                              style: const TextStyle(
                                color: Color(0xFF8B949E),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (sites.isEmpty)
                              _EmptySites(onCreate: _createSite)
                            else
                              ...sites.map((site) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _SiteCard(
                                      name: _name(site),
                                      notes: site.notes,
                                      routerCount: site.routers.length,
                                      lastUsedAtMs: site.lastUsedAtMs,
                                      onTap: () => _openSite(site),
                                      onEdit: () => _editSite(site),
                                      onDelete: () => _deleteSite(site),
                                    ),
                                  )),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _quickConnect,
                              icon: const Icon(Icons.bolt_outlined),
                              label: Text(l.t(
                                'Quick connection without saving',
                                'Быстрое подключение без сохранения',
                              )),
                            ),
                            TextButton.icon(
                              onPressed: _phoneOnly,
                              icon: const Icon(Icons.smartphone),
                              label: Text(l.t(
                                'Phone-only network view',
                                'Просмотр сети только с телефона',
                              )),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _busy || _storageFailed || sites == null || sites.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _createSite,
                  icon: const Icon(Icons.add),
                  label: Text(l.t('New site', 'Новый объект')),
                ),
    );
  }
}

class _SitesStorageError extends StatelessWidget {
  final VoidCallback onRetry;

  const _SitesStorageError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.key_off_outlined,
                    size: 36,
                    color: Color(0xFFFFB74D),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.t(
                      'Saved sites are unavailable',
                      'Сохранённые объекты недоступны',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.t(
                      'The app could not access its secure credential storage. '
                          'On macOS, allow Keychain access and try again.',
                      'Приложение не смогло открыть защищённое хранилище учётных '
                          'данных. На macOS разреши доступ к Связке ключей и повтори попытку.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.t('Try again', 'Повторить')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  final String name;
  final String notes;
  final int routerCount;
  final int? lastUsedAtMs;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SiteCard({
    required this.name,
    required this.notes,
    required this.routerCount,
    required this.lastUsedAtMs,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.read<SettingsController>().l;
    final routerLabel = l.t(
      '$routerCount router(s)',
      _ruRouters(routerCount),
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_outlined,
                    color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        routerLabel,
                        if (lastUsedAtMs != null)
                          l.t('used ${_shortDate(lastUsedAtMs!)}',
                              'запуск ${_shortDate(lastUsedAtMs!)}'),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8B949E),
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFAAB2BD),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(l.t('Edit', 'Изменить')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l.t('Delete', 'Удалить')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortDate(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year}';
  }

  static String _ruRouters(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    if (lastTwo >= 11 && lastTwo <= 14) return '$count роутеров';
    if (last == 1) return '$count роутер';
    if (last >= 2 && last <= 4) return '$count роутера';
    return '$count роутеров';
  }
}

class _ActiveSessionCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool phoneOnly;
  const _ActiveSessionCard({required this.onTap, required this.phoneOnly});

  @override
  Widget build(BuildContext context) {
    final l = context.read<SettingsController>().l;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.phoneAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppTheme.phoneAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.sensors, color: AppTheme.phoneAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phoneOnly
                  ? l.t('A phone-only Wi-Fi measurement is active.',
                      'Замер Wi-Fi только с телефона уже запущен.')
                  : l.t('A MikroTik Wi-Fi measurement is active.',
                      'Замер MikroTik Wi-Fi уже запущен.'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(l.t('Continue', 'Продолжить')),
          ),
        ],
      ),
    );
  }
}

class _EmptySites extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptySites({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final l = context.read<SettingsController>().l;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.add_location_alt_outlined,
                size: 38, color: AppTheme.accent),
            const SizedBox(height: 9),
            Text(
              l.t('No sites yet', 'Объектов пока нет'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              l.t(
                'Create one and add the MikroTik routers that manage its APs.',
                'Создай объект и добавь MikroTik, управляющие его точками.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8B949E)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(l.t('Create site', 'Создать объект')),
            ),
          ],
        ),
      ),
    );
  }
}
