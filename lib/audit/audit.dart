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

/// Reads Wi-Fi config (read-only) from the connected routers and flags common
/// misconfigurations for someone who sets up MikroTik APs without deep RF
/// knowledge.
class AuditEngine {
  Future<List<Finding>> run(List<MikrotikService> routers) async {
    final out = <Finding>[];
    for (final svc in routers) {
      // Radios driven by CAPsMAN: their local /interface/wireless config is
      // overridden by the manager, so auditing it would produce false results.
      final managed = await _capsmanRadioMacs(svc);
      await _wireless(svc, out, managed);
      await _capsman(svc, out);
    }
    out.sort((a, b) => a.sev.index.compareTo(b.sev.index));
    return out;
  }

  Future<Set<String>> _capsmanRadioMacs(MikrotikService svc) async {
    final ifaces = await _safe(svc, '/caps-man/interface');
    return {
      for (final i in ifaces)
        if ((i['radio-mac'] ?? '').isNotEmpty &&
            i['radio-mac'] != '00:00:00:00:00:00')
          i['radio-mac']!.toLowerCase()
    };
  }

  Future<List<Map<String, String>>> _safe(
      MikrotikService svc, String menu) async {
    try {
      return await svc.readMenu(menu);
    } catch (_) {
      return const [];
    }
  }

  // --- classic /interface/wireless ----------------------------------------

  Future<void> _wireless(
      MikrotikService svc, List<Finding> out, Set<String> managed) async {
    final ifaces = await _safe(svc, '/interface/wireless');
    if (ifaces.isEmpty) return;
    final profiles = await _safe(svc, '/interface/wireless/security-profiles');
    final byName = {for (final p in profiles) p['name']: p};

    for (final w in ifaces) {
      // Skip CAPsMAN-managed radios — the manager overrides this config.
      if (managed.contains((w['mac-address'] ?? '').toLowerCase())) continue;

      final name = w['name'] ?? '?';
      final band = w['band'] ?? '';
      final width = w['channel-width'] ?? '';

      if (band.startsWith('2ghz') && width.contains('40')) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: '2.4 GHz using 40 MHz',
            titleRu: '2.4 ГГц на 40 МГц',
            detailEn:
                '$name runs a 40 MHz channel on 2.4 GHz, where only 3 channels '
                "don't overlap. This interferes with itself and neighbours.",
            detailRu:
                '$name работает на 40 МГц в 2.4 ГГц, где всего 3 непересекающихся '
                'канала. Это создаёт помехи себе и соседям.',
            fixEn: 'Set channel width to 20 MHz on 2.4 GHz.',
            fixRu: 'Поставь ширину канала 20 МГц на 2.4 ГГц.',
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
            fixEn: 'Enable WMM support on the interface.',
            fixRu: 'Включи поддержку WMM на интерфейсе.',
            where: name));
      }

      final country = w['country'] ?? '';
      if (country.isEmpty || country == 'no_country_set') {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'Regulatory country not set',
            titleRu: 'Не задана страна',
            detailEn:
                '$name has no country set — power limits and allowed channels '
                'may be wrong.',
            detailRu:
                'У $name не задана страна — лимиты мощности и разрешённые '
                'каналы могут быть неверными.',
            fixEn: 'Set the correct country on the interface.',
            fixRu: 'Укажи правильную страну на интерфейсе.',
            where: name));
      }

      final basic = '${w['basic-rates-a/g'] ?? ''},${w['basic-rates-b'] ?? ''}';
      if (RegExp(r'(^|,)(1Mbps|2Mbps|5\.5Mbps|11Mbps)').hasMatch(basic)) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'Legacy basic rates enabled',
            titleRu: 'Включены legacy-рейты',
            detailEn:
                '$name allows 1/2/5.5/11 Mbps as basic rates. Old slow rates '
                'drag down the whole cell.',
            detailRu:
                '$name разрешает 1/2/5.5/11 Мбит/с как базовые. Старые медленные '
                'рейты тормозят всю соту.',
            fixEn: 'Raise the basic rate (e.g. drop rates below 6–12 Mbps).',
            fixRu: 'Подними базовый рейт (убери скорости ниже 6–12 Мбит/с).',
            where: name));
      }

      final tp = int.tryParse(w['tx-power'] ?? '');
      if (tp != null && tp >= 24) {
        out.add(Finding(AuditSeverity.warn,
            titleEn: 'Very high TX power',
            titleRu: 'Очень высокая мощность',
            detailEn:
                '$name TX power is $tp dBm. Too high power makes the AP shout '
                'while clients can\'t answer as loud (asymmetry) and raises '
                'co-channel noise.',
            detailRu:
                'Мощность $name — $tp dBm. Слишком высокая мощность: точка '
                '«кричит», а клиенты не отвечают так же громко (асимметрия), '
                'плюс растёт шум на канале.',
            fixEn: 'Lower TX power so both directions are balanced.',
            fixRu: 'Снизь мощность, чтобы обе стороны были сбалансированы.',
            where: name));
      }

      _checkWirelessProfile(byName[w['security-profile']], name, out);
    }
  }

  void _checkWirelessProfile(
      Map<String, String>? prof, String where, List<Finding> out) {
    if (prof == null) return;
    final mode = prof['mode'] ?? '';
    final auth = prof['authentication-types'] ?? '';
    final ciphers =
        '${prof['unicast-ciphers'] ?? ''},${prof['group-ciphers'] ?? ''}';

    if (mode == 'none') {
      out.add(_openFinding(where));
    } else if (mode == 'static-keys') {
      out.add(_wepFinding(where));
    } else if (auth.contains('wpa-psk') && !auth.contains('wpa2')) {
      out.add(_wpa1Finding(where));
    } else if (ciphers.contains('tkip')) {
      out.add(_tkipFinding(where));
    } else if (auth.contains('wpa2') || auth.contains('wpa3')) {
      out.add(_secOkFinding(where));
    }
  }

  // --- CAPsMAN --------------------------------------------------------------

  Future<void> _capsman(MikrotikService svc, List<Finding> out) async {
    final configs = await _safe(svc, '/caps-man/configuration');
    if (configs.isEmpty) return;
    final secs = await _safe(svc, '/caps-man/security');
    final byName = {for (final s in secs) s['name']: s};

    for (final c in configs) {
      final ssid = c['ssid'] ?? c['name'] ?? '?';
      final secName = c['security'] ?? '';
      if (secName.isEmpty) {
        out.add(_openFinding(ssid));
        continue;
      }
      final sec = byName[secName];
      if (sec == null) continue;
      final auth = sec['authentication-types'] ?? '';
      final enc = '${sec['encryption'] ?? ''},${sec['group-encryption'] ?? ''}';
      if (auth.isEmpty) {
        out.add(_openFinding(ssid));
      } else if (auth.contains('wpa-psk') && !auth.contains('wpa2')) {
        out.add(_wpa1Finding(ssid));
      } else if (enc.contains('tkip')) {
        out.add(_tkipFinding(ssid));
      } else if (auth.contains('wpa2') || auth.contains('wpa3')) {
        out.add(_secOkFinding(ssid));
      }
    }
  }

  // --- shared security findings --------------------------------------------

  Finding _openFinding(String where) => Finding(AuditSeverity.critical,
      titleEn: 'Open network',
      titleRu: 'Открытая сеть',
      detailEn:
          '"$where" has no encryption — anyone nearby can join and sniff.',
      detailRu:
          '«$where» без шифрования — любой рядом может подключиться и слушать.',
      fixEn: 'Add WPA2 (or WPA2/WPA3) with a strong passphrase.',
      fixRu: 'Включи WPA2 (или WPA2/WPA3) с надёжным паролем.',
      where: where);

  Finding _wepFinding(String where) => Finding(AuditSeverity.critical,
      titleEn: 'WEP / static keys',
      titleRu: 'WEP / статические ключи',
      detailEn: '"$where" uses WEP-style static keys — broken, cracked in '
          'minutes.',
      detailRu:
          '«$where» использует WEP-подобные статические ключи — взламывается '
          'за минуты.',
      fixEn: 'Switch to WPA2/WPA3.',
      fixRu: 'Перейди на WPA2/WPA3.',
      where: where);

  Finding _wpa1Finding(String where) => Finding(AuditSeverity.warn,
      titleEn: 'WPA1 only',
      titleRu: 'Только WPA1',
      detailEn: '"$where" allows WPA1 — deprecated and weak. Use WPA2+.',
      detailRu: '«$where» разрешает WPA1 — устарел и слаб. Нужен WPA2+.',
      fixEn: 'Require WPA2-PSK (drop WPA1).',
      fixRu: 'Оставь только WPA2-PSK (убери WPA1).',
      where: where);

  Finding _tkipFinding(String where) => Finding(AuditSeverity.warn,
      titleEn: 'TKIP encryption',
      titleRu: 'Шифрование TKIP',
      detailEn: '"$where" allows TKIP — insecure and caps the link to 54 Mbps.',
      detailRu:
          '«$where» разрешает TKIP — небезопасно и режет линк до 54 Мбит/с.',
      fixEn: 'Use AES-CCM (CCMP) only.',
      fixRu: 'Оставь только AES-CCM (CCMP).',
      where: where);

  Finding _secOkFinding(String where) => Finding(AuditSeverity.ok,
      titleEn: 'WPA2/WPA3 + AES',
      titleRu: 'WPA2/WPA3 + AES',
      detailEn: '"$where" uses modern encryption. Good.',
      detailRu: '«$where» использует современное шифрование. Хорошо.',
      where: where);
}
