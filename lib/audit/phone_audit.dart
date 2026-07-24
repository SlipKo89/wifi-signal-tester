import '../models/phone_signal.dart';
import 'audit.dart';

/// Audits the connection from the phone's own point of view — no router needed.
class PhoneAudit {
  List<Finding> run(PhoneSignal? p) {
    final out = <Finding>[];
    if (p == null ||
        (p.ssid == null && p.ipAddress == null && p.rssiDbm == null)) {
      out.add(const Finding(AuditSeverity.info,
          titleEn: 'Not connected to Wi-Fi',
          titleRu: 'Нет подключения к Wi-Fi',
          detailEn: 'Connect to a Wi-Fi network to audit it from the phone.',
          detailRu: 'Подключись к сети Wi-Fi, чтобы проверить её с телефона.'));
      return out;
    }

    // Summary line.
    final bits = <String>[
      if (p.ssid != null) p.ssid!,
      p.band,
      if (p.wifiStandard != null) p.wifiStandard!,
      if (p.security != null) p.security!,
    ];
    out.add(Finding(AuditSeverity.info,
        titleEn: 'This connection',
        titleRu: 'Это подключение',
        detailEn: bits.join(' · '),
        detailRu: bits.join(' · ')));

    _signal(p, out);
    _band(p, out);
    _channel(p, out);
    _security(p, out);
    _standard(p, out);
    _rate(p, out);

    out.sort((a, b) => a.sev.index.compareTo(b.sev.index));
    return out;
  }

  void _signal(PhoneSignal p, List<Finding> out) {
    final r = p.rssiDbm;
    if (r == null) return;
    if (r >= -60) {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'Strong signal ($r dBm)',
          titleRu: 'Сильный сигнал ($r dBm)',
          detailEn: 'The phone hears the AP well — full rates are possible.',
          detailRu: 'Телефон хорошо слышит точку — доступны максимальные '
              'скорости.'));
    } else if (r >= -72) {
      out.add(Finding(AuditSeverity.info,
          titleEn: 'Usable signal ($r dBm)',
          titleRu: 'Рабочий сигнал ($r dBm)',
          detailEn: 'OK, but rates may drop. Closer or a nearer AP helps.',
          detailRu: 'Нормально, но скорость может падать. Ближе или ближняя '
              'точка помогут.'));
    } else {
      out.add(Finding(AuditSeverity.warn,
          titleEn: 'Weak signal ($r dBm)',
          titleRu: 'Слабый сигнал ($r dBm)',
          detailEn: 'Expect retransmits and low speed here.',
          detailRu: 'Здесь жди ретрансмиты и низкую скорость.',
          fixEn: 'Move closer to the AP, or add an AP for this area.',
          fixRu: 'Подойди ближе к точке или добавь точку на эту зону.'));
    }
  }

  void _band(PhoneSignal p, List<Finding> out) {
    if (p.frequencyMhz == null) return;
    if (p.band == '2.4 GHz') {
      out.add(const Finding(AuditSeverity.info,
          titleEn: 'On 2.4 GHz',
          titleRu: 'На 2.4 ГГц',
          detailEn: '2.4 GHz reaches further but is crowded and slower. Use '
              '5 GHz when you\'re close enough.',
          detailRu: '2.4 ГГц бьёт дальше, но забит и медленнее. Если ты близко '
              '— переходи на 5 ГГц.'));
    } else {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'On ${p.band}',
          titleRu: 'На ${p.band}',
          detailEn: 'Faster, cleaner band — good.',
          detailRu: 'Быстрый и чистый диапазон — хорошо.'));
    }
  }

  void _channel(PhoneSignal p, List<Finding> out) {
    final ch = p.channel24;
    if (ch == null) return;
    if ([1, 6, 11].contains(ch)) {
      out.add(Finding(AuditSeverity.ok,
          titleEn: '2.4 GHz channel $ch',
          titleRu: 'Канал 2.4 ГГц: $ch',
          detailEn: 'A non-overlapping channel (1/6/11) — correct.',
          detailRu: 'Непересекающийся канал (1/6/11) — правильно.'));
    } else {
      out.add(Finding(AuditSeverity.info,
          titleEn: '2.4 GHz channel $ch overlaps',
          titleRu: 'Канал 2.4 ГГц $ch пересекается',
          detailEn: 'The AP is on channel $ch. On 2.4 GHz only 1, 6 and 11 '
              'don\'t overlap.',
          detailRu: 'Точка на канале $ch. В 2.4 ГГц не пересекаются только 1, 6 '
              'и 11.'));
    }
  }

  void _security(PhoneSignal p, List<Finding> out) {
    final s = p.security;
    if (s == null) return;
    if (s == 'Open') {
      out.add(const Finding(AuditSeverity.critical,
          titleEn: 'Open network',
          titleRu: 'Открытая сеть',
          detailEn: 'No encryption — traffic can be sniffed by anyone nearby.',
          detailRu: 'Без шифрования — трафик может слушать любой рядом.',
          fixEn: 'Prefer a WPA2/WPA3 network.',
          fixRu: 'Лучше подключаться к сети с WPA2/WPA3.'));
    } else if (s == 'WEP') {
      out.add(const Finding(AuditSeverity.critical,
          titleEn: 'WEP security',
          titleRu: 'Защита WEP',
          detailEn: 'WEP is broken — cracked in minutes.',
          detailRu: 'WEP взломан — вскрывается за минуты.'));
    } else {
      out.add(Finding(AuditSeverity.ok,
          titleEn: 'Security: $s',
          titleRu: 'Защита: $s',
          detailEn: 'Modern encryption — good.',
          detailRu: 'Современное шифрование — хорошо.'));
    }
  }

  void _standard(PhoneSignal p, List<Finding> out) {
    final s = p.wifiStandard;
    if (s == null) return;
    if (s.contains('legacy')) {
      out.add(const Finding(AuditSeverity.warn,
          titleEn: 'Legacy Wi-Fi (a/b/g)',
          titleRu: 'Старый Wi-Fi (a/b/g)',
          detailEn: 'The link fell back to an old, slow standard.',
          detailRu: 'Линк ушёл на старый медленный стандарт.',
          fixEn: 'Check the AP allows 802.11n/ac/ax and drops legacy rates.',
          fixRu: 'Проверь, что точка разрешает 802.11n/ac/ax и убрала '
              'legacy-рейты.'));
    } else {
      out.add(Finding(AuditSeverity.ok,
          titleEn: s,
          titleRu: s,
          detailEn: 'A modern Wi-Fi generation.',
          detailRu: 'Современное поколение Wi-Fi.'));
    }
  }

  void _rate(PhoneSignal p, List<Finding> out) {
    final link = p.linkSpeedMbps;
    if (link == null) return;
    final strong = (p.rssiDbm ?? -100) >= -60;
    if (strong && link < 100) {
      out.add(Finding(AuditSeverity.info,
          titleEn: 'Low link rate ($link Mbps) for a strong signal',
          titleRu: 'Низкий линк ($link Мбит/с) при сильном сигнале',
          detailEn: 'Strong signal but a low negotiated rate suggests '
              'interference or a narrow channel.',
          detailRu: 'Сильный сигнал, но низкая скорость линка — намёк на помехи '
              'или узкий канал.'));
    } else {
      out.add(Finding(AuditSeverity.info,
          titleEn: 'Link rate: $link Mbps',
          titleRu: 'Скорость линка: $link Мбит/с',
          detailEn: 'Negotiated PHY rate (the ceiling, not real traffic).',
          detailRu: 'Согласованная PHY-скорость (потолок, не реальный трафик).'));
    }
  }
}
