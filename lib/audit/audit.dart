import '../mikrotik/mikrotik_service.dart';

enum AuditSeverity { critical, warn, info, ok }

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

  const Finding(
    this.sev, {
    required this.titleEn,
    required this.titleRu,
    required this.detailEn,
    required this.detailRu,
    this.fixEn,
    this.fixRu,
    this.where,
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
  Future<List<Finding>> run(List<MikrotikService> routers) async {
    final out = <Finding>[];
    for (final svc in routers) {
      final c = await _gather(svc);
      _routerInfo(c, out);
      _deviceChecks(c, out);
      _capsmanChecks(c, out);
      _standaloneChecks(c, out);
      _bestPractices(c, out);
      _hardeningChecks(c, out);
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

  /// Positive/pass checks and policies — so a healthy router still gets a
  /// substantive report, and good practices are confirmed.
  void _bestPractices(_Ctx c, List<Finding> out) {
    // Regulatory country.
    final countries =
        c.wireless.map((w) => w['country'] ?? '').where((s) => s.isNotEmpty);
    if (countries.isNotEmpty &&
        countries.every((s) => s != 'no_country_set')) {
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
        c.wireless.every((w) => (w['tx-power-mode'] ?? 'default') == 'default')) {
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
    } else {
      out.add(const Finding(AuditSeverity.info,
          titleEn: 'No signal-based access rules',
          titleRu: 'Нет правил по сигналу',
          detailEn:
              'Nothing forces weak clients to roam — a phone can cling to a far '
              'AP. Consider access-list signal-range + allow-signal-out-of-range.',
          detailRu:
              'Ничто не гонит слабых клиентов роумиться — телефон может '
              'залипнуть на дальней точке. Рассмотри access-list signal-range + '
              'allow-signal-out-of-range.'));
    }

    // Client isolation on active configs' datapaths.
    final activeConfigs = <String>{
      for (final i in c.capsIfaces)
        if (i['running'] == 'true' && (i['configuration'] ?? '').isNotEmpty)
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

  Future<_Ctx> _gather(MikrotikService svc) async {
    Future<List<Map<String, String>>> read(String m) async {
      try {
        return await svc.readMenu(m);
      } catch (_) {
        return const [];
      }
    }

    final resource = await read('/system/resource');
    final ntp = await read('/system/ntp/client');
    final update = await read('/system/package/update');
    return _Ctx(
      capsIfaces: await read('/caps-man/interface'),
      capsConfigs: await read('/caps-man/configuration'),
      capsSecs: {
        for (final s in await read('/caps-man/security')) s['name'] ?? '': s
      },
      wireless: await read('/interface/wireless'),
      wirelessProfiles: {
        for (final p in await read('/interface/wireless/security-profiles'))
          p['name'] ?? '': p
      },
      datapaths: {
        for (final d in await read('/caps-man/datapath')) d['name'] ?? '': d
      },
      accessList: [
        ...await read('/caps-man/access-list'),
        ...await read('/interface/wireless/access-list'),
      ],
      resource: resource.isEmpty ? null : resource.first,
      host: svc.host,
      ntp: ntp.isEmpty ? null : ntp.first,
      update: update.isEmpty ? null : update.first,
      services: await read('/ip/service'),
      users: await read('/user'),
      pools: await read('/ip/pool'),
      leases: await read('/ip/dhcp-server/lease'),
      filter: await read('/ip/firewall/filter'),
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
            fixEn: 'Use tx-power-mode=default; reduce power via country/antenna '
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

    final active = c.capsIfaces.where((i) => i['running'] == 'true').toList();
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
            detailRu:
                'Канал $freq пересекается с соседними. В 2.4 ГГц не '
                'пересекаются только 1, 6 и 11.'));
      }
    });

    // Pass: 2.4 GHz channel plan is clean.
    if (had24 && !chan24Issue) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: '2.4 GHz channel plan is clean',
          titleRu: 'Канал-план 2.4 ГГц в порядке',
          detailEn:
              'All 2.4 GHz radios run 20 MHz on non-overlapping channels '
              '(1 / 6 / 11) — textbook.',
          detailRu:
              'Все радио 2.4 ГГц — 20 МГц на непересекающихся каналах '
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
          detailEn:
              'Defined but not assigned to any running radio, so not '
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
        'enc':
            '${p['encryption'] ?? ''},${p['group-encryption'] ?? ''}',
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

  void _hardeningChecks(_Ctx c, List<Finding> out) {
    // NTP time sync.
    final ntp = c.ntp;
    if (ntp != null) {
      if (ntp['enabled'] == 'true') {
        out.add(Finding(AuditSeverity.ok,
            titleEn: 'NTP time sync on',
            titleRu: 'Синхронизация времени (NTP)',
            detailEn:
                'Clock is synced (${ntp['status'] ?? 'ok'}) — certificates, '
                'logs and schedules stay correct.',
            detailRu:
                'Часы синхронизированы (${ntp['status'] ?? 'ok'}) — сертификаты, '
                'логи и расписания корректны.'));
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
            detailEn: '$installed → $latest. Updates fix security bugs; plan an '
                'upgrade.',
            detailRu: '$installed → $latest. Обновления чинят уязвимости — '
                'запланируй апгрейд.'));
      }
    }

    // Active management services (dedupe by standard port).
    final active = <String, Map<String, String>>{};
    for (final s in c.services) {
      final n = s['name'] ?? '';
      if (s['disabled'] == 'true') continue;
      if (_mgmtPorts[n] == s['port']) active[n] = s;
    }
    final defaultDrop = _hasDefaultDrop(c.filter);

    // Plaintext services — worth disabling regardless of the firewall.
    for (final n in ['ftp', 'telnet']) {
      if (active.containsKey(n)) {
        out.add(Finding(AuditSeverity.info,
            titleEn: '$n is enabled',
            titleRu: '$n включён',
            detailEn: '$n is a plaintext protocol. If you don\'t use it, turn '
                'it off to shrink the attack surface.',
            detailRu: '$n — протокол без шифрования. Если не используешь — '
                'выключи, чтобы сузить поверхность атаки.',
            fixEn: 'Disable $n in /ip service if unused.',
            fixRu: 'Отключи $n в /ip service, если не нужен.'));
      }
    }

    // Real exposure = no service-level ACL AND no catch-all drop on input.
    // (A default-deny firewall gates services even when their address is empty.)
    final noAcl = <String>[];
    for (final n in ['ssh', 'www-ssl', 'winbox', 'api', 'api-ssl', 'ftp']) {
      final s = active[n];
      if (s != null && (s['address'] ?? '').isEmpty) noAcl.add(n);
    }
    if (noAcl.isNotEmpty && !defaultDrop) {
      out.add(Finding(AuditSeverity.warn,
          titleEn: 'Management may be exposed',
          titleRu: 'Управление может быть открыто',
          detailEn: '${noAcl.join(', ')} have no service-level IP restriction, '
              'and the input firewall has no catch-all drop — they may accept '
              'connections from anywhere.',
          detailRu:
              '${noAcl.join(', ')} без ограничения по IP на уровне сервиса, и в '
              'firewall на input нет финального drop — могут принимать '
              'подключения откуда угодно.',
          fixEn: 'Add a default-deny to the input chain and/or restrict these '
              'services by address.',
          fixRu: 'Добавь финальный drop в input и/или ограничь эти сервисы по '
              'адресу.'));
    }

    // Default admin user.
    if (c.users
        .any((u) => u['name'] == 'admin' && u['disabled'] != 'true')) {
      out.add(const Finding(AuditSeverity.warn,
          titleEn: "Default 'admin' user present",
          titleRu: 'Есть дефолтный пользователь admin',
          detailEn: 'The well-known admin account is enabled — a common attack '
              'target.',
          detailRu: 'Включена стандартная учётка admin — частая цель атак.',
          fixEn: 'Create a named admin user and remove/disable admin.',
          fixRu: 'Заведи именованного админа, а admin убери/отключи.'));
    }

    // Firewall posture on the input chain.
    final hasInput =
        c.filter.any((f) => (f['chain'] ?? '').startsWith('input'));
    if (defaultDrop) {
      out.add(const Finding(AuditSeverity.ok,
          titleEn: 'Firewall: input default-deny',
          titleRu: 'Firewall: default-deny на input',
          detailEn: 'The input chain drops everything not explicitly allowed — '
              'services are gated by the firewall, not just their address ACL.',
          detailRu: 'Input-цепочка отбрасывает всё, что явно не разрешено — '
              'сервисы гейтит firewall, а не только их address-ACL.'));
    } else if (hasInput) {
      out.add(const Finding(AuditSeverity.info,
          titleEn: 'Input firewall: no catch-all drop found',
          titleRu: 'Firewall input: нет финального drop',
          detailEn: 'There are input rules but no default-deny was detected. '
              'Verify the router doesn\'t accept unsolicited traffic.',
          detailRu: 'Правила на input есть, но финального drop не нашла. '
              'Проверь, что роутер не принимает лишний трафик.'));
    } else {
      out.add(const Finding(AuditSeverity.warn,
          titleEn: 'No input firewall',
          titleRu: 'Нет firewall на input',
          detailEn: 'Nothing filters traffic to the router itself.',
          detailRu: 'Ничто не фильтрует трафик к самому роутеру.',
          fixEn: 'Add an input chain ending with a drop.',
          fixRu: 'Добавь цепочку input с финальным drop.'));
    }

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

  /// True if the input chain has a catch-all drop (default-deny) — a drop rule
  /// with no matcher that would limit which traffic it catches.
  bool _hasDefaultDrop(List<Map<String, String>> filter) {
    const limiters = [
      'protocol',
      'dst-port',
      'src-port',
      'port',
      'src-address',
      'dst-address',
      'src-address-list',
      'dst-address-list',
      'in-interface',
      'in-interface-list',
      'connection-state',
      'src-address-type',
      'dst-address-type',
      'connection-nat-state',
      'p2p',
      'content',
    ];
    for (final r in filter) {
      if ((r['chain'] ?? '') != 'input') continue;
      if (r['action'] != 'drop' || r['disabled'] == 'true') continue;
      final limited = limiters.any((k) => (r[k] ?? '').isNotEmpty);
      if (!limited) return true;
    }
    return false;
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
  final List<Map<String, String>> filter;
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
    required this.filter,
  });
}
