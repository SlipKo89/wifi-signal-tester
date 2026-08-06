import '../mikrotik/mikrotik_service.dart';
import '../mikrotik/router_os_transport.dart';

enum AuditSeverity { critical, warn, info, ok }

/// Which slice of checks to run.
enum AuditScope { wifi, system }

/// One audit result. Text is bilingual; the UI resolves via L10n.
class Finding {
  final AuditSeverity sev;
  final String titleEn;
  final String titleRu;
  final String detailEn;
  final String detailRu;
  final String? fixEn;
  final String? fixRu;
  final String? where;
  final String? sourceUrl;

  const Finding(
    this.sev, {
    required this.titleEn,
    required this.titleRu,
    required this.detailEn,
    required this.detailRu,
    this.fixEn,
    this.fixRu,
    this.where,
    this.sourceUrl,
  });
}

/// Parsed CAPsMAN `current-channel`, e.g. `5260/20-Ceee/ac/DP(20dBm)`.
class _Channel {
  final int? freq;
  final int? width;
  final int? txPowerDbm;
  const _Channel(this.freq, this.width, this.txPowerDbm);

  bool get is24 => freq != null && freq! < 2500;
}

/// Reads Wi-Fi config and operating state (read-only) from the connected
/// routers and flags common misconfigurations, aimed at people who set up
/// MikroTik APs without deep RF knowledge.
///
/// Design notes learned from real routers:
///  * REST returns only explicitly-set fields, so "field absent" ≠ "disabled".
///    Where possible we audit the *operating state* (`current-channel`), not the
///    config.
///  * A CAPsMAN configuration that isn't applied to a running radio is not on
///    air — we don't raise it as a live risk.
///  * Security can be inline on the configuration or via a named profile.
class AuditEngine {
  Future<List<Finding>> run(
    List<MikrotikService> routers, {
    AuditScope scope = AuditScope.wifi,
  }) async {
    final out = <Finding>[];
    for (final svc in routers) {
      final c = await _gather(svc, scope);
      _routerInfo(c, out);
      _dataGaps(c, out);
      if (scope == AuditScope.wifi) {
        _deviceChecks(c, out);
        _capsmanChecks(c, out);
        _standaloneChecks(c, out);
        _bestPractices(c, out);
      } else {
        _hardeningChecks(c, out);
      }
    }
    out.sort((a, b) => a.sev.index.compareTo(b.sev.index));
    return out;
  }

  void _routerInfo(_Ctx c, List<Finding> out) {
    final r = c.resource;
    if (r == null) return;
    out.add(Finding(AuditSeverity.info,
        titleEn: 'Router: ${r['board-name'] ?? '?'}',
        titleRu: 'Роутер: ${r['board-name'] ?? '?'}',
        detailEn:
            'RouterOS ${r['version'] ?? '?'} · CPU ${r['cpu-load'] ?? '?'}% · '
            'uptime ${r['uptime'] ?? '?'}.',
        detailRu:
            'RouterOS ${r['version'] ?? '?'} · CPU ${r['cpu-load'] ?? '?'}% · '
            'аптайм ${r['uptime'] ?? '?'}.',
        where: c.host));
  }

  /// Says out loud which menus couldn't be read. A report that silently omits
  /// half its checks looks exactly like a clean router — this makes the
  /// difference visible.
  void _dataGaps(_Ctx c, List<Finding> out) {
    if (c.unreadable.isEmpty) return;
    final list = (c.unreadable.toList()..sort()).join(', ');
    out.add(Finding(AuditSeverity.warn,
        titleEn: 'Report incomplete: ${c.unreadable.length} menu(s) unreadable',
        titleRu: 'Отчёт неполный: не прочитано меню — ${c.unreadable.length}',
        detailEn:
            'Checks that depend on these were skipped rather than guessed: '
            '$list. Usually a dropped session or a user without rights to them.',
        detailRu: 'Проверки, зависящие от них, пропущены, а не угаданы: $list. '
            'Обычно это оборванная сессия или пользователь без прав на них.',
        fixEn: 'Reconnect and run the audit again; check the user\'s group has '
            'the read policy.',
        fixRu: 'Переподключись и прогони аудит снова; проверь, что у группы '
            'пользователя есть политика read.',
        where: c.host));
  }

  /// Positive/pass checks and policies — so a healthy router still gets a
  /// substantive report, and good practices are confirmed.
  void _bestPractices(_Ctx c, List<Finding> out) {
    // Regulatory country.
    final countries =
        c.wireless.map((w) => w['country'] ?? '').where((s) => s.isNotEmpty);
    if (countries.isNotEmpty && countries.every((s) => s != 'no_country_set')) {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'Regulatory country set',
          titleRu: 'Страна задана',
          detailEn: 'Country is set (${countries.first}) — correct power and '
              'channel limits.',
          detailRu: 'Страна задана (${countries.first}) — верные лимиты '
              'мощности и каналов.'));
    }

    // TX-power mode.
    if (c.wireless.isNotEmpty &&
        c.wireless
            .every((w) => (w['tx-power-mode'] ?? 'default') == 'default')) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: 'TX power at default',
          titleRu: 'Мощность по умолчанию',
          detailEn: 'Radios use the card default power — the recommended, safe '
              'setting.',
          detailRu: 'Радио используют мощность по умолчанию — рекомендуемый '
              'безопасный вариант.'));
    }

    // Sticky-client mitigation via signal-based access rules.
    final signalRules = c.accessList.where((a) =>
        a['disabled'] != 'true' &&
        ((a['signal-range'] ?? '').isNotEmpty ||
            (a['allow-signal-out-of-range'] ?? '').isNotEmpty));
    if (signalRules.isNotEmpty) {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'Sticky-client mitigation on',
          titleRu: 'Отшибание «залипших» клиентов',
          detailEn:
              '${signalRules.length} access rule(s) use signal thresholds — '
              'weak clients get pushed off so they roam to a closer AP.',
          detailRu:
              '${signalRules.length} правил доступа с порогами сигнала — слабые '
              'клиенты сбрасываются и переходят на ближнюю точку.'));
    } else if (!c.unreadable.contains('/caps-man/access-list') &&
        !c.unreadable.contains('/interface/wireless/access-list')) {
      out.add(const Finding(AuditSeverity.info,
          titleEn: 'No signal-based access rules',
          titleRu: 'Нет правил по сигналу',
          detailEn:
              'Nothing forces weak clients to roam — a phone can cling to a far '
              'AP. Consider access-list signal-range + allow-signal-out-of-range.',
          detailRu: 'Ничто не гонит слабых клиентов роумиться — телефон может '
              'залипнуть на дальней точке. Рассмотри access-list signal-range + '
              'allow-signal-out-of-range.'));
    }

    // Client isolation on active configs' datapaths.
    final activeConfigs = <String>{
      for (final i in c.capsIfaces)
        if (_isRunning(i) && (i['configuration'] ?? '').isNotEmpty)
          i['configuration']!
    };
    final isolated = <String>{};
    for (final cfg in c.capsConfigs) {
      if (!activeConfigs.contains(cfg['name'])) continue;
      final dp = c.datapaths[cfg['datapath']];
      if (dp != null && dp['client-to-client-forwarding'] == 'false') {
        isolated.add(cfg['ssid'] ?? cfg['name'] ?? '');
      }
    }
    if (isolated.isNotEmpty) {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'Client isolation on',
          titleRu: 'Изоляция клиентов включена',
          detailEn:
              'Clients can\'t talk to each other on: ${isolated.join(', ')} — '
              'good for guest/IoT networks.',
          detailRu:
              'Клиенты не видят друг друга в: ${isolated.join(', ')} — хорошо '
              'для гостевых/IoT сетей.'));
    }

    // Wireless logging on? (useful events)
    // Handled in _logNote via a separate read is overkill; note-only here.
  }

  Future<_Ctx> _gather(MikrotikService svc, AuditScope scope) async {
    // A menu that simply doesn't exist on this stack reads as empty — that's
    // normal and the checks below cope. A menu that *failed* is different: it
    // must not be mistaken for "the feature isn't configured", which is how an
    // unreadable /ip/firewall/filter once turned into "no input firewall".
    final failed = <String>{};
    Future<List<Map<String, String>>> read(String m) async {
      try {
        return await svc.readMenu(m);
      } catch (_) {
        failed.add(m);
        return const [];
      }
    }

    final resource = await read('/system/resource');
    if (failed.contains('/system/resource')) {
      // Nothing readable at all — report that instead of inventing a report.
      throw RouterOsException(
          'Could not read the router — reconnect and run the audit again');
    }
    final system = scope == AuditScope.system;
    final ntp = system
        ? await read('/system/ntp/client')
        : const <Map<String, String>>[];
    final update = system
        ? await read('/system/package/update')
        : const <Map<String, String>>[];
    final macServer =
        system ? await read('/tool/mac-server') : const <Map<String, String>>[];
    final macWinbox = system
        ? await read('/tool/mac-server/mac-winbox')
        : const <Map<String, String>>[];
    final macPing = system
        ? await read('/tool/mac-server/ping')
        : const <Map<String, String>>[];
    final neighborDiscovery = system
        ? await read('/ip/neighbor/discovery-settings')
        : const <Map<String, String>>[];
    final bandwidthServer = system
        ? await read('/tool/bandwidth-server')
        : const <Map<String, String>>[];
    final dns = system ? await read('/ip/dns') : const <Map<String, String>>[];
    final proxy =
        system ? await read('/ip/proxy') : const <Map<String, String>>[];
    final socks =
        system ? await read('/ip/socks') : const <Map<String, String>>[];
    final upnp =
        system ? await read('/ip/upnp') : const <Map<String, String>>[];
    final cloud =
        system ? await read('/ip/cloud') : const <Map<String, String>>[];
    final ssh = system ? await read('/ip/ssh') : const <Map<String, String>>[];
    return _Ctx(
      capsIfaces: system ? const [] : await read('/caps-man/interface'),
      capsConfigs: system ? const [] : await read('/caps-man/configuration'),
      capsSecs: system
          ? const {}
          : {
              for (final s in await read('/caps-man/security'))
                s['name'] ?? '': s
            },
      wireless: system ? const [] : await read('/interface/wireless'),
      wirelessProfiles: system
          ? const {}
          : {
              for (final p
                  in await read('/interface/wireless/security-profiles'))
                p['name'] ?? '': p
            },
      datapaths: system
          ? const {}
          : {
              for (final d in await read('/caps-man/datapath'))
                d['name'] ?? '': d
            },
      accessList: system
          ? const []
          : [
              ...await read('/caps-man/access-list'),
              ...await read('/interface/wireless/access-list'),
            ],
      resource: resource.isEmpty ? null : resource.first,
      host: svc.host,
      ntp: ntp.isEmpty ? null : ntp.first,
      update: update.isEmpty ? null : update.first,
      services: system ? await read('/ip/service') : const [],
      users: system ? await read('/user') : const [],
      pools: system ? await read('/ip/pool') : const [],
      leases: system ? await read('/ip/dhcp-server/lease') : const [],
      ipv4Filter: system ? await read('/ip/firewall/filter') : const [],
      ipv6Filter: system ? await read('/ipv6/firewall/filter') : const [],
      macServer: macServer.isEmpty ? null : macServer.first,
      macWinbox: macWinbox.isEmpty ? null : macWinbox.first,
      macPing: macPing.isEmpty ? null : macPing.first,
      neighborDiscovery:
          neighborDiscovery.isEmpty ? null : neighborDiscovery.first,
      bandwidthServer: bandwidthServer.isEmpty ? null : bandwidthServer.first,
      dns: dns.isEmpty ? null : dns.first,
      proxy: proxy.isEmpty ? null : proxy.first,
      socks: socks.isEmpty ? null : socks.first,
      upnp: upnp.isEmpty ? null : upnp.first,
      cloud: cloud.isEmpty ? null : cloud.first,
      ssh: ssh.isEmpty ? null : ssh.first,
      unreadable: failed,
    );
  }

  // --- device-level (physical radio) checks --------------------------------

  void _deviceChecks(_Ctx c, List<Finding> out) {
    for (final w in c.wireless) {
      final name = w['name'] ?? '?';
      final country = w['country'] ?? '';
      if (country.isEmpty || country == 'no_country_set') {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'Regulatory country not set',
            titleRu: 'Не задана страна',
            detailEn:
                'No country on $name — power limits and allowed channels may be '
                'wrong, and modern clients may even ignore the radio.',
            detailRu:
                'На $name не задана страна — лимиты мощности и разрешённые '
                'каналы могут быть неверными, а новые клиенты могут вообще '
                'игнорировать радио.',
            fixEn: 'Set your real country on every radio (2.4 and 5 GHz).',
            fixRu: 'Укажи реальную страну на каждом радио (2.4 и 5 ГГц).',
            where: name));
      }
      if ((w['tx-power-mode'] ?? '') == 'all-rates-fixed') {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'tx-power-mode = all-rates-fixed',
            titleRu: 'tx-power-mode = all-rates-fixed',
            detailEn:
                '$name forces one TX power on all rates. High-order rates can\'t '
                'take full power — this degrades throughput. Not recommended.',
            detailRu:
                '$name задаёт одну мощность на все скорости. Высокие MCS не '
                'тянут полную мощность — падает пропускная. Не рекомендуется.',
            fixEn:
                'Use tx-power-mode=default; reduce power via country/antenna '
                'gain if needed.',
            fixRu: 'Используй tx-power-mode=default; снижай мощность через '
                'страну/antenna-gain при необходимости.',
            where: name));
      }
    }
  }

  // --- CAPsMAN (operating state + applied configs) -------------------------

  void _capsmanChecks(_Ctx c, List<Finding> out) {
    if (c.capsIfaces.isEmpty) return;

    final active = c.capsIfaces.where(_isRunning).toList();
    final activeConfigs = <String>{
      for (final i in active)
        if ((i['configuration'] ?? '').isNotEmpty) i['configuration']!
    };

    // Operating-state RF checks per active radio.
    final freq24 = <int, int>{}; // freq -> count (2.4 GHz)
    var had24 = false;
    var chan24Issue = false;
    for (final i in active) {
      final name = i['name'] ?? '?';
      final ch = _parseChannel(i['current-channel']);
      if (ch.is24) {
        had24 = true;
        if (ch.width != null && ch.width! > 20) {
          chan24Issue = true;
          out.add(Finding(AuditSeverity.warn,
              titleEn: '2.4 GHz running ${ch.width} MHz',
              titleRu: '2.4 ГГц на ${ch.width} МГц',
              detailEn:
                  '$name is on a ${ch.width} MHz channel at 2.4 GHz, where only '
                  '3 channels fit. Wider = more interference, not more speed.',
              detailRu:
                  '$name на канале ${ch.width} МГц в 2.4 ГГц, где помещается '
                  'всего 3 канала. Шире = больше помех, а не скорости.',
              fixEn: 'Use 20 MHz on 2.4 GHz.',
              fixRu: 'Поставь 20 МГц на 2.4 ГГц.',
              where: name));
        }
        if (ch.freq != null) {
          freq24[ch.freq!] = (freq24[ch.freq!] ?? 0) + 1;
        }
      }
      if (ch.txPowerDbm != null && ch.txPowerDbm! > 23) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'High TX power (${ch.txPowerDbm} dBm)',
            titleRu: 'Высокая мощность (${ch.txPowerDbm} dBm)',
            detailEn:
                '$name transmits at ${ch.txPowerDbm} dBm. Too much power causes '
                'asymmetry (AP shouts, clients can\'t answer) and co-channel '
                'noise; it can even overheat the radio.',
            detailRu:
                '$name передаёт на ${ch.txPowerDbm} dBm. Избыток мощности даёт '
                'асимметрию (точка «кричит», клиенты не отвечают) и шум на '
                'канале, вплоть до перегрева радио.',
            fixEn: 'Leave tx-power at default or lower it; don\'t inflate it.',
            fixRu: 'Оставь мощность по умолчанию или снизь; не задирай.',
            where: name));
      }
    }

    // Co-channel: same 2.4 GHz frequency on more than one active radio.
    freq24.forEach((freq, count) {
      if (count > 1) {
        chan24Issue = true;
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'Co-channel on 2.4 GHz ($freq)',
            titleRu: 'Совпадение канала 2.4 ГГц ($freq)',
            detailEn:
                '$count of your radios share 2.4 GHz channel $freq. They talk '
                'over each other. Spread APs across channels 1, 6 and 11.',
            detailRu:
                '$count твоих радио сидят на одном канале 2.4 ГГц $freq и '
                'глушат друг друга. Разнеси точки по каналам 1, 6 и 11.',
            fixEn: 'Assign non-overlapping channels (1 / 6 / 11).',
            fixRu: 'Назначь непересекающиеся каналы (1 / 6 / 11).'));
      } else if (![2412, 2437, 2462].contains(freq)) {
        chan24Issue = true;
        out.add(Finding(AuditSeverity.info,
            titleEn: 'Non-standard 2.4 channel ($freq)',
            titleRu: 'Нестандартный канал 2.4 ($freq)',
            detailEn:
                'Channel $freq overlaps its neighbours. On 2.4 GHz only 1, 6 '
                'and 11 don\'t overlap.',
            detailRu: 'Канал $freq пересекается с соседними. В 2.4 ГГц не '
                'пересекаются только 1, 6 и 11.'));
      }
    });

    // Pass: 2.4 GHz channel plan is clean.
    if (had24 && !chan24Issue) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: '2.4 GHz channel plan is clean',
          titleRu: 'Канал-план 2.4 ГГц в порядке',
          detailEn: 'All 2.4 GHz radios run 20 MHz on non-overlapping channels '
              '(1 / 6 / 11) — textbook.',
          detailRu: 'Все радио 2.4 ГГц — 20 МГц на непересекающихся каналах '
              '(1 / 6 / 11) — как надо.'));
    }

    // Security of applied configurations only.
    final notOnAir = <String>[];
    for (final cfg in c.capsConfigs) {
      final name = cfg['name'] ?? '';
      final ssid = cfg['ssid'] ?? name;
      if (!activeConfigs.contains(name)) {
        notOnAir.add(ssid);
        continue;
      }
      _securityFinding(_resolveSecurity(cfg, c.capsSecs), ssid, out);
    }
    if (notOnAir.isNotEmpty) {
      final list = notOnAir.join(', ');
      out.add(Finding(AuditSeverity.info,
          titleEn: '${notOnAir.length} config(s) not on air',
          titleRu: 'Конфигов не в эфире: ${notOnAir.length}',
          detailEn: 'Defined but not assigned to any running radio, so not '
              'broadcasting (not audited): $list.',
          detailRu:
              'Заданы, но не назначены ни на одно активное радио, значит не '
              'вещают (в аудит не идут): $list.'));
    }
  }

  // --- standalone /interface/wireless (not CAPsMAN-managed) ----------------

  void _standaloneChecks(_Ctx c, List<Finding> out) {
    final managed = <String>{
      for (final i in c.capsIfaces)
        if ((i['radio-mac'] ?? '').isNotEmpty &&
            i['radio-mac'] != '00:00:00:00:00:00')
          i['radio-mac']!.toLowerCase()
    };

    for (final w in c.wireless) {
      if (managed.contains((w['mac-address'] ?? '').toLowerCase())) continue;
      final name = w['name'] ?? '?';
      final band = w['band'] ?? '';
      final width = w['channel-width'] ?? '';

      if (band.startsWith('2ghz') && width.contains('40')) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: '2.4 GHz set to 40 MHz',
            titleRu: '2.4 ГГц на 40 МГц',
            detailEn: '$name is configured for 40 MHz on 2.4 GHz — use 20 MHz.',
            detailRu: '$name настроен на 40 МГц в 2.4 ГГц — используй 20 МГц.',
            fixEn: 'Set channel width to 20 MHz.',
            fixRu: 'Поставь ширину 20 МГц.',
            where: name));
      }
      if ((w['wmm-support'] ?? '') == 'disabled') {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'WMM disabled',
            titleRu: 'WMM выключен',
            detailEn:
                '$name has WMM off. WMM (QoS) is needed for higher 802.11n/ac '
                'rates and smoother traffic.',
            detailRu:
                'У $name выключен WMM. WMM (QoS) нужен для высоких скоростей '
                '802.11n/ac и ровного трафика.',
            fixEn: 'Enable WMM support.',
            fixRu: 'Включи поддержку WMM.',
            where: name));
      }
      final basic = '${w['basic-rates-a/g'] ?? ''},${w['basic-rates-b'] ?? ''}';
      if (RegExp(r'(^|,)(1Mbps|2Mbps|5\.5Mbps|11Mbps)').hasMatch(basic)) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'Legacy basic rates enabled',
            titleRu: 'Включены legacy-рейты',
            detailEn:
                '$name allows 1/2/5.5/11 Mbps basic rates — old slow rates drag '
                'down the whole cell.',
            detailRu:
                '$name разрешает базовые 1/2/5.5/11 Мбит/с — старые медленные '
                'рейты тормозят всю соту.',
            fixEn: 'Raise the basic rate (drop rates below ~6–12 Mbps).',
            fixRu: 'Подними базовый рейт (убери ниже ~6–12 Мбит/с).',
            where: name));
      }
      _securityFinding(_wirelessSecurity(w, c.wirelessProfiles), name, out);
    }
  }

  // --- security helpers -----------------------------------------------------

  /// Resolves a CAPsMAN config's security, inline or via a named profile.
  Map<String, String> _resolveSecurity(
      Map<String, String> cfg, Map<String, Map<String, String>> named) {
    if (cfg.containsKey('security.authentication-types') ||
        cfg.containsKey('security.passphrase')) {
      return {
        'auth': cfg['security.authentication-types'] ??
            (cfg.containsKey('security.passphrase') ? 'wpa2-psk' : ''),
        'enc':
            '${cfg['security.encryption'] ?? ''},${cfg['security.group-encryption'] ?? ''}',
        'mode': 'dynamic-keys',
      };
    }
    final ref = cfg['security'] ?? '';
    if (ref.isNotEmpty && named.containsKey(ref)) {
      final p = named[ref]!;
      return {
        'auth': p['authentication-types'] ?? '',
        'enc': '${p['encryption'] ?? ''},${p['group-encryption'] ?? ''}',
        'mode': 'dynamic-keys',
      };
    }
    return {'auth': '', 'enc': '', 'mode': 'none'};
  }

  Map<String, String> _wirelessSecurity(
      Map<String, String> w, Map<String, Map<String, String>> profiles) {
    final p = profiles[w['security-profile']];
    if (p == null) return {'auth': '', 'enc': '', 'mode': 'none'};
    return {
      'auth': p['authentication-types'] ?? '',
      'enc': '${p['unicast-ciphers'] ?? ''},${p['group-ciphers'] ?? ''}',
      'mode': p['mode'] ?? '',
    };
  }

  void _securityFinding(
      Map<String, String> s, String where, List<Finding> out) {
    final auth = s['auth'] ?? '';
    final enc = s['enc'] ?? '';
    final mode = s['mode'] ?? '';

    if (mode == 'static-keys') {
      out.add(Finding(AuditSeverity.critical,
          titleEn: 'WEP / static keys',
          titleRu: 'WEP / статические ключи',
          detailEn: '"$where" uses WEP-style static keys — cracked in minutes.',
          detailRu:
              '«$where» использует WEP-подобные ключи — взламывается за минуты.',
          fixEn: 'Switch to WPA2/WPA3.',
          fixRu: 'Перейди на WPA2/WPA3.',
          where: where));
    } else if (mode == 'none' && auth.isEmpty) {
      out.add(Finding(AuditSeverity.critical,
          titleEn: 'Open network',
          titleRu: 'Открытая сеть',
          detailEn:
              '"$where" has no encryption — anyone nearby can join and sniff.',
          detailRu:
              '«$where» без шифрования — любой рядом может подключиться и '
              'слушать.',
          fixEn: 'Add WPA2 (or WPA2/WPA3) with a strong passphrase.',
          fixRu: 'Включи WPA2 (или WPA2/WPA3) с надёжным паролем.',
          where: where));
    } else if (auth.contains('wpa-psk') || auth.contains('wpa-eap')) {
      if (!auth.contains('wpa2') && !auth.contains('wpa3')) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'WPA1 only',
            titleRu: 'Только WPA1',
            detailEn: '"$where" allows WPA1 — deprecated and weak.',
            detailRu: '«$where» разрешает WPA1 — устарел и слаб.',
            fixEn: 'Require WPA2-PSK (drop WPA1).',
            fixRu: 'Оставь только WPA2-PSK (убери WPA1).',
            where: where));
      }
    } else if (enc.contains('tkip')) {
      out.add(Finding(AuditSeverity.warn,
          titleEn: 'TKIP encryption',
          titleRu: 'Шифрование TKIP',
          detailEn:
              '"$where" allows TKIP — insecure and caps the link at 54 Mbps.',
          detailRu:
              '«$where» разрешает TKIP — небезопасно и режет линк до 54 Мбит/с.',
          fixEn: 'Use AES-CCM (CCMP) only.',
          fixRu: 'Оставь только AES-CCM (CCMP).',
          where: where));
    } else if (auth.contains('wpa2') || auth.contains('wpa3')) {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'WPA2/WPA3 + AES',
          titleRu: 'WPA2/WPA3 + AES',
          detailEn: '"$where" uses modern encryption. Good.',
          detailRu: '«$where» использует современное шифрование. Хорошо.',
          where: where));
    }
  }

  _Channel _parseChannel(String? raw) {
    if (raw == null || raw.isEmpty) return const _Channel(null, null, null);
    final freq = RegExp(r'^(\d+)').firstMatch(raw);
    final width = RegExp(r'^\d+/(\d+)').firstMatch(raw);
    final power = RegExp(r'\((\d+)dBm\)').firstMatch(raw);
    return _Channel(
      freq == null ? null : int.tryParse(freq.group(1)!),
      width == null ? null : int.tryParse(width.group(1)!),
      power == null ? null : int.tryParse(power.group(1)!),
    );
  }

  // --- router hardening / health -------------------------------------------

  static const _mgmtPorts = {
    'ftp': '21',
    'telnet': '23',
    'ssh': '22',
    'www': '80',
    'www-ssl': '443',
    'api': '8728',
    'api-ssl': '8729',
    'winbox': '8291',
  };

  static const _hardeningUrl =
      'https://manual.mikrotik.com/docs/getting-started/securing-your-router/';
  static const _servicesUrl =
      'https://manual.mikrotik.com/docs/system-information-and-utilities/services/';

  void _hardeningChecks(_Ctx c, List<Finding> out) {
    // NTP time sync.
    final ntp = c.ntp;
    if (ntp != null) {
      final enabled = ntp['enabled'] == 'true';
      final status = (ntp['status'] ?? '').toLowerCase();
      if (enabled && status.contains('synchronized')) {
        out.add(Finding(AuditSeverity.ok,
            titleEn: 'NTP time sync on',
            titleRu: 'Синхронизация времени (NTP)',
            detailEn:
                'Clock is synced (${ntp['status'] ?? 'ok'}) — certificates, '
                'logs and schedules stay correct.',
            detailRu:
                'Часы синхронизированы (${ntp['status'] ?? 'ok'}) — сертификаты, '
                'логи и расписания корректны.'));
      } else if (enabled) {
        out.add(Finding(AuditSeverity.info,
            titleEn: 'NTP client enabled; sync not confirmed',
            titleRu: 'NTP включён, синхронизация не подтверждена',
            detailEn:
                'RouterOS reports status "${ntp['status'] ?? 'unknown'}". '
                'The client is configured, but the audit cannot confirm that '
                'the clock is synchronized.',
            detailRu:
                'RouterOS сообщает статус «${ntp['status'] ?? 'неизвестно'}». '
                'Клиент настроен, но аудит не может подтвердить синхронизацию '
                'часов.'));
      } else {
        out.add(const Finding(AuditSeverity.warn,
            titleEn: 'NTP time sync off',
            titleRu: 'NTP выключен',
            detailEn: 'The clock drifts without NTP — this breaks TLS certs, '
                'log timestamps and scheduled tasks.',
            detailRu: 'Без NTP часы плывут — ломаются TLS-сертификаты, время в '
                'логах и задачи по расписанию.',
            fixEn: 'Enable the NTP client with a couple of servers.',
            fixRu: 'Включи NTP-клиент с парой серверов.'));
      }
    }

    // Software update.
    final upd = c.update;
    if (upd != null) {
      final installed = upd['installed-version'] ?? '';
      final latest = upd['latest-version'] ?? '';
      if (latest.isNotEmpty &&
          latest != installed &&
          (upd['status'] ?? '').toLowerCase().contains('new')) {
        out.add(Finding(AuditSeverity.info,
            titleEn: 'RouterOS update available',
            titleRu: 'Доступно обновление RouterOS',
            detailEn:
                '$installed → $latest. Updates fix security bugs; plan an '
                'upgrade.',
            detailRu: '$installed → $latest. Обновления чинят уязвимости — '
                'запланируй апгрейд.',
            sourceUrl: '$_hardeningUrl#routeros-version'));
      }
    }

    // Active management services. A service stays the same service when the
    // administrator moves it to a non-standard port — filtering by the default
    // port here used to make e.g. telnet:2323 disappear from the audit.
    final active = <String, Map<String, String>>{};
    for (final s in c.services) {
      final n = s['name'] ?? '';
      if (s['disabled'] == 'true') continue;
      if (_mgmtPorts.containsKey(n)) active[n] = s;
    }
    if (active.isNotEmpty) {
      final labelsEn = active.entries
          .map((e) => _serviceLabel(e.key, e.value, customSuffix: ' (custom)'))
          .join(', ');
      final labelsRu = active.entries
          .map((e) =>
              _serviceLabel(e.key, e.value, customSuffix: ' (нестандартный)'))
          .join(', ');
      out.add(Finding(AuditSeverity.info,
          titleEn: 'Active management services',
          titleRu: 'Активные сервисы управления',
          detailEn:
              '$labelsEn. A custom port reduces background scanning noise, '
              'but does not replace an IP restriction or input firewall.',
          detailRu: '$labelsRu. Нестандартный порт уменьшает фоновый шум от '
              'сканеров, но не заменяет ограничение по IP или firewall input.',
          where: c.host,
          sourceUrl: '$_hardeningUrl#management-service-ports'));
    }

    // Plaintext services — worth disabling regardless of the firewall.
    for (final n in ['ftp', 'telnet', 'www', 'api']) {
      final service = active[n];
      if (service != null) {
        final label = _serviceLabel(n, service);
        out.add(Finding(AuditSeverity.warn,
            titleEn: '$label is enabled',
            titleRu: '$label включён',
            detailEn: '$label is a plaintext management service. If you don\'t '
                'use it, turn it off to shrink the attack surface.',
            detailRu: '$label — сервис управления без шифрования. Если не '
                'используешь — выключи, чтобы сузить поверхность атаки.',
            fixEn: 'Disable $n in /ip service if unused; prefer its encrypted '
                'alternative where one exists.',
            fixRu: 'Отключи $n в /ip service, если не нужен; по возможности '
                'используй зашифрованную альтернативу.',
            sourceUrl: '$_hardeningUrl#management-service-ports'));
      }
    }

    // Report only the service's own address restriction. We deliberately do
    // not infer WAN exposure from firewall rules: rule order, interface lists,
    // address lists and dynamic rules make that a separate product-sized task.
    final noAcl = <String>[];
    for (final n in _mgmtPorts.keys) {
      final s = active[n];
      if (s != null && !_hasServiceAcl(s['address'])) {
        noAcl.add(_serviceLabel(n, s));
      }
    }
    if (noAcl.isNotEmpty) {
      out.add(Finding(AuditSeverity.info,
          titleEn: 'No own IP restriction on management services',
          titleRu: 'Нет собственного IP-ограничения сервисов',
          detailEn: '${noAcl.join(', ')} do not restrict source addresses in '
              '/ip service. This is a fact about the service setting, not a '
              'claim that it is reachable from the internet: firewall rules '
              'are not analysed by this app.',
          detailRu: '${noAcl.join(', ')} не ограничивают адреса источников в '
              '/ip service. Это факт о настройке сервиса, а не утверждение о '
              'доступности из интернета: правила firewall приложение не '
              'анализирует.',
          fixEn: 'If appropriate, restrict trusted source prefixes in the '
              'service address field and review the firewall separately.',
          fixRu: 'Если подходит для твоей сети, ограничь доверенные подсети в '
              'поле address сервиса и отдельно проверь firewall.',
          sourceUrl: '$_servicesUrl#properties'));
    } else if (active.isNotEmpty) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: 'Management services have own IP restrictions',
          titleRu: 'Сервисы управления ограничены по IP',
          detailEn: 'Every active management service has a non-global address '
              'restriction. Firewall effectiveness is outside this audit.',
          detailRu: 'У каждого активного сервиса управления есть неглобальное '
              'ограничение address. Эффективность firewall в этот аудит не '
              'входит.',
          sourceUrl: '$_servicesUrl#properties'));
    }

    // Default admin user.
    final admin = c.users.where((u) => u['name'] == 'admin').toList();
    if (admin.isNotEmpty) {
      if (admin.first['disabled'] == 'true') {
        out.add(const Finding(AuditSeverity.ok,
            titleEn: "Default 'admin' disabled",
            titleRu: 'Дефолтный admin отключён',
            detailEn: 'The well-known admin account is disabled — good.',
            detailRu: 'Стандартная учётка admin отключена — хорошо.',
            sourceUrl: '$_hardeningUrl#access-username'));
      } else {
        out.add(const Finding(AuditSeverity.warn,
            titleEn: "Default 'admin' account is active",
            titleRu: 'Учётка admin активна',
            detailEn: 'The well-known admin account is enabled — a common '
                'attack target. Make sure its password was changed from the '
                'default (blank), or rename/disable it.',
            detailRu: 'Включена стандартная учётка admin — частая цель атак. '
                'Убедись, что пароль сменён с дефолтного (пустого), либо '
                'переименуй/отключи её.',
            fixEn: 'Change the admin password, or create a named admin and '
                'disable admin.',
            fixRu: 'Смени пароль admin, либо заведи именованного админа и '
                'отключи admin.',
            sourceUrl: '$_hardeningUrl#access-username'));
      }
    }

    _firewallPresence(c, out);
    _macAccessChecks(c, out);
    _neighborDiscoveryCheck(c, out);
    _bandwidthServerCheck(c, out);
    _dnsCheck(c, out);
    _additionalServiceCheck(
        c.proxy, 'Web proxy', 'Web proxy', '/ip proxy', out);
    _additionalServiceCheck(
        c.socks, 'SOCKS proxy', 'SOCKS-прокси', '/ip socks', out);
    _additionalServiceCheck(c.upnp, 'UPnP', 'UPnP', '/ip upnp', out);
    _cloudCheck(c, out);
    _sshCheck(c, active, out);

    // IP pool usage.
    for (final p in c.pools) {
      final ranges = p['ranges'] ?? '';
      final size = _rangeSize(ranges);
      if (size == null || size == 0) continue;
      final used =
          c.leases.where((l) => _inRanges(l['address'] ?? '', ranges)).length;
      final pct = (used * 100 / size).round();
      if (pct >= 85) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: "IP pool '${p['name']}' almost full",
            titleRu: 'IP-пул «${p['name']}» почти заполнен',
            detailEn: '$used of $size addresses used ($pct%). New devices may '
                'fail to get an IP.',
            detailRu: 'Занято $used из $size адресов ($pct%). Новые устройства '
                'могут не получить IP.',
            fixEn: 'Enlarge the pool range.',
            fixRu: 'Расширь диапазон пула.',
            where: p['name']));
      }
    }
  }

  void _firewallPresence(_Ctx c, List<Finding> out) {
    void check({
      required String version,
      required String menu,
      required List<Map<String, String>> rules,
    }) {
      if (c.unreadable.contains(menu)) return;
      final active = rules.where((r) => r['disabled'] != 'true').length;
      if (active == 0) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'No $version firewall filter rules',
            titleRu: 'Нет правил firewall для $version',
            detailEn: 'No active rules were found in $menu. A firewall should '
                'be configured for this protocol family.',
            detailRu: 'В $menu не найдено активных правил. Для этого семейства '
                'протоколов стоит настроить firewall.',
            fixEn:
                'Configure and verify the firewall in WinBox/WebFig. The app '
                'does not assess rule order or effectiveness.',
            fixRu: 'Настрой и проверь firewall в WinBox/WebFig. Приложение не '
                'оценивает порядок и эффективность правил.',
            sourceUrl: '$_hardeningUrl#firewall-rules-for-management-access'));
      } else {
        out.add(Finding(AuditSeverity.ok,
            titleEn: '$version firewall rules present',
            titleRu: 'Правила firewall для $version присутствуют',
            detailEn: '$active active filter rule(s) found. Presence only: the '
                'app does not analyse their order, coverage or effectiveness.',
            detailRu: 'Найдено активных правил: $active. Проверяется только '
                'наличие: порядок, покрытие и эффективность не анализируются.',
            sourceUrl: '$_hardeningUrl#firewall-rules-for-management-access'));
      }
    }

    check(version: 'IPv4', menu: '/ip/firewall/filter', rules: c.ipv4Filter);
    check(version: 'IPv6', menu: '/ipv6/firewall/filter', rules: c.ipv6Filter);
  }

  void _macAccessChecks(_Ctx c, List<Finding> out) {
    void allowedList(
      Map<String, String>? row,
      String titleEn,
      String titleRu,
    ) {
      if (row == null) return;
      final value = (row['allowed-interface-list'] ?? '').trim();
      if (value == 'none') {
        out.add(Finding(AuditSeverity.ok,
            titleEn: '$titleEn disabled',
            titleRu: '$titleRu отключён',
            detailEn: 'allowed-interface-list=none.',
            detailRu: 'allowed-interface-list=none.',
            sourceUrl: '$_hardeningUrl#routeros-mac-access'));
      } else {
        out.add(Finding(AuditSeverity.warn,
            titleEn: '$titleEn enabled',
            titleRu: '$titleRu включён',
            detailEn:
                'allowed-interface-list=${value.isEmpty ? 'unknown' : value}. '
                'MikroTik recommends disabling MAC management access in '
                'production networks.',
            detailRu:
                'allowed-interface-list=${value.isEmpty ? 'неизвестно' : value}. '
                'MikroTik рекомендует отключать управление по MAC в '
                'production-сетях.',
            fixEn: 'Set allowed-interface-list=none, or deliberately restrict '
                'it to a trusted management interface list.',
            fixRu: 'Установи allowed-interface-list=none либо осознанно '
                'ограничь доверенным списком интерфейсов.',
            sourceUrl: '$_hardeningUrl#routeros-mac-access'));
      }
    }

    allowedList(c.macServer, 'MAC Telnet', 'MAC Telnet');
    allowedList(c.macWinbox, 'MAC WinBox', 'MAC WinBox');
    final ping = c.macPing;
    if (ping != null) {
      final enabled = ping['enabled'] == 'true';
      out.add(Finding(enabled ? AuditSeverity.warn : AuditSeverity.ok,
          titleEn: enabled ? 'MAC Ping enabled' : 'MAC Ping disabled',
          titleRu: enabled ? 'MAC Ping включён' : 'MAC Ping отключён',
          detailEn: enabled
              ? 'MikroTik recommends disabling MAC Ping in production networks.'
              : 'MAC-level ping is disabled.',
          detailRu: enabled
              ? 'MikroTik рекомендует отключать MAC Ping в production-сетях.'
              : 'Ping на MAC-уровне отключён.',
          fixEn: enabled ? 'Set enabled=no in /tool mac-server ping.' : null,
          fixRu:
              enabled ? 'Установи enabled=no в /tool mac-server ping.' : null,
          sourceUrl: '$_hardeningUrl#routeros-mac-access'));
    }
  }

  void _neighborDiscoveryCheck(_Ctx c, List<Finding> out) {
    final row = c.neighborDiscovery;
    if (row == null) return;
    final value = (row['discover-interface-list'] ?? '').trim();
    final disabled = value == 'none';
    out.add(Finding(disabled ? AuditSeverity.ok : AuditSeverity.warn,
        titleEn: disabled
            ? 'Neighbor Discovery disabled'
            : 'Neighbor Discovery enabled',
        titleRu: disabled
            ? 'Neighbor Discovery отключён'
            : 'Neighbor Discovery включён',
        detailEn: disabled
            ? 'discover-interface-list=none.'
            : 'discover-interface-list=${value.isEmpty ? 'unknown' : value}. '
                'Discovery reveals router information on those interfaces.',
        detailRu: disabled
            ? 'discover-interface-list=none.'
            : 'discover-interface-list=${value.isEmpty ? 'неизвестно' : value}. '
                'Discovery раскрывает сведения о роутере на этих интерфейсах.',
        fixEn: disabled
            ? null
            : 'Set it to none, or restrict it to a trusted management list.',
        fixRu: disabled
            ? null
            : 'Установи none либо ограничь доверенным списком управления.',
        sourceUrl: '$_hardeningUrl#neighbor-discovery'));
  }

  void _bandwidthServerCheck(_Ctx c, List<Finding> out) {
    final row = c.bandwidthServer;
    if (row == null) return;
    final enabled = row['enabled'] == 'true';
    final authenticated = row['authenticate'] != 'false';
    if (!enabled) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: 'Bandwidth Test Server disabled',
          titleRu: 'Bandwidth Test Server отключён',
          detailEn: 'The resource-intensive test server is not listening.',
          detailRu: 'Ресурсоёмкий тестовый сервер не слушает подключения.',
          sourceUrl: '$_hardeningUrl#bandwidth-server'));
      return;
    }
    out.add(Finding(AuditSeverity.warn,
        titleEn: authenticated
            ? 'Bandwidth Test Server enabled'
            : 'Bandwidth Test Server has no authentication',
        titleRu: authenticated
            ? 'Bandwidth Test Server включён'
            : 'Bandwidth Test Server без авторизации',
        detailEn: authenticated
            ? 'Authentication is on, but MikroTik recommends disabling the '
                'server in production. Firewall reachability is not analysed.'
            : 'The server is enabled with authenticate=no. It can consume '
                'substantial CPU and bandwidth; firewall reachability is not '
                'analysed.',
        detailRu: authenticated
            ? 'Авторизация включена, но MikroTik рекомендует отключать сервер '
                'в production. Доступность через firewall не анализируется.'
            : 'Сервер включён с authenticate=no. Он способен занять заметную '
                'часть CPU и полосы; доступность через firewall не '
                'анализируется.',
        fixEn: 'Disable /tool bandwidth-server when it is not actively needed.',
        fixRu: 'Отключи /tool bandwidth-server, когда он не нужен.',
        sourceUrl: '$_hardeningUrl#bandwidth-server'));
  }

  void _dnsCheck(_Ctx c, List<Finding> out) {
    final row = c.dns;
    if (row == null) return;
    final remote = row['allow-remote-requests'] == 'true';
    out.add(Finding(remote ? AuditSeverity.info : AuditSeverity.ok,
        titleEn: remote
            ? 'Router accepts client DNS requests'
            : 'Remote DNS requests disabled',
        titleRu: remote
            ? 'Роутер принимает DNS-запросы клиентов'
            : 'Удалённые DNS-запросы отключены',
        detailEn: remote
            ? 'allow-remote-requests=yes. This may be intentional when the '
                'router is the LAN DNS cache. Confirm it is needed and review '
                'the firewall separately.'
            : 'allow-remote-requests=no.',
        detailRu: remote
            ? 'allow-remote-requests=yes. Это может быть правильно, если '
                'роутер работает DNS-кэшем для LAN. Подтверди необходимость и '
                'отдельно проверь firewall.'
            : 'allow-remote-requests=no.',
        sourceUrl: '$_hardeningUrl#dns-cache'));
  }

  void _additionalServiceCheck(
    Map<String, String>? row,
    String titleEn,
    String titleRu,
    String menu,
    List<Finding> out,
  ) {
    if (row == null) return;
    final enabled = row['enabled'] == 'true';
    out.add(Finding(enabled ? AuditSeverity.warn : AuditSeverity.ok,
        titleEn: enabled ? '$titleEn enabled' : '$titleEn disabled',
        titleRu: enabled ? '$titleRu включён' : '$titleRu отключён',
        detailEn: enabled
            ? 'MikroTik recommends disabling this service in production when '
                'it is not explicitly required.'
            : 'The optional service is disabled.',
        detailRu: enabled
            ? 'MikroTik рекомендует отключать этот сервис в production, если '
                'он явно не нужен.'
            : 'Дополнительный сервис отключён.',
        fixEn: enabled ? 'Set enabled=no in $menu.' : null,
        fixRu: enabled ? 'Установи enabled=no в $menu.' : null,
        sourceUrl: '$_hardeningUrl#additional-services'));
  }

  void _cloudCheck(_Ctx c, List<Finding> out) {
    final row = c.cloud;
    if (row == null) return;
    final ddns = (row['ddns-enabled'] ?? '').toLowerCase();
    final updateTime = row['update-time'] == 'true';
    final explicitlyEnabled = ddns == 'true' || ddns == 'yes';
    if (!explicitlyEnabled && !updateTime) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: 'Optional MikroTik Cloud services off',
          titleRu: 'Дополнительные сервисы MikroTik Cloud выключены',
          detailEn: 'Cloud DDNS is not explicitly enabled and cloud time '
              'updates are off.',
          detailRu: 'Cloud DDNS явно не включён, обновление времени через '
              'облако выключено.',
          sourceUrl: '$_hardeningUrl#additional-services'));
      return;
    }
    out.add(Finding(AuditSeverity.info,
        titleEn: 'MikroTik Cloud feature enabled',
        titleRu: 'Включена функция MikroTik Cloud',
        detailEn: 'ddns-enabled=${ddns.isEmpty ? 'unknown' : ddns}, '
            'update-time=${updateTime ? 'yes' : 'no'}. Confirm these cloud '
            'features are intentional.',
        detailRu: 'ddns-enabled=${ddns.isEmpty ? 'неизвестно' : ddns}, '
            'update-time=${updateTime ? 'yes' : 'no'}. Подтверди, что эти '
            'облачные функции включены осознанно.',
        sourceUrl: '$_hardeningUrl#additional-services'));
  }

  void _sshCheck(
    _Ctx c,
    Map<String, Map<String, String>> active,
    List<Finding> out,
  ) {
    if (!active.containsKey('ssh') || c.ssh == null) return;
    final strong = c.ssh!['strong-crypto'] == 'true';
    out.add(Finding(strong ? AuditSeverity.ok : AuditSeverity.warn,
        titleEn: strong ? 'SSH strong crypto enabled' : 'SSH strong crypto off',
        titleRu: strong
            ? 'Усиленная криптография SSH включена'
            : 'Усиленная криптография SSH выключена',
        detailEn: strong
            ? 'strong-crypto=yes.'
            : 'SSH is active with strong-crypto=no. MikroTik recommends the '
                'stricter cipher, HMAC and key-exchange set.',
        detailRu: strong
            ? 'strong-crypto=yes.'
            : 'SSH активен с strong-crypto=no. MikroTik рекомендует более '
                'строгий набор шифров, HMAC и обмена ключами.',
        fixEn: strong ? null : 'Set strong-crypto=yes in /ip ssh.',
        fixRu: strong ? null : 'Установи strong-crypto=yes в /ip ssh.',
        sourceUrl: '$_hardeningUrl#more-secure-ssh-access'));
  }

  /// True if a CAPsMAN interface is on the air.
  ///
  /// REST reports it as `running`; the SSH console marks a bound radio with a
  /// flag letter instead, so `current-state` (`running-ap`) is the second
  /// witness. Both transports agree on the outcome.
  bool _isRunning(Map<String, String> iface) =>
      iface['running'] == 'true' ||
      (iface['current-state'] ?? '').startsWith('running');

  /// `ssh` on port 2222 becomes `ssh:2222`; missing ports fall back to the
  /// RouterOS default so an incomplete transport response is still readable.
  String _serviceLabel(
    String name,
    Map<String, String> service, {
    String customSuffix = '',
  }) {
    final defaultPort = _mgmtPorts[name];
    final port = (service['port'] ?? defaultPort ?? '').trim();
    if (port.isEmpty) return name;
    final custom = defaultPort != null && port != defaultPort;
    return '$name:$port${custom ? customSuffix : ''}';
  }

  /// Empty and explicit any-address values both mean that `/ip service` itself
  /// does not restrict who may connect. Firewall checks are handled separately.
  bool _hasServiceAcl(String? raw) {
    final values = (raw ?? '')
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (values.isEmpty) return false;
    if (values.any((v) => v == '0.0.0.0/0' || v == '::/0')) return false;
    return true;
  }

  int? _ipToInt(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    var v = 0;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      v = v * 256 + n;
    }
    return v;
  }

  int? _rangeSize(String ranges) {
    var total = 0;
    var any = false;
    for (final raw in ranges.split(',')) {
      final t = raw.trim();
      if (t.contains('-')) {
        final ab = t.split('-');
        final a = _ipToInt(ab.first);
        final b = _ipToInt(ab.last);
        if (a != null && b != null && b >= a) {
          total += b - a + 1;
          any = true;
        }
      } else if (t.contains('/')) {
        final cidr = t.split('/');
        final bits = int.tryParse(cidr.last);
        if (bits != null && bits >= 0 && bits <= 32) {
          total += 1 << (32 - bits);
          any = true;
        }
      }
    }
    return any ? total : null;
  }

  bool _inRanges(String ip, String ranges) {
    final v = _ipToInt(ip);
    if (v == null) return false;
    for (final raw in ranges.split(',')) {
      final t = raw.trim();
      if (t.contains('-')) {
        final ab = t.split('-');
        final a = _ipToInt(ab.first);
        final b = _ipToInt(ab.last);
        if (a != null && b != null && v >= a && v <= b) return true;
      } else if (t.contains('/')) {
        final cidr = t.split('/');
        final base = _ipToInt(cidr.first);
        final bits = int.tryParse(cidr.last);
        if (base != null && bits != null && bits >= 0 && bits <= 32) {
          final mask = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
          if ((v & mask) == (base & mask)) return true;
        }
      }
    }
    return false;
  }
}

class _Ctx {
  final List<Map<String, String>> capsIfaces;
  final List<Map<String, String>> capsConfigs;
  final Map<String, Map<String, String>> capsSecs;
  final List<Map<String, String>> wireless;
  final Map<String, Map<String, String>> wirelessProfiles;
  final Map<String, Map<String, String>> datapaths;
  final List<Map<String, String>> accessList;
  final Map<String, String>? resource;
  final String? host;
  final Map<String, String>? ntp;
  final Map<String, String>? update;
  final List<Map<String, String>> services;
  final List<Map<String, String>> users;
  final List<Map<String, String>> pools;
  final List<Map<String, String>> leases;
  final List<Map<String, String>> ipv4Filter;
  final List<Map<String, String>> ipv6Filter;
  final Map<String, String>? macServer;
  final Map<String, String>? macWinbox;
  final Map<String, String>? macPing;
  final Map<String, String>? neighborDiscovery;
  final Map<String, String>? bandwidthServer;
  final Map<String, String>? dns;
  final Map<String, String>? proxy;
  final Map<String, String>? socks;
  final Map<String, String>? upnp;
  final Map<String, String>? cloud;
  final Map<String, String>? ssh;

  /// Menus whose read threw — treated as "unknown", never as "empty".
  final Set<String> unreadable;
  _Ctx({
    required this.capsIfaces,
    required this.capsConfigs,
    required this.capsSecs,
    required this.wireless,
    required this.wirelessProfiles,
    required this.datapaths,
    required this.accessList,
    required this.resource,
    required this.host,
    required this.ntp,
    required this.update,
    required this.services,
    required this.users,
    required this.pools,
    required this.leases,
    required this.ipv4Filter,
    required this.ipv6Filter,
    required this.macServer,
    required this.macWinbox,
    required this.macPing,
    required this.neighborDiscovery,
    required this.bandwidthServer,
    required this.dns,
    required this.proxy,
    required this.socks,
    required this.upnp,
    required this.cloud,
    required this.ssh,
    required this.unreadable,
  });
}
