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
        quality: LteQuality.fair,
        titleEn: 'Signal is strong enough, radio quality is poor',
        titleRu: 'Мощности хватает, но качество радиоканала плохое',
        summaryEn:
            'More antenna gain alone may not help: interference or sector load is more likely.',
        summaryRu:
            'Одно усиление антенны может не помочь: вероятнее помехи или загрузка сектора.',
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

    final grades = [
      rsrpQuality(signal.rsrp),
      rsrqQuality(signal.rsrq),
      sinrQuality(signal.sinr),
      if (signal.cqi != null) cqiQuality(signal.cqi),
    ].where((g) => g != LteQuality.unknown).toList();
    final quality = grades.isEmpty
        ? LteQuality.unknown
        : grades.reduce((a, b) => a.index > b.index ? a : b);

    return LteDiagnosticReport(
      quality: unstable ? LteQuality.fair : quality,
      titleEn:
          unstable ? 'LTE signal is unstable' : 'LTE radio link looks healthy',
      titleRu: unstable
          ? 'LTE-сигнал нестабилен'
          : 'Радиоканал LTE выглядит нормально',
      summaryEn: unstable
          ? 'Average levels are usable, but recent samples fluctuate.'
          : 'Received power and radio quality are in a usable range.',
      summaryRu: unstable
          ? 'Средние уровни рабочие, но последние измерения скачут.'
          : 'Мощность и качество радиоканала находятся в рабочем диапазоне.',
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
}
