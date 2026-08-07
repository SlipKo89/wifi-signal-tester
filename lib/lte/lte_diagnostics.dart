import 'lte_signal.dart';

enum LteQuality { excellent, good, fair, poor, unknown }

class LteDiagnosticReport {
  final LteQuality quality;
  final String titleEn;
  final String titleRu;
  final String summaryEn;
  final String summaryRu;
  final List<String> factsEn;
  final List<String> factsRu;
  final List<String> adviceEn;
  final List<String> adviceRu;

  const LteDiagnosticReport({
    required this.quality,
    required this.titleEn,
    required this.titleRu,
    required this.summaryEn,
    required this.summaryRu,
    this.factsEn = const [],
    this.factsRu = const [],
    this.adviceEn = const [],
    this.adviceRu = const [],
  });
}

class LteDiagnostics {
  static LteQuality rsrpQuality(double? value) {
    if (value == null) return LteQuality.unknown;
    if (value >= -80) return LteQuality.excellent;
    if (value >= -90) return LteQuality.good;
    if (value >= -100) return LteQuality.fair;
    return LteQuality.poor;
  }

  static LteQuality rsrqQuality(double? value) {
    if (value == null) return LteQuality.unknown;
    if (value >= -10) return LteQuality.excellent;
    if (value >= -15) return LteQuality.good;
    if (value >= -20) return LteQuality.fair;
    return LteQuality.poor;
  }

  static LteQuality sinrQuality(double? value) {
    if (value == null) return LteQuality.unknown;
    if (value >= 20) return LteQuality.excellent;
    if (value >= 13) return LteQuality.good;
    if (value >= 0) return LteQuality.fair;
    return LteQuality.poor;
  }

  static LteQuality rssiQuality(double? value) {
    if (value == null) return LteQuality.unknown;
    if (value >= -65) return LteQuality.excellent;
    if (value >= -75) return LteQuality.good;
    if (value >= -85) return LteQuality.fair;
    return LteQuality.poor;
  }

  static LteQuality cqiQuality(int? value) {
    if (value == null) return LteQuality.unknown;
    if (value >= 13) return LteQuality.excellent;
    if (value >= 10) return LteQuality.good;
    if (value >= 7) return LteQuality.fair;
    return LteQuality.poor;
  }

  static LteDiagnosticReport evaluate(
    LteSignal? signal, {
    List<LteSignal> history = const [],
  }) {
    if (signal == null) {
      return const LteDiagnosticReport(
        quality: LteQuality.unknown,
        titleEn: 'Waiting for LTE data',
        titleRu: 'Ждём данные LTE',
        summaryEn: 'Connect to a MikroTik with an LTE interface.',
        summaryRu: 'Подключись к MikroTik с LTE-интерфейсом.',
      );
    }
    if (!signal.registered) {
      return const LteDiagnosticReport(
        quality: LteQuality.poor,
        titleEn: 'Modem is not registered',
        titleRu: 'Модем не зарегистрирован в сети',
        summaryEn: 'There is no usable radio link to grade yet.',
        summaryRu: 'Оценивать радиоканал пока нельзя.',
        adviceEn: [
          'Check SIM state, APN and operator coverage in RouterOS.',
          'Check the antenna connectors and whether the antenna supports the operator bands.',
        ],
        adviceRu: [
          'Проверь состояние SIM, APN и покрытие оператора в RouterOS.',
          'Проверь антенные разъёмы и поддержку диапазонов оператора антенной.',
        ],
      );
    }
    if (!signal.hasRadioMetrics) {
      return const LteDiagnosticReport(
        quality: LteQuality.unknown,
        titleEn: 'Registered, but radio metrics are unavailable',
        titleRu: 'Регистрация есть, но радиометрики недоступны',
        summaryEn:
            'This modem/RouterOS combination did not return RSRP, RSRQ or SINR.',
        summaryRu:
            'Эта связка модема и RouterOS не вернула RSRP, RSRQ или SINR.',
        adviceEn: [
          'Wait for registration to settle and check the modem firmware.'
        ],
        adviceRu: ['Подожди завершения регистрации и проверь прошивку модема.'],
      );
    }

    final weak = signal.rsrp != null && signal.rsrp! < -100;
    final veryWeak = signal.rsrp != null && signal.rsrp! < -110;
    final noisy = (signal.sinr != null && signal.sinr! < 5) ||
        (signal.rsrq != null && signal.rsrq! < -15);
    final criticalNoise = (signal.sinr != null && signal.sinr! < 0) ||
        (signal.rsrq != null && signal.rsrq! < -20);
    final clean = (signal.sinr == null || signal.sinr! >= 10) &&
        (signal.rsrq == null || signal.rsrq! >= -15);
    final strongEnough = signal.rsrp != null && signal.rsrp! >= -95;
    final lowCqi = signal.cqi != null && signal.cqi! < 7;
    final unstable = _spread(history, (s) => s.rsrp) >= 8 ||
        _spread(history, (s) => s.sinr) >= 10;

    final factsEn = <String>[];
    final factsRu = <String>[];
    if (weak) {
      factsEn.add('RSRP shows weak received power at the modem.');
      factsRu.add('RSRP показывает слабую мощность сигнала на модеме.');
    }
    if (noisy) {
      factsEn.add('RSRQ/SINR show interference, sector load or multipath.');
      factsRu.add(
          'RSRQ/SINR указывают на помехи, нагрузку сектора или отражения.');
    }
    if (lowCqi) {
      factsEn.add('Low CQI limits the modulation and therefore speed.');
      factsRu.add('Низкий CQI ограничивает модуляцию и итоговую скорость.');
    }
    if (unstable) {
      factsEn.add('The recent samples fluctuate noticeably.');
      factsRu.add('Последние измерения заметно скачут.');
    }

    if (weak && clean) {
      return LteDiagnosticReport(
        quality: veryWeak ? LteQuality.poor : LteQuality.fair,
        titleEn: 'Weak but fairly clean LTE signal',
        titleRu: 'LTE-сигнал слабый, но достаточно чистый',
        summaryEn:
            'The sector is usable, but received power is the main limitation.',
        summaryRu:
            'Сектор пригоден для работы, но ограничивает именно мощность сигнала.',
        factsEn: factsEn,
        factsRu: factsRu,
        adviceEn: [
          'Fine-tune antenna direction and height while watching RSRP and SINR together.',
          'Inspect cable, adapters and connectors; every dB of loss matters at LTE frequencies.',
          'Compare available bands/cells rather than judging by RSSI alone.',
        ],
        adviceRu: [
          'Точно настрой направление и высоту антенны, одновременно наблюдая RSRP и SINR.',
          'Проверь кабель, переходники и разъёмы: на частотах LTE важен каждый dB потерь.',
          'Сравни доступные диапазоны/соты, не ориентируйся только на RSSI.',
        ],
      );
    }

    if (strongEnough && noisy) {
      return LteDiagnosticReport(
        quality: criticalNoise ? LteQuality.poor : LteQuality.fair,
        titleEn: criticalNoise
            ? 'LTE radio quality is poor'
            : 'Signal is strong enough, radio quality needs attention',
        titleRu: criticalNoise
            ? 'Качество радиоканала LTE плохое'
            : 'Мощности хватает, но качество эфира требует внимания',
        summaryEn: criticalNoise
            ? 'Interference/noise is stronger than the useful margin; more antenna gain alone is unlikely to help.'
            : 'Interference or sector load is more likely than insufficient signal power.',
        summaryRu: criticalNoise
            ? 'Помехи/шум съедают полезный запас; одно усиление антенны вряд ли поможет.'
            : 'Вероятнее помехи или загрузка сектора, а не недостаток мощности сигнала.',
        factsEn: factsEn,
        factsRu: factsRu,
        adviceEn: [
          'Turn the directional antenna in small steps and keep the position with better SINR/RSRQ, not just RSRP.',
          'Compare another LTE band or cell and repeat at busy and quiet hours.',
          'Run a speed test only after the radio metrics stabilise.',
        ],
        adviceRu: [
          'Поворачивай направленную антенну малыми шагами и выбирай положение по SINR/RSRQ, а не только RSRP.',
          'Сравни другой LTE-диапазон или соту и повтори замеры в часы пик и вне их.',
          'Тест скорости имеет смысл запускать после стабилизации радиометрик.',
        ],
      );
    }

    if (weak && noisy) {
      return LteDiagnosticReport(
        quality: LteQuality.poor,
        titleEn: 'LTE signal is weak and noisy',
        titleRu: 'LTE-сигнал слабый и шумный',
        summaryEn: 'Both coverage and radio quality limit the connection.',
        summaryRu: 'Связь одновременно ограничивают покрытие и качество эфира.',
        factsEn: factsEn,
        factsRu: factsRu,
        adviceEn: [
          'Check antenna polarity, connectors, line of sight and mounting height.',
          'Search for a direction/band with better SINR even if RSRP changes only slightly.',
          'Compare another operator or external antenna before changing RouterOS settings.',
        ],
        adviceRu: [
          'Проверь поляризацию антенны, разъёмы, прямую видимость и высоту установки.',
          'Ищи направление/диапазон с лучшим SINR, даже если RSRP меняется мало.',
          'До изменения настроек RouterOS сравни другого оператора или внешнюю антенну.',
        ],
      );
    }

    // The common middle ground: power is poor, but SINR/RSRQ are neither clean
    // enough for the "weak but clean" diagnosis nor bad enough to call the
    // link noisy. This was previously allowed to fall through to a generic
    // "healthy" title while retaining a red quality from RSRP.
    if (weak) {
      final value = _format(signal.rsrp);
      return LteDiagnosticReport(
        quality: veryWeak ? LteQuality.poor : LteQuality.fair,
        titleEn: veryWeak
            ? 'LTE signal is very weak'
            : 'LTE works, but the signal is weak',
        titleRu: veryWeak
            ? 'LTE-сигнал очень слабый'
            : 'LTE работает, но сигнал слабый',
        summaryEn:
            'RSRP $value dBm is the main limitation; radio quality is still usable.',
        summaryRu:
            'RSRP $value dBm ограничивает запас; качество эфира пока рабочее.',
        factsEn: factsEn,
        factsRu: factsRu,
        adviceEn: [
          'Adjust antenna direction and height while watching whether SINR stays stable.',
          'Check cable, adapters and connectors before changing RouterOS settings.',
          'Compare another band/cell and keep the position with the best balance, not merely the strongest RSSI.',
        ],
        adviceRu: [
          'Подстрой направление и высоту антенны, наблюдая, остаётся ли SINR стабильным.',
          'Проверь кабель, переходники и разъёмы до изменения настроек RouterOS.',
          'Сравни другой диапазон/соту и выбирай лучший баланс, а не просто самый сильный RSSI.',
        ],
      );
    }

    if (noisy) {
      return LteDiagnosticReport(
        quality: criticalNoise ? LteQuality.poor : LteQuality.fair,
        titleEn: criticalNoise
            ? 'LTE radio quality is poor'
            : 'LTE radio quality needs attention',
        titleRu: criticalNoise
            ? 'Качество радиоканала LTE плохое'
            : 'Качество радиоканала LTE требует внимания',
        summaryEn:
            'RSRQ/SINR indicate interference, sector load or reflected signal.',
        summaryRu:
            'RSRQ/SINR указывают на помехи, загрузку сектора или отражённый сигнал.',
        factsEn: factsEn,
        factsRu: factsRu,
        adviceEn: [
          'Optimise the antenna position by SINR/RSRQ rather than RSRP alone.',
          'Compare another band/cell and repeat the measurement outside busy hours.',
        ],
        adviceRu: [
          'Настраивай положение антенны по SINR/RSRQ, а не только по RSRP.',
          'Сравни другой диапазон/соту и повтори замер вне часов пик.',
        ],
      );
    }

    final grades = [
      rsrpQuality(signal.rsrp),
      rsrqQuality(signal.rsrq),
      sinrQuality(signal.sinr),
      if (signal.cqi != null) cqiQuality(signal.cqi),
    ].where((g) => g != LteQuality.unknown).toList();
    final quality = grades.isEmpty
        ? LteQuality.unknown
        : grades.reduce((a, b) => a.index > b.index ? a : b);

    final effectiveQuality = unstable ? LteQuality.fair : quality;
    final titleEn = unstable
        ? 'LTE signal is unstable'
        : switch (effectiveQuality) {
            LteQuality.excellent ||
            LteQuality.good =>
              'LTE radio link looks healthy',
            LteQuality.fair => 'LTE works with limitations',
            LteQuality.poor => 'LTE radio link is poor',
            LteQuality.unknown => 'Not enough LTE data',
          };
    final titleRu = unstable
        ? 'LTE-сигнал нестабилен'
        : switch (effectiveQuality) {
            LteQuality.excellent ||
            LteQuality.good =>
              'Радиоканал LTE выглядит нормально',
            LteQuality.fair => 'LTE работает с ограничениями',
            LteQuality.poor => 'Радиоканал LTE плохой',
            LteQuality.unknown => 'Недостаточно данных LTE',
          };
    final summaryEn = unstable
        ? 'Average levels are usable, but recent samples fluctuate.'
        : switch (effectiveQuality) {
            LteQuality.excellent ||
            LteQuality.good =>
              'Received power and radio quality are in a good range.',
            LteQuality.fair =>
              'The connection is usable, but at least one core metric needs attention.',
            LteQuality.poor =>
              'At least one core metric severely limits the connection.',
            LteQuality.unknown =>
              'The modem did not return enough core radio metrics.',
          };
    final summaryRu = unstable
        ? 'Средние уровни рабочие, но последние измерения скачут.'
        : switch (effectiveQuality) {
            LteQuality.excellent ||
            LteQuality.good =>
              'Мощность и качество радиоканала находятся в хорошем диапазоне.',
            LteQuality.fair =>
              'Связь рабочая, но хотя бы одна основная метрика требует внимания.',
            LteQuality.poor =>
              'Хотя бы одна основная метрика серьёзно ограничивает связь.',
            LteQuality.unknown =>
              'Модем не вернул достаточно основных радиометрик.',
          };

    return LteDiagnosticReport(
      quality: effectiveQuality,
      titleEn: titleEn,
      titleRu: titleRu,
      summaryEn: summaryEn,
      summaryRu: summaryRu,
      factsEn: factsEn,
      factsRu: factsRu,
      adviceEn: unstable
          ? const [
              'Secure the antenna/cable and watch whether the serving cell or band changes.'
            ]
          : const [
              'Keep this position as a baseline and compare speed at several times of day.'
            ],
      adviceRu: unstable
          ? const [
              'Закрепи антенну/кабель и проверь, не меняются ли обслуживающая сота или диапазон.'
            ]
          : const [
              'Сохрани это положение как эталон и сравни скорость в разное время суток.'
            ],
    );
  }

  static double _spread(
    List<LteSignal> history,
    double? Function(LteSignal) value,
  ) {
    final values = history.map(value).whereType<double>().toList();
    if (values.length < 4) return 0;
    values.sort();
    return values.last - values.first;
  }

  static String _format(double? value) {
    if (value == null) return '—';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }
}
