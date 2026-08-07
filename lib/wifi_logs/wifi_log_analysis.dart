enum WifiLogSeverity { ok, info, warning, critical }

enum WifiLogConfidence { confirmed, likely, context }

enum WifiLogKind {
  connected,
  disconnected,
  connectionAttempt,
  clientLeft,
  inactivity,
  weakSignal,
  radioLoss,
  accessDenied,
  authenticationFailure,
  securityFailure,
  radar,
  channelChange,
  capConnected,
  capDisconnected,
  interfaceDisabled,
}

class WifiLogSourceSnapshot {
  final String host;
  final String transport;
  final List<Map<String, String>> rows;
  final int totalRows;
  final bool truncated;
  final bool infoLogging;
  final bool debugLogging;
  final String? error;

  const WifiLogSourceSnapshot({
    required this.host,
    required this.transport,
    required this.rows,
    required this.totalRows,
    required this.truncated,
    required this.infoLogging,
    required this.debugLogging,
    this.error,
  });

  WifiLogSourceSummary toSummary() => WifiLogSourceSummary(
        host: host,
        transport: transport,
        rowsScanned: rows.length,
        totalRows: totalRows,
        truncated: truncated,
        infoLogging: infoLogging,
        debugLogging: debugLogging,
        error: error,
      );
}

/// Safe source metadata retained after analysis. Unlike the input snapshot it
/// cannot contain RouterOS messages or client identifiers.
class WifiLogSourceSummary {
  final String host;
  final String transport;
  final int rowsScanned;
  final int totalRows;
  final bool truncated;
  final bool infoLogging;
  final bool debugLogging;
  final String? error;

  const WifiLogSourceSummary({
    required this.host,
    required this.transport,
    required this.rowsScanned,
    required this.totalRows,
    required this.truncated,
    required this.infoLogging,
    required this.debugLogging,
    this.error,
  });
}

class WifiLogEvent {
  final WifiLogKind kind;
  final WifiLogSeverity severity;
  final WifiLogConfidence confidence;
  final DateTime? timestamp;
  final String rawTime;
  final String host;
  final String transport;
  final String topics;
  final String titleEn;
  final String titleRu;
  final String detailEn;
  final String detailRu;
  final String? interfaceName;
  final int? signalDbm;
  final bool targetSpecific;
  final int ordinal;

  const WifiLogEvent({
    required this.kind,
    required this.severity,
    required this.confidence,
    required this.timestamp,
    required this.rawTime,
    required this.host,
    required this.transport,
    required this.topics,
    required this.titleEn,
    required this.titleRu,
    required this.detailEn,
    required this.detailRu,
    required this.ordinal,
    this.interfaceName,
    this.signalDbm,
    this.targetSpecific = true,
  });
}

class WifiHandoff {
  final String? fromInterface;
  final String? toInterface;
  final Duration? gap;
  final bool roam;
  final WifiLogSeverity severity;

  const WifiHandoff({
    required this.fromInterface,
    required this.toInterface,
    required this.gap,
    required this.roam,
    required this.severity,
  });
}

class WifiLogReport {
  final String targetMac;
  final String? targetLabel;
  final List<WifiLogSourceSummary> sources;
  final List<WifiLogEvent> events;
  final List<WifiHandoff> handoffs;
  final WifiLogSeverity severity;
  final String verdictEn;
  final String verdictRu;
  final String detailEn;
  final String detailRu;

  const WifiLogReport({
    required this.targetMac,
    required this.targetLabel,
    required this.sources,
    required this.events,
    required this.handoffs,
    required this.severity,
    required this.verdictEn,
    required this.verdictRu,
    required this.detailEn,
    required this.detailRu,
  });

  bool get hasDebug => sources.any((source) => source.debugLogging);
  bool get hasErrors => sources.any((source) => source.error != null);
  int get rowsScanned =>
      sources.fold(0, (sum, source) => sum + source.rowsScanned);
}

class WifiLogAnalyzer {
  static final _macRe = RegExp(
    r'(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f])',
  );
  static final _signalRe =
      RegExp(r'signal(?: strength)?\s*[:=]?\s*(-?\d+)', caseSensitive: false);

  static WifiLogReport analyze({
    required String targetMac,
    String? targetLabel,
    String? targetInterface,
    required List<WifiLogSourceSnapshot> sources,
    DateTime? now,
  }) {
    final mac = _canonicalMac(targetMac);
    if (mac == null) {
      throw ArgumentError.value(targetMac, 'targetMac', 'Invalid MAC address');
    }
    final current = now ?? DateTime.now();
    final events = <WifiLogEvent>[];
    var ordinal = 0;

    for (final source in sources) {
      for (final row in source.rows) {
        final message = row['message']?.trim() ?? '';
        if (message.isEmpty) {
          ordinal++;
          continue;
        }
        final event = _classify(
          message: message,
          topics: row['topics'] ?? '',
          rawTime: row['time'] ?? '',
          host: source.host,
          transport: source.transport,
          targetMac: mac,
          targetInterface: targetInterface,
          now: current,
          ordinal: ordinal++,
        );
        if (event != null) events.add(event);
      }
    }

    events.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at != null && bt != null) {
        final byTime = at.compareTo(bt);
        if (byTime != 0) return byTime;
      }
      return a.ordinal.compareTo(b.ordinal);
    });

    final handoffs = _handoffs(events);
    final diagnosis = _diagnose(events, handoffs, sources);
    return WifiLogReport(
      targetMac: mac,
      targetLabel: targetLabel,
      sources: List.unmodifiable(sources.map((source) => source.toSummary())),
      events: List.unmodifiable(events.reversed),
      handoffs: List.unmodifiable(handoffs.reversed),
      severity: diagnosis.severity,
      verdictEn: diagnosis.verdictEn,
      verdictRu: diagnosis.verdictRu,
      detailEn: diagnosis.detailEn,
      detailRu: diagnosis.detailRu,
    );
  }

  static WifiLogEvent? _classify({
    required String message,
    required String topics,
    required String rawTime,
    required String host,
    required String transport,
    required String targetMac,
    required String? targetInterface,
    required DateTime now,
    required int ordinal,
  }) {
    final lower = message.toLowerCase();
    final targetSpecific = _containsMac(message, targetMac);
    final timestamp = _parseTime(rawTime, now);
    final detectedInterface =
        targetSpecific ? _interfaceFor(message, targetMac) : null;
    final interfaceName = detectedInterface ??
        (targetSpecific &&
                targetInterface != null &&
                lower.contains(targetInterface.toLowerCase())
            ? targetInterface
            : null);
    final signal = int.tryParse(_signalRe.firstMatch(message)?.group(1) ?? '');

    WifiLogEvent event(
      WifiLogKind kind,
      WifiLogSeverity severity,
      WifiLogConfidence confidence,
      String titleEn,
      String titleRu,
      String detailEn,
      String detailRu, {
      bool selected = true,
    }) =>
        WifiLogEvent(
          kind: kind,
          severity: severity,
          confidence: confidence,
          timestamp: timestamp,
          rawTime: rawTime,
          host: host,
          transport: transport,
          topics: topics,
          titleEn: titleEn,
          titleRu: titleRu,
          detailEn: detailEn,
          detailRu: detailRu,
          interfaceName: interfaceName,
          signalDbm: signal,
          targetSpecific: selected,
          ordinal: ordinal,
        );

    if (targetSpecific) {
      final placeEn = _placeEn(interfaceName, signal);
      final placeRu = _placeRu(interfaceName, signal);
      if (lower.contains('mic failure') ||
          lower.contains('tkip countermeasures')) {
        return event(
          WifiLogKind.securityFailure,
          WifiLogSeverity.critical,
          WifiLogConfidence.confirmed,
          'Wi-Fi security exchange failed',
          'Ошибка защиты Wi-Fi',
          'RouterOS reported a MIC failure or TKIP countermeasure.$placeEn',
          'RouterOS сообщил об ошибке MIC или защитной реакции TKIP.$placeRu',
        );
      }
      if (lower.contains('forbidden by access-list') ||
          lower.contains('rejected by access-list') ||
          (lower.contains('access-list') && lower.contains('reject'))) {
        return event(
          WifiLogKind.accessDenied,
          WifiLogSeverity.warning,
          WifiLogConfidence.confirmed,
          'Connection rejected by access list',
          'Подключение запрещено access-list',
          'The selected device matched a rejecting wireless access-list rule.$placeEn',
          'Выбранное устройство попало под запрещающее правило access-list.$placeRu',
        );
      }
      if (lower.contains('extensive data loss') ||
          lower.contains('no beacons') ||
          lower.contains('join timeout')) {
        return event(
          WifiLogKind.radioLoss,
          WifiLogSeverity.warning,
          WifiLogConfidence.confirmed,
          'Radio link was lost',
          'Радиоканал был потерян',
          'The AP could not exchange frames reliably. Weak coverage, interference or a vanished client are possible.$placeEn',
          'Точка не смогла надёжно обмениваться кадрами. Возможны слабое покрытие, помехи или исчезновение клиента.$placeRu',
        );
      }
      if (lower.contains('too weak signal') ||
          lower.contains('signal out of range')) {
        return event(
          WifiLogKind.weakSignal,
          WifiLogSeverity.warning,
          WifiLogConfidence.confirmed,
          'Client removed because of weak signal',
          'Клиент отключён из-за слабого сигнала',
          'RouterOS explicitly applied a signal threshold.$placeEn',
          'RouterOS явно применил настроенный порог сигнала.$placeRu',
        );
      }
      if (_hasAuthenticationFailure(lower)) {
        return event(
          WifiLogKind.authenticationFailure,
          WifiLogSeverity.warning,
          WifiLogConfidence.confirmed,
          'Authentication failed',
          'Ошибка аутентификации',
          'The association or key exchange did not complete. Check PSK, WPA/SAE, PMF, FT or RADIUS settings.$placeEn',
          'Ассоциация или обмен ключами не завершились. Проверь пароль, WPA/SAE, PMF, FT или RADIUS.$placeRu',
        );
      }
      if (lower.contains('sending station leaving') ||
          lower.contains('station leaving') ||
          lower.contains('received deauth') ||
          lower.contains('received disassoc')) {
        return event(
          WifiLogKind.clientLeft,
          WifiLogSeverity.ok,
          WifiLogConfidence.confirmed,
          'Client initiated the disconnect',
          'Клиент сам инициировал отключение',
          'This is commonly a roam, Wi-Fi shutdown or client power-saving event.$placeEn',
          'Обычно это роуминг, выключение Wi-Fi или энергосбережение клиента.$placeRu',
        );
      }
      if (lower.contains('inactivity')) {
        return event(
          WifiLogKind.inactivity,
          WifiLogSeverity.info,
          WifiLogConfidence.confirmed,
          'Client timed out as inactive',
          'Клиент отключён по неактивности',
          'The AP stopped seeing activity from the device; this is not proof of poor radio quality.$placeEn',
          'Точка перестала видеть активность устройства; это не доказывает плохой радиоканал.$placeRu',
        );
      }
      if (lower.contains('disconnected') ||
          lower.contains('lost connection') ||
          lower.contains('decided to deauth')) {
        return event(
          WifiLogKind.disconnected,
          WifiLogSeverity.info,
          WifiLogConfidence.context,
          'Device disconnected',
          'Устройство отключилось',
          'RouterOS did not provide a reason that can be classified safely.$placeEn',
          'RouterOS не сообщил причину, которую можно надёжно классифицировать.$placeRu',
        );
      }
      if (lower.contains('rejected') || lower.contains('failed to connect')) {
        return event(
          WifiLogKind.authenticationFailure,
          WifiLogSeverity.warning,
          WifiLogConfidence.likely,
          'Connection attempt was rejected',
          'Попытка подключения отклонена',
          'The exact reason is not present in this log line.$placeEn',
          'Точная причина в этой строке журнала не указана.$placeRu',
        );
      }
      if (lower.contains('attempts to connect') ||
          lower.contains('attempting to connect')) {
        return event(
          WifiLogKind.connectionAttempt,
          WifiLogSeverity.info,
          WifiLogConfidence.context,
          'Connection attempt',
          'Попытка подключения',
          'The device started association.$placeEn',
          'Устройство начало ассоциацию.$placeRu',
        );
      }
      if (lower.contains('connected') || lower.contains('established')) {
        return event(
          WifiLogKind.connected,
          WifiLogSeverity.ok,
          WifiLogConfidence.confirmed,
          'Device connected',
          'Устройство подключилось',
          'Association completed successfully.$placeEn',
          'Ассоциация успешно завершена.$placeRu',
        );
      }
      return null;
    }

    // Infrastructure events contain no selected-client data. Keep only a
    // narrow whitelist; never surface unrelated client log messages.
    if (lower.contains('radar detected')) {
      return event(
        WifiLogKind.radar,
        WifiLogSeverity.warning,
        WifiLogConfidence.confirmed,
        'Radar detected on the Wi-Fi channel',
        'На Wi-Fi-канале обнаружен радар',
        'DFS can force the AP to leave the current channel and interrupt clients.',
        'DFS может заставить точку сменить канал и временно прервать соединения.',
        selected: false,
      );
    }
    final capsTopic = topics.toLowerCase().contains('caps');
    if (_isCapDown(lower) ||
        (capsTopic &&
            (lower.startsWith('disconnected from ') ||
                lower.startsWith('failed to connect ')))) {
      return event(
        WifiLogKind.capDisconnected,
        WifiLogSeverity.critical,
        WifiLogConfidence.confirmed,
        'CAP lost its manager connection',
        'CAP потерял связь с менеджером',
        'This is a CAP/CAPsMAN control-path problem, not evidence of weak client signal.',
        'Это проблема управляющего соединения CAP/CAPsMAN, а не признак слабого сигнала клиента.',
        selected: false,
      );
    }
    if (_isCapUp(lower) ||
        (capsTopic &&
            (lower.startsWith('connected to ') ||
                lower.startsWith('selected capsman ')))) {
      return event(
        WifiLogKind.capConnected,
        WifiLogSeverity.ok,
        WifiLogConfidence.confirmed,
        'CAP connected to its manager',
        'CAP подключился к менеджеру',
        'The CAP/CAPsMAN control path became available.',
        'Управляющее соединение CAP/CAPsMAN восстановлено.',
        selected: false,
      );
    }
    if ((lower.contains('selected channel') ||
            lower.contains('channel reselect')) &&
        (topics.toLowerCase().contains('wireless') ||
            topics.toLowerCase().contains('caps'))) {
      return event(
        WifiLogKind.channelChange,
        WifiLogSeverity.info,
        WifiLogConfidence.context,
        'Wi-Fi channel selected',
        'Выбран Wi-Fi-канал',
        'A nearby interruption may have been caused by radio provisioning or channel selection.',
        'Соседний по времени разрыв мог быть связан с настройкой радио или выбором канала.',
        selected: false,
      );
    }
    if (lower.contains('interface disabled') &&
        (topics.toLowerCase().contains('wireless') ||
            topics.toLowerCase().contains('caps'))) {
      return event(
        WifiLogKind.interfaceDisabled,
        WifiLogSeverity.warning,
        WifiLogConfidence.confirmed,
        'Wi-Fi interface was disabled',
        'Wi-Fi-интерфейс был отключён',
        'Clients on this radio could not remain associated.',
        'Клиенты этого радиоинтерфейса не могли сохранить подключение.',
        selected: false,
      );
    }
    return null;
  }

  static List<WifiHandoff> _handoffs(List<WifiLogEvent> events) {
    final result = <WifiHandoff>[];
    WifiLogEvent? disconnected;
    for (final event in events.where((event) => event.targetSpecific)) {
      if (_isDisconnectKind(event.kind)) {
        disconnected = event;
        continue;
      }
      if (event.kind != WifiLogKind.connected || disconnected == null) continue;
      Duration? gap;
      if (event.timestamp != null && disconnected.timestamp != null) {
        final value = event.timestamp!.difference(disconnected.timestamp!);
        if (!value.isNegative && value <= const Duration(minutes: 1)) {
          gap = value;
        }
      }
      final from = disconnected.interfaceName;
      final to = event.interfaceName;
      final roam = from != null && to != null && from != to;
      final severity = gap == null
          ? WifiLogSeverity.info
          : gap <= const Duration(seconds: 1)
              ? WifiLogSeverity.ok
              : gap <= const Duration(seconds: 3)
                  ? WifiLogSeverity.info
                  : WifiLogSeverity.warning;
      result.add(WifiHandoff(
        fromInterface: from,
        toInterface: to,
        gap: gap,
        roam: roam,
        severity: severity,
      ));
      disconnected = null;
    }
    return result;
  }

  static _Diagnosis _diagnose(
    List<WifiLogEvent> events,
    List<WifiHandoff> handoffs,
    List<WifiLogSourceSnapshot> sources,
  ) {
    final critical =
        events.where((e) => e.severity == WifiLogSeverity.critical);
    final radioFailures = events.where((e) =>
        e.kind == WifiLogKind.radioLoss ||
        e.kind == WifiLogKind.weakSignal ||
        e.kind == WifiLogKind.authenticationFailure ||
        e.kind == WifiLogKind.accessDenied);
    final disconnects = events.where((e) => _isDisconnectKind(e.kind));
    final slow = handoffs.where((h) => h.severity == WifiLogSeverity.warning);
    final sourceErrors = sources.where((source) => source.error != null).length;

    if (critical.isNotEmpty) {
      return _Diagnosis(
        WifiLogSeverity.critical,
        'Infrastructure or security failure found',
        'Обнаружена инфраструктурная ошибка или ошибка защиты',
        '${critical.length} explicit critical event(s) found in the recent log window.',
        'В недавнем фрагменте журнала найдено критических событий: ${critical.length}.',
      );
    }
    if (radioFailures.length >= 2) {
      return _Diagnosis(
        WifiLogSeverity.warning,
        'Repeated Wi-Fi failures found',
        'Обнаружены повторяющиеся сбои Wi-Fi',
        '${radioFailures.length} radio, access or authentication failures were reported.',
        'Событий радиоканала, доступа или аутентификации: ${radioFailures.length}.',
      );
    }
    if (slow.isNotEmpty) {
      return const _Diagnosis(
        WifiLogSeverity.warning,
        'A slow reconnect or roam was found',
        'Обнаружен медленный роуминг или переподключение',
        'At least one measured handoff took more than three seconds.',
        'Как минимум один измеренный переход занял больше трёх секунд.',
      );
    }
    if (events.isEmpty) {
      return _Diagnosis(
        WifiLogSeverity.info,
        'No events for this device were found',
        'События выбранного устройства не найдены',
        sourceErrors == sources.length && sources.isNotEmpty
            ? 'The routers did not return readable logs.'
            : 'The device may have been stable, or the relevant logging topics are not enabled.',
        sourceErrors == sources.length && sources.isNotEmpty
            ? 'Роутеры не вернули доступный для чтения журнал.'
            : 'Устройство могло работать стабильно, либо нужные темы журналирования не включены.',
      );
    }
    if (disconnects.length >= 3) {
      return _Diagnosis(
        WifiLogSeverity.warning,
        'Frequent disconnects found',
        'Обнаружены частые отключения',
        '${disconnects.length} disconnect events were found in the examined window.',
        'В просмотренном фрагменте найдено отключений: ${disconnects.length}.',
      );
    }
    final measured = handoffs.where((handoff) => handoff.gap != null).length;
    return _Diagnosis(
      WifiLogSeverity.ok,
      'No clear Wi-Fi fault found',
      'Явных проблем Wi-Fi не найдено',
      measured == 0
          ? 'Recent events do not contain an explicit failure reason.'
          : '$measured reconnect or roam event(s) were measured without a severe delay.',
      measured == 0
          ? 'В недавних событиях нет явной причины сбоя.'
          : 'Измерено переходов или переподключений без серьёзной задержки: $measured.',
    );
  }

  static bool _isDisconnectKind(WifiLogKind kind) => {
        WifiLogKind.disconnected,
        WifiLogKind.clientLeft,
        WifiLogKind.inactivity,
        WifiLogKind.weakSignal,
        WifiLogKind.radioLoss,
      }.contains(kind);

  static bool _hasAuthenticationFailure(String lower) =>
      lower.contains('authentication failed') ||
      lower.contains('auth failed') ||
      lower.contains('4-way handshake') ||
      lower.contains('group key exchange timeout') ||
      lower.contains('eapol timeout') ||
      lower.contains('sae authentication') ||
      lower.contains('invalid psk') ||
      lower.contains('radius timeout');

  static bool _isCapDown(String lower) =>
      lower.contains('disconnected from capsman') ||
      lower.contains('cap disconnected') ||
      lower.contains('failed to join capsman') ||
      lower.contains('failed to connect to capsman') ||
      lower.contains('max keepalives without response') ||
      (lower.contains('capsman') && lower.contains('connection interrupted'));

  static bool _isCapUp(String lower) =>
      lower.contains('connected to capsman') ||
      lower.contains('selected capsman') ||
      lower.contains('cap joined') ||
      (lower.contains('joined') && lower.contains('provides radio'));

  static String? _canonicalMac(String raw) {
    final hex = raw.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length != 12) return null;
    return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
  }

  static bool _containsMac(String message, String targetMac) => _macRe
      .allMatches(message)
      .map((match) => _canonicalMac(match.group(0)!))
      .contains(targetMac);

  static String? _interfaceFor(String message, String targetMac) {
    final escaped = RegExp.escape(targetMac);
    final after = RegExp(
      '$escaped@(.+?)\\s+(?:connected|disconnected|rejected|established)',
      caseSensitive: false,
    ).firstMatch(message)?.group(1);
    if (after != null) return _cleanInterface(after);
    final before = RegExp(
      r'^(.+?):\s*' + escaped + r'\s+(?:attempts|failed|established)',
      caseSensitive: false,
    ).firstMatch(message)?.group(1);
    return before == null ? null : _cleanInterface(before);
  }

  static String? _cleanInterface(String raw) {
    var value = raw.trim().replaceFirst(RegExp(r':$'), '');
    value = value.replaceFirst(RegExp(r'\([^)]*\)$'), '').trim();
    return value.isEmpty ? null : value;
  }

  static String _placeEn(String? interfaceName, int? signal) {
    final facts = [
      if (interfaceName != null) 'AP/interface: $interfaceName',
      if (signal != null) 'signal: $signal dBm',
    ];
    return facts.isEmpty ? '' : ' ${facts.join(', ')}.';
  }

  static String _placeRu(String? interfaceName, int? signal) {
    final facts = [
      if (interfaceName != null) 'точка/интерфейс: $interfaceName',
      if (signal != null) 'сигнал: $signal dBm',
    ];
    return facts.isEmpty ? '' : ' ${facts.join(', ')}.';
  }

  static DateTime? _parseTime(String raw, DateTime now) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (iso != null) return iso;

    final full = RegExp(
      r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (full != null) {
      return _dateFromMatch(full, int.parse(full.group(3)!));
    }
    final short = RegExp(
      r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (short != null) {
      final month = _months[short.group(1)!.toLowerCase()]!;
      final year = month > now.month + 1 ? now.year - 1 : now.year;
      return DateTime(
        year,
        month,
        int.parse(short.group(2)!),
        int.parse(short.group(3)!),
        int.parse(short.group(4)!),
        int.parse(short.group(5)!),
        _millis(short.group(6)),
      );
    }
    final time = RegExp(
      r'^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
    ).firstMatch(value);
    if (time == null) return null;
    var result = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(time.group(1)!),
      int.parse(time.group(2)!),
      int.parse(time.group(3)!),
      _millis(time.group(4)),
    );
    if (result.isAfter(now.add(const Duration(minutes: 1)))) {
      result = result.subtract(const Duration(days: 1));
    }
    return result;
  }

  static DateTime _dateFromMatch(RegExpMatch match, int year) => DateTime(
        year,
        _months[match.group(1)!.toLowerCase()]!,
        int.parse(match.group(2)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        _millis(match.group(7)),
      );

  static int _millis(String? raw) {
    if (raw == null) return 0;
    return int.parse(raw.padRight(3, '0'));
  }

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
}

class _Diagnosis {
  final WifiLogSeverity severity;
  final String verdictEn;
  final String verdictRu;
  final String detailEn;
  final String detailRu;

  const _Diagnosis(
    this.severity,
    this.verdictEn,
    this.verdictRu,
    this.detailEn,
    this.detailRu,
  );
}
