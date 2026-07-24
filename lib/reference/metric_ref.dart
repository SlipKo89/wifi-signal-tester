import 'package:flutter/material.dart';

const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);
const _red = Color(0xFFF85149);

/// One good/ok/bad band for a metric.
class RefBand {
  final Color color;
  final String rangeEn;
  final String rangeRu;
  final String descEn;
  final String descRu;
  const RefBand(
      this.color, this.rangeEn, this.rangeRu, this.descEn, this.descRu);
}

/// Reference entry for a metric — shared by the tap-help sheet and the
/// Reference screen.
class MetricRef {
  final String key;
  final String titleEn;
  final String titleRu;
  final String whatEn;
  final String whatRu;
  final List<RefBand> bands;
  final String? tipEn;
  final String? tipRu;

  const MetricRef({
    required this.key,
    required this.titleEn,
    required this.titleRu,
    required this.whatEn,
    required this.whatRu,
    this.bands = const [],
    this.tipEn,
    this.tipRu,
  });
}

const Map<String, MetricRef> kMetricRefs = {
  'signal': MetricRef(
    key: 'signal',
    titleEn: 'Signal (dBm)',
    titleRu: 'Сигнал (dBm)',
    whatEn: 'How strongly one side receives the other, in dBm. It is negative — '
        'closer to 0 is stronger (−45 is great, −80 is weak).',
    whatRu: 'Насколько сильно одна сторона слышит другую, в dBm. Значение '
        'отрицательное — чем ближе к 0, тем сильнее (−45 отлично, −80 слабо).',
    bands: [
      RefBand(_green, '≥ −60', '≥ −60', 'Excellent — full rates.',
          'Отлично — максимальные скорости.'),
      RefBand(_amber, '−60…−72', '−60…−72', 'Usable, rates may drop.',
          'Рабочий, скорость может падать.'),
      RefBand(_red, '< −72', '< −72', 'Weak — retransmits, low speed.',
          'Слабый — ретрансмиты, низкая скорость.'),
    ],
    tipEn: 'Look at both sides and SNR, not just this number.',
    tipRu: 'Смотри обе стороны и SNR, а не только эту цифру.',
  ),
  'snr': MetricRef(
    key: 'snr',
    titleEn: 'SNR (dB)',
    titleRu: 'SNR (dB)',
    whatEn: 'Signal above the noise floor, in dB. Higher is cleaner. For real '
        'speed SNR matters more than the raw dBm.',
    whatRu: 'Насколько сигнал выше уровня шума, в dB. Больше — чище. Для '
        'реальной скорости SNR важнее «сырого» dBm.',
    bands: [
      RefBand(_green, '≥ 25', '≥ 25', 'Great — high data rates.',
          'Отлично — высокие скорости.'),
      RefBand(_amber, '15…25', '15…25', 'OK — mid rates.',
          'Норм — средние скорости.'),
      RefBand(_red, '< 15', '< 15', 'Noisy — speed suffers.',
          'Шумно — скорость страдает.'),
    ],
    tipEn: '"est." means we estimated it from the radio noise floor.',
    tipRu: '«est.» — значит оценили по уровню шума радио.',
  ),
  'ccq': MetricRef(
    key: 'ccq',
    titleEn: 'CCQ (%)',
    titleRu: 'CCQ (%)',
    whatEn: 'Client Connection Quality, 0–100%. MikroTik\'s estimate of how '
        'efficiently frames get through (fewer retransmits = higher). Legacy '
        'wireless only — CAPsMAN does not report it.',
    whatRu: 'Client Connection Quality, 0–100%. Оценка MikroTik, насколько '
        'эффективно проходят кадры (меньше ретрансмитов = выше). Только legacy '
        'wireless — CAPsMAN его не отдаёт.',
    bands: [
      RefBand(_green, '≥ 80', '≥ 80', 'Clean link.', 'Чистый линк.'),
      RefBand(_amber, '50…80', '50…80', 'Some retransmits.',
          'Есть ретрансмиты.'),
      RefBand(_red, '< 50', '< 50', 'Many retransmits — poor efficiency.',
          'Много ретрансмитов — низкая эффективность.'),
    ],
  ),
  'rate': MetricRef(
    key: 'rate',
    titleEn: 'TX / RX rate',
    titleRu: 'TX / RX rate',
    whatEn: 'The current negotiated PHY rate (e.g. 866Mbps-80MHz/2S): channel '
        'width, spatial streams and standard. It is the ceiling of the link, '
        'not the real traffic.',
    whatRu: 'Текущая согласованная PHY-скорость (напр. 866Mbps-80MHz/2S): ширина '
        'канала, число потоков и стандарт. Это потолок линка, а не реальный '
        'трафик.',
    tipEn: 'Strong signal but low rate → interference or a legacy/1-stream '
        'client.',
    tipRu: 'Сильный сигнал, но низкий rate → помехи или старый/1-поточный '
        'клиент.',
  ),
  'throughput': MetricRef(
    key: 'throughput',
    titleEn: 'Down / Up (live)',
    titleRu: 'Загрузка / Отдача (live)',
    whatEn: 'Actual bytes moving right now, from the AP byte counters. This is '
        'real usage, not the PHY ceiling — near 0 when idle, which is normal.',
    whatRu: 'Реальные байты прямо сейчас, из счётчиков AP. Это фактическое '
        'использование, а не потолок — около 0 в простое, и это нормально.',
  ),
  'ping': MetricRef(
    key: 'ping',
    titleEn: 'Ping (ms)',
    titleRu: 'Пинг (мс)',
    whatEn: 'Round-trip time to your gateway over Wi-Fi. Lower is snappier. '
        'Spikes or packet loss while the signal looks strong point to '
        'interference or a busy/overloaded AP.',
    whatRu: 'Время туда-обратно до шлюза по Wi-Fi. Меньше — отзывчивее. Скачки '
        'или потери при «сильном» сигнале намекают на помехи или '
        'перегруженную точку.',
    bands: [
      RefBand(_green, '< 20', '< 20', 'Snappy.', 'Шустро.'),
      RefBand(_amber, '20–80', '20–80', 'OK for most use.',
          'Норм для большинства задач.'),
      RefBand(_red, '> 80 / loss', '> 80 / потери', 'Laggy — check the link.',
          'Тормозит — проверь линк.'),
    ],
  ),
  'delta': MetricRef(
    key: 'delta',
    titleEn: 'Δ AP−phone (asymmetry)',
    titleRu: 'Δ AP−phone (асимметрия)',
    whatEn: 'Difference between the two directions. Negative = the AP hears you '
        'worse than you hear it (weak uplink). Tap the Δ badge for advice.',
    whatRu: 'Разница между направлениями. Минус = точка слышит тебя хуже, чем ты '
        'её (слабый аплинк). Тапни по плашке Δ для советов.',
    bands: [
      RefBand(_green, '|Δ| ≤ 6', '|Δ| ≤ 6', 'Balanced — ideal.',
          'Симметрично — идеал.'),
      RefBand(_amber, '≤ 12', '≤ 12', 'Noticeable imbalance.',
          'Заметный перекос.'),
      RefBand(_red, '> 12', '> 12', 'Strong imbalance — act on it.',
          'Сильный перекос — стоит исправить.'),
    ],
  ),
  'band': MetricRef(
    key: 'band',
    titleEn: 'Band / Frequency',
    titleRu: 'Диапазон / Частота',
    whatEn: '2.4 GHz reaches further but is crowded and slower; 5 GHz is faster '
        'with more clean channels; 6 GHz is the newest and cleanest. Frequency '
        '(MHz) is the exact channel.',
    whatRu: '2.4 ГГц бьёт дальше, но забит и медленнее; 5 ГГц быстрее и чище; '
        '6 ГГц — самый новый и чистый. Частота (МГц) — конкретный канал.',
  ),
  'uptime': MetricRef(
    key: 'uptime',
    titleEn: 'Uptime',
    titleRu: 'Аптайм',
    whatEn: 'How long the client has stayed associated to this AP. Frequent '
        'resets mean roaming or an unstable link.',
    whatRu: 'Как долго клиент держится на этой точке. Частые сбросы — роуминг '
        'или нестабильный линк.',
  ),
};
