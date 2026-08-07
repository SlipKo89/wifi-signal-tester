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
  'purpose': MetricRef(
    key: 'purpose',
    titleEn: 'What this app is for',
    titleRu: 'Зачем это приложение',
    whatEn: 'It tests Wi-Fi from both sides on MikroTik: how your device hears '
        'the access point AND how the AP hears your device — the reverse '
        'direction normal analyzers can\'t show. It also runs a read-only '
        'Wi-Fi and system audit of your MikroTik, checks other devices on the '
        'network, and measures latency. A separate LTE tool diagnoses '
        'RSRP/RSRQ/SINR on MikroTik cellular routers. Built for installers and '
        'anyone tuning MikroTik Wi-Fi or LTE. Read-only — it never changes your router.',
    whatRu: 'Тестирует Wi-Fi с двух сторон на MikroTik: как твоё устройство '
        'слышит точку и как точка слышит устройство — обратную сторону обычные '
        'анализаторы не показывают. Ещё делает read-only аудит Wi-Fi и системы '
        'MikroTik, смотрит другие устройства сети и меряет задержку. Для '
        'отдельной диагностики LTE читает RSRP/RSRQ/SINR с сотового MikroTik. '
        'Для монтажников и всех, кто настраивает Wi-Fi или LTE на MikroTik. '
        'Только чтение — настройки роутера не меняются.',
    tipEn: 'Tap any number in the app for a plain-language explanation like '
        'these.',
    tipRu: 'Тапни по любой цифре в приложении — получишь такое же понятное '
        'объяснение.',
  ),
  'signal': MetricRef(
    key: 'signal',
    titleEn: 'Signal (dBm)',
    titleRu: 'Сигнал (dBm)',
    whatEn:
        'How strongly one side receives the other, in dBm. It is negative — '
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
      RefBand(
          _amber, '50…80', '50…80', 'Some retransmits.', 'Есть ретрансмиты.'),
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
    whatRu:
        'Текущая согласованная PHY-скорость (напр. 866Mbps-80MHz/2S): ширина '
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
    whatEn:
        'Difference between the two directions. Negative = the AP hears you '
        'worse than you hear it (weak uplink). Tap the Δ badge for advice.',
    whatRu:
        'Разница между направлениями. Минус = точка слышит тебя хуже, чем ты '
        'её (слабый аплинк). Тапни по плашке Δ для советов.',
    bands: [
      RefBand(_green, '|Δ| ≤ 6', '|Δ| ≤ 6', 'Balanced — ideal.',
          'Симметрично — идеал.'),
      RefBand(
          _amber, '≤ 12', '≤ 12', 'Noticeable imbalance.', 'Заметный перекос.'),
      RefBand(_red, '> 12', '> 12', 'Strong imbalance — act on it.',
          'Сильный перекос — стоит исправить.'),
    ],
  ),
  'band': MetricRef(
    key: 'band',
    titleEn: 'Band / Frequency',
    titleRu: 'Диапазон / Частота',
    whatEn:
        '2.4 GHz reaches further but is crowded and slower; 5 GHz is faster '
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
  'lte_quality': MetricRef(
    key: 'lte_quality',
    titleEn: 'LTE Quality Score (0–100)',
    titleRu: 'Оценка качества LTE (0–100)',
    whatEn: 'A simplified radio-link score where higher is better. It combines '
        'RSRP, RSRQ, SINR and optional CQI, adapts their weights when coverage '
        'is weak, and penalises unstable readings. It is smoothed over recent '
        'samples and starts a fresh window after a band/cell handoff.',
    whatRu:
        'Упрощённая оценка радиоканала: чем выше, тем лучше. Она объединяет '
        'RSRP, RSRQ, SINR и при наличии CQI, меняет их вес при слабом покрытии '
        'и штрафует нестабильные значения. Оценка сглаживается по последним '
        'замерам и начинает новое окно после смены диапазона/соты.',
    bands: [
      RefBand(_green, '80…100', '80…100', 'Excellent radio conditions.',
          'Отличная радиообстановка.'),
      RefBand(
          _green, '60…79', '60…79', 'Good radio link.', 'Хороший радиоканал.'),
      RefBand(_amber, '40…59', '40…59', 'Usable, but needs attention.',
          'Работает, но требует внимания.'),
      RefBand(_red, '0…39', '0…39', 'Poor radio link.', 'Плохой радиоканал.'),
    ],
    tipEn: 'This is not a speed test. Sector load, routing and provider '
        'congestion can reduce Internet speed even with a high score. Use the '
        'score to compare antenna positions, then verify speed separately.',
    tipRu: 'Это не тест скорости. Нагрузка сектора, маршрутизация и сеть '
        'оператора могут снижать скорость даже при высокой оценке. Используй '
        'оценку для сравнения положений антенны, затем проверь скорость отдельно.',
  ),
  'lte_rsrp': MetricRef(
    key: 'lte_rsrp',
    titleEn: 'LTE RSRP (dBm)',
    titleRu: 'LTE RSRP (dBm)',
    whatEn: 'Reference Signal Received Power: the power of LTE reference '
        'signals received by the modem. It is the main coverage/antenna-level '
        'number. Closer to zero is stronger.',
    whatRu: 'Reference Signal Received Power — мощность опорных сигналов LTE, '
        'принятых модемом. Главная цифра для оценки покрытия и уровня на '
        'антенне. Чем ближе к нулю, тем сильнее.',
    bands: [
      RefBand(_green, '≥ −90', '≥ −90', 'Good to excellent power.',
          'Хорошая или отличная мощность.'),
      RefBand(_amber, '−90…−100', '−90…−100', 'Usable, with less margin.',
          'Рабочий уровень, но запас меньше.'),
      RefBand(_red, '< −100', '< −100', 'Weak; below −110 is very poor.',
          'Слабо; ниже −110 — очень плохо.'),
    ],
    tipEn: 'Strong RSRP does not guarantee speed: always check RSRQ and SINR.',
    tipRu: 'Сильный RSRP не гарантирует скорость: всегда смотри RSRQ и SINR.',
  ),
  'lte_rsrq': MetricRef(
    key: 'lte_rsrq',
    titleEn: 'LTE RSRQ (dB)',
    titleRu: 'LTE RSRQ (dB)',
    whatEn: 'Reference Signal Received Quality. It combines useful LTE signal '
        'with total received energy, so it reacts to interference and sector '
        'load. Closer to zero is better.',
    whatRu: 'Reference Signal Received Quality — качество опорного сигнала с '
        'учётом всей принятой энергии. Реагирует на помехи и загрузку сектора. '
        'Чем ближе к нулю, тем лучше.',
    bands: [
      RefBand(
          _green, '≥ −10', '≥ −10', 'Excellent quality.', 'Отличное качество.'),
      RefBand(_amber, '−10…−15', '−10…−15', 'Good/usable.',
          'Хорошо/рабочий уровень.'),
      RefBand(_red, '< −15', '< −15', 'Poor quality or busy/noisy sector.',
          'Плохое качество или загруженный/шумный сектор.'),
    ],
  ),
  'lte_sinr': MetricRef(
    key: 'lte_sinr',
    titleEn: 'LTE SINR (dB)',
    titleRu: 'LTE SINR (dB)',
    whatEn: 'Useful signal versus interference plus noise. SINR strongly '
        'affects modulation and speed. Higher is better; a negative value '
        'means interference/noise is stronger than the useful signal.',
    whatRu: 'Полезный сигнал относительно помех и шума. SINR сильно влияет на '
        'модуляцию и скорость. Чем выше, тем лучше; отрицательное значение '
        'означает, что помехи/шум сильнее полезного сигнала.',
    bands: [
      RefBand(_green, '≥ 13', '≥ 13', 'Good; ≥20 is excellent.',
          'Хорошо; ≥20 — отлично.'),
      RefBand(_amber, '0…13', '0…13', 'Usable, speed is limited.',
          'Работает, но скорость ограничена.'),
      RefBand(_red, '< 0', '< 0', 'Poor radio conditions.',
          'Плохая радиообстановка.'),
    ],
    tipEn: 'When RSRP is good but SINR is poor, adding antenna gain alone is '
        'unlikely to solve the problem.',
    tipRu: 'Если RSRP хороший, а SINR плохой, одно усиление антенны вряд ли '
        'решит проблему.',
  ),
  'lte_rssi': MetricRef(
    key: 'lte_rssi',
    titleEn: 'LTE RSSI (dBm)',
    titleRu: 'LTE RSSI (dBm)',
    whatEn: 'Total received wideband power: useful LTE signal, other cells, '
        'interference and noise together. It is secondary to RSRP/RSRQ/SINR.',
    whatRu: 'Полная широкополосная принятая мощность: полезный LTE-сигнал, '
        'другие соты, помехи и шум вместе. Вторична по отношению к '
        'RSRP/RSRQ/SINR.',
    bands: [
      RefBand(_green, '≥ −75', '≥ −75', 'Strong total power.',
          'Высокая общая мощность.'),
      RefBand(_amber, '−75…−85', '−75…−85', 'Usable.', 'Рабочий уровень.'),
      RefBand(_red, '< −85', '< −85', 'Weak total power.',
          'Низкая общая мощность.'),
    ],
    tipEn: 'A strong RSSI can include strong interference, so it is never the '
        'main LTE quality verdict.',
    tipRu: 'Сильный RSSI может включать сильные помехи, поэтому это не главная '
        'оценка качества LTE.',
  ),
  'lte_cqi': MetricRef(
    key: 'lte_cqi',
    titleEn: 'LTE CQI',
    titleRu: 'LTE CQI',
    whatEn: 'Channel Quality Indicator, normally 0–15. The modem reports what '
        'modulation/coding the current downlink can sustain. Higher usually '
        'allows more throughput.',
    whatRu: 'Channel Quality Indicator, обычно 0–15. Модем сообщает, какую '
        'модуляцию и кодирование выдерживает текущий downlink. Больше обычно '
        'означает выше возможную скорость.',
    bands: [
      RefBand(_green, '≥ 10', '≥ 10', 'Good; ≥13 is excellent.',
          'Хорошо; ≥13 — отлично.'),
      RefBand(_amber, '7…9', '7…9', 'Moderate.', 'Средне.'),
      RefBand(_red, '< 7', '< 7', 'Low modulation / limited speed.',
          'Низкая модуляция / ограниченная скорость.'),
    ],
  ),
  'scan_throttle': MetricRef(
    key: 'scan_throttle',
    titleEn: 'Wi-Fi scan throttling (Android)',
    titleRu: 'Тротлинг сканирования Wi-Fi (Android)',
    whatEn: 'Since Android 9, the system limits how often apps can scan for '
        'nearby Wi-Fi (about 4 scans per 2 minutes), so signal/BSSID updates '
        'can lag.',
    whatRu: 'С Android 9 система ограничивает, как часто приложения сканируют '
        'Wi-Fi вокруг (примерно 4 скана за 2 минуты), поэтому обновления '
        'сигнала/BSSID могут запаздывать.',
    tipEn: 'To scan faster: enable Developer options (tap Build number 7×), '
        'then turn off "Wi-Fi scan throttling". It resets on reboot on some '
        'phones.',
    tipRu: 'Чтобы сканить чаще: включи «Для разработчиков» (тапни 7× по «Номер '
        'сборки»), затем выключи «Ограничение поиска сетей Wi-Fi». На части '
        'телефонов сбрасывается после перезагрузки.',
  ),
};
