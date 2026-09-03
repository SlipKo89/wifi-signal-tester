import '../audit/audit.dart';
import 'lte_service.dart';
import 'lte_signal.dart';

enum LteAuditRole { general, primary, backup, passthrough, monitor }

/// A static, read-only audit of the selected RouterOS LTE interface.
///
/// It deliberately avoids active radio operations (`scan`, `cell-monitor`,
/// `at-chat`) and projects every menu read so SIM PIN, APN credentials and
/// modem/SIM identifiers never enter the process.
class LteAuditEngine {
  static const documentationUrl =
      'https://help.mikrotik.com/docs/spaces/ROS/pages/30146563/LTE+5G';
  static const networkApnUrl =
      'https://help.mikrotik.com/docs/spaces/RKB/pages/30146629/Chateau+LTE12+APN+problem';

  static const _resourceFields = [
    'board-name',
    'version',
    'cpu-load',
    'uptime',
  ];
  static const _interfaceIdentityFields = [
    'name',
    'default-name',
    'disabled',
    'running',
  ];
  static const _interfaceDetailFields = [
    'name',
    'default-name',
    'apn-profiles',
    'allow-roaming',
    'band',
    'nr-band',
    'network-mode',
    'operator',
    'mtu',
  ];
  static const _apnFields = [
    'name',
    'apn',
    'authentication',
    'add-default-route',
    'default-route-distance',
    'ip-type',
    'ipv6-interface',
    'passthrough-interface',
    'passthrough-mac',
    'passthrough-subnet-selection',
    'use-network-apn',
    'use-peer-dns',
  ];
  static const _settingsFields = ['mode', 'sim-slot'];
  static const _filterPresenceFields = ['disabled'];

  Future<List<Finding>> run(
    LteService service, {
    required LteAuditRole role,
    LteSignal? signal,
  }) async {
    final unreadable = <String>{};

    Future<List<Map<String, String>>> read(
      String path,
      List<String> fields, {
      bool reportFailure = true,
    }) async {
      try {
        return await service.readMenu(path, fields: fields);
      } catch (_) {
        if (reportFailure) unreadable.add(path);
        return const [];
      }
    }

    final resources = await read('/system/resource', _resourceFields);
    final resource = resources.isEmpty ? null : resources.first;
    final routerOsMajor = _routerOsMajor(resource?['version']);
    final interfaces = (await read(
      '/interface/lte',
      _interfaceIdentityFields,
    ))
        .map(Map<String, String>.of)
        .toList();
    var interfaceDetailsReadable = true;
    if (interfaces.isNotEmpty) {
      final details = await read(
        '/interface/lte',
        _interfaceDetailFields,
        reportFailure: false,
      );
      if (details.isEmpty) {
        interfaceDetailsReadable = false;
        unreadable.add('/interface/lte (optional properties)');
      } else {
        _mergeInterfaceDetails(interfaces, details);
      }
    }
    final apns = await read('/interface/lte/apn', _apnFields);
    final settings = routerOsMajor != null && routerOsMajor < 7
        ? const <Map<String, String>>[]
        : await read('/interface/lte/settings', _settingsFields);

    final out = <Finding>[];
    _routerInfo(service, resource, out);

    final interface = _selectedInterface(interfaces, service.interfaceName);
    if (interface == null) {
      final emptyResult =
          !unreadable.contains('/interface/lte') && interfaces.isEmpty;
      out.add(Finding(
        unreadable.contains('/interface/lte') || emptyResult
            ? AuditSeverity.warn
            : AuditSeverity.critical,
        titleEn: unreadable.contains('/interface/lte')
            ? 'LTE interface configuration could not be read'
            : emptyResult
                ? 'LTE interface configuration returned no rows'
                : 'Selected LTE interface is unavailable',
        titleRu: unreadable.contains('/interface/lte')
            ? 'Не удалось прочитать настройки LTE-интерфейса'
            : emptyResult
                ? 'Чтение настроек LTE-интерфейса вернуло пустой результат'
                : 'Выбранный LTE-интерфейс недоступен',
        detailEn: unreadable.contains('/interface/lte')
            ? 'Interface-dependent checks were skipped.'
            : emptyResult
                ? 'The live session already selected ${service.interfaceName ?? 'an LTE interface'}, so this is a transport/configuration-read mismatch, not proof that the modem is absent.'
                : 'The connected interface ${service.interfaceName ?? '—'} is no longer present.',
        detailRu: unreadable.contains('/interface/lte')
            ? 'Проверки, зависящие от интерфейса, пропущены.'
            : emptyResult
                ? 'Рабочая сессия уже выбрала ${service.interfaceName ?? 'LTE-интерфейс'}, поэтому это несовместимость чтения настроек через транспорт, а не доказательство отсутствия модема.'
                : 'Интерфейс ${service.interfaceName ?? '—'}, к которому подключилось приложение, больше не найден.',
        fixEn: emptyResult
            ? 'Retry the audit. If live LTE metrics remain available, check the transport compatibility rather than changing the modem configuration.'
            : 'Check `/interface lte print`, modem detection and the selected interface name.',
        fixRu: emptyResult
            ? 'Повтори аудит. Если живые LTE-метрики доступны, проверяй совместимость транспорта, а не меняй настройки модема.'
            : 'Проверь `/interface lte print`, обнаружение модема и выбранное имя интерфейса.',
        where: service.host,
        sourceUrl: documentationUrl,
      ));
      _dataGaps(service, unreadable, out);
      return _sorted(out);
    }

    final name = interface['name'] ?? interface['default-name'] ?? 'LTE';
    _interfaceState(interface, signal, name, out);

    final profileNames = interfaceDetailsReadable
        ? _csv(interface['apn-profiles'] ?? 'default')
        : const <String>[];
    final profilesByName = <String, Map<String, String>>{
      for (final profile in apns)
        if ((profile['name'] ?? '').isNotEmpty) profile['name']!: profile,
    };
    final applied = <Map<String, String>>[];
    for (final profileName in unreadable.contains('/interface/lte/apn')
        ? const <String>[]
        : profileNames) {
      final profile = profilesByName[profileName];
      if (profile == null) {
        out.add(Finding(
          AuditSeverity.critical,
          titleEn: 'APN profile "$profileName" was not found',
          titleRu: 'APN-профиль «$profileName» не найден',
          detailEn:
              '$name references an APN profile that RouterOS did not return.',
          detailRu:
              '$name ссылается на APN-профиль, которого RouterOS не вернул.',
          fixEn: 'Select an existing profile in LTE interface → APN profiles.',
          fixRu: 'Выбери существующий профиль в LTE-интерфейс → APN profiles.',
          where: name,
          sourceUrl: documentationUrl,
        ));
      } else {
        applied.add(profile);
        out.add(Finding(
          AuditSeverity.ok,
          titleEn: 'APN profile resolved: $profileName',
          titleRu: 'APN-профиль найден: $profileName',
          detailEn: 'The interface references an existing APN profile.',
          detailRu: 'Интерфейс ссылается на существующий APN-профиль.',
          where: name,
          sourceUrl: documentationUrl,
        ));
      }
    }

    final usesIpv6 = applied.any(_usesIpv6);
    final ipv6Filter = usesIpv6
        ? await read('/ipv6/firewall/filter', _filterPresenceFields)
        : const <Map<String, String>>[];

    for (final profile in applied) {
      _apnChecks(
        profile,
        interface,
        signal,
        role,
        ipv6Filter,
        ipv6FilterReadable: !unreadable.contains('/ipv6/firewall/filter'),
        routerOsMajor: routerOsMajor,
        interfaceName: name,
        out: out,
      );
    }
    if (interfaceDetailsReadable) {
      _radioPolicyChecks(
        interface,
        settings,
        signal,
        routerOsMajor,
        settingsReadable: !unreadable.contains('/interface/lte/settings'),
        name: name,
        out: out,
      );
    }
    _dataGaps(service, unreadable, out);
    return _sorted(out);
  }

  void _routerInfo(
    LteService service,
    Map<String, String>? resource,
    List<Finding> out,
  ) {
    if (resource == null) return;
    out.add(Finding(
      AuditSeverity.info,
      titleEn: 'Router: ${resource['board-name'] ?? '?'}',
      titleRu: 'Роутер: ${resource['board-name'] ?? '?'}',
      detailEn: 'RouterOS ${resource['version'] ?? '?'} · '
          '${service.transportKind ?? 'RouterOS'} · uptime ${resource['uptime'] ?? '?'}.',
      detailRu: 'RouterOS ${resource['version'] ?? '?'} · '
          '${service.transportKind ?? 'RouterOS'} · аптайм ${resource['uptime'] ?? '?'}.',
      where: service.host,
    ));
  }

  void _interfaceState(
    Map<String, String> interface,
    LteSignal? signal,
    String name,
    List<Finding> out,
  ) {
    final disabled = interface['disabled'] == 'true';
    final running = interface['running'] == 'true';
    out.add(Finding(
      disabled ? AuditSeverity.critical : AuditSeverity.ok,
      titleEn:
          disabled ? 'LTE interface is disabled' : 'LTE interface is enabled',
      titleRu: disabled ? 'LTE-интерфейс выключен' : 'LTE-интерфейс включён',
      detailEn: disabled
          ? '$name cannot register or carry traffic while disabled.'
          : '$name is allowed to operate.',
      detailRu: disabled
          ? '$name не может зарегистрироваться и передавать трафик, пока выключен.'
          : '$name может работать.',
      fixEn: disabled ? 'Enable it in Interfaces → LTE.' : null,
      fixRu: disabled ? 'Включи его в Interfaces → LTE.' : null,
      where: name,
      sourceUrl: documentationUrl,
    ));
    if (!disabled) {
      out.add(Finding(
        running ? AuditSeverity.ok : AuditSeverity.warn,
        titleEn: running
            ? 'LTE interface is running'
            : 'LTE interface is not running',
        titleRu: running
            ? 'LTE-интерфейс работает'
            : 'LTE-интерфейс не в состоянии running',
        detailEn: running
            ? 'RouterOS reports the interface as running.'
            : 'Check SIM state, modem detection, APN and operator coverage.',
        detailRu: running
            ? 'RouterOS сообщает состояние running.'
            : 'Проверь SIM, обнаружение модема, APN и покрытие оператора.',
        where: name,
        sourceUrl: documentationUrl,
      ));
    }

    if (signal == null) {
      out.add(Finding(
        AuditSeverity.info,
        titleEn: 'Registration state is still loading',
        titleRu: 'Состояние регистрации ещё загружается',
        detailEn:
            'Configuration was audited, but the first valid modem monitor sample has not arrived.',
        detailRu:
            'Конфигурация проверена, но первый корректный monitor-ответ модема ещё не пришёл.',
        where: name,
      ));
    } else if (signal.registered) {
      out.add(Finding(
        AuditSeverity.ok,
        titleEn: 'Modem is registered',
        titleRu: 'Модем зарегистрирован',
        detailEn:
            '${signal.operatorName ?? 'Operator detected'} · ${signal.technology ?? 'mobile network'}.',
        detailRu:
            '${signal.operatorName ?? 'Оператор определён'} · ${signal.technology ?? 'мобильная сеть'}.',
        where: name,
      ));
    } else {
      out.add(Finding(
        AuditSeverity.critical,
        titleEn: 'Modem is not registered',
        titleRu: 'Модем не зарегистрирован',
        detailEn: 'Current status: ${signal.status ?? 'not registered'}.',
        detailRu: 'Текущее состояние: ${signal.status ?? 'нет регистрации'}.',
        fixEn:
            'Check SIM/PIN state in RouterOS, APN, antenna connections and operator coverage.',
        fixRu:
            'Проверь в RouterOS состояние SIM/PIN, APN, антенные разъёмы и покрытие оператора.',
        where: name,
        sourceUrl: documentationUrl,
      ));
    }
  }

  void _apnChecks(
    Map<String, String> apn,
    Map<String, String> interface,
    LteSignal? signal,
    LteAuditRole role,
    List<Map<String, String>> ipv6Filter, {
    required bool ipv6FilterReadable,
    required int? routerOsMajor,
    required String interfaceName,
    required List<Finding> out,
  }) {
    final name = apn['name'] ?? 'default';
    final where = '$interfaceName · $name';
    final apnValue = (apn['apn'] ?? '').trim();
    final supportsNetworkApn = routerOsMajor == null || routerOsMajor >= 7;
    final networkApn =
        supportsNetworkApn && _yes(apn['use-network-apn'], fallback: true);
    if (supportsNetworkApn && apnValue.isNotEmpty && networkApn) {
      out.add(Finding(
        AuditSeverity.warn,
        titleEn: 'Manual APN may be overridden by the network',
        titleRu: 'Сетевой APN может перекрыть ручной',
        detailEn:
            'Profile $name contains APN "$apnValue", while use-network-apn=yes. MBIM modems may use the operator-provided APN instead.',
        detailRu:
            'В профиле $name указан APN «$apnValue», но use-network-apn=yes. MBIM-модем может использовать APN, полученный от оператора.',
        fixEn:
            'If this SIM requires exactly "$apnValue", verify the active APN and consider use-network-apn=no.',
        fixRu:
            'Если SIM требует именно «$apnValue», проверь фактический APN и рассмотри use-network-apn=no.',
        where: where,
        sourceUrl: networkApnUrl,
      ));
    } else if (supportsNetworkApn) {
      out.add(Finding(
        AuditSeverity.ok,
        titleEn: networkApn
            ? 'Network APN selection is enabled'
            : 'Manual APN selection is explicit',
        titleRu: networkApn
            ? 'Включён выбор APN оператором'
            : 'Ручной APN выбран явно',
        detailEn: networkApn
            ? 'The modem may accept the APN supplied by the mobile network.'
            : 'RouterOS will use ${apnValue.isEmpty ? 'the configured profile value' : '"$apnValue"'} instead of replacing it with a network APN.',
        detailRu: networkApn
            ? 'Модем может принять APN, который сообщает мобильная сеть.'
            : 'RouterOS будет использовать ${apnValue.isEmpty ? 'значение профиля' : '«$apnValue»'}, не заменяя его сетевым APN.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    } else {
      out.add(Finding(
        AuditSeverity.ok,
        titleEn: 'APN is explicit on RouterOS 6',
        titleRu: 'APN задан явно в RouterOS 6',
        detailEn: apnValue.isEmpty
            ? 'The profile uses its default APN value.'
            : 'Configured APN: "$apnValue". RouterOS 7 MBIM network-APN behaviour is not applied.',
        detailRu: apnValue.isEmpty
            ? 'Профиль использует значение APN по умолчанию.'
            : 'Настроенный APN: «$apnValue». Поведение network APN для MBIM из RouterOS 7 здесь не применяется.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    }

    final auth = (apn['authentication'] ?? 'none').toLowerCase();
    out.add(Finding(
      auth == 'none' ? AuditSeverity.ok : AuditSeverity.info,
      titleEn: auth == 'none'
          ? 'APN authentication is not required'
          : 'APN authentication: ${auth.toUpperCase()}',
      titleRu: auth == 'none'
          ? 'Аутентификация APN не требуется'
          : 'Аутентификация APN: ${auth.toUpperCase()}',
      detailEn: auth == 'none'
          ? 'No PAP/CHAP credentials are expected for this profile.'
          : 'Credentials are required by this profile. The audit deliberately does not read the APN username or password.',
      detailRu: auth == 'none'
          ? 'Для профиля не ожидаются логин и пароль PAP/CHAP.'
          : 'Профилю нужны учётные данные. Аудит намеренно не читает логин и пароль APN.',
      where: where,
      sourceUrl: documentationUrl,
    ));

    _routeChecks(apn, role, where, out);
    _passthroughChecks(apn, role, where, out);
    _ipChecks(
      apn,
      interface,
      ipv6Filter,
      ipv6FilterReadable: ipv6FilterReadable,
      where: where,
      out: out,
    );

    final peerDns = _yes(apn['use-peer-dns'], fallback: true);
    out.add(Finding(
      AuditSeverity.info,
      titleEn: peerDns ? 'Operator DNS is accepted' : 'Operator DNS is ignored',
      titleRu:
          peerDns ? 'DNS оператора принимается' : 'DNS оператора игнорируется',
      detailEn: peerDns
          ? 'The LTE link may add DNS servers supplied by the operator.'
          : 'Make sure another DNS source is configured and reachable.',
      detailRu: peerDns
          ? 'LTE-соединение может добавить DNS-серверы оператора.'
          : 'Убедись, что настроен и доступен другой источник DNS.',
      where: where,
      sourceUrl: documentationUrl,
    ));
  }

  void _routeChecks(
    Map<String, String> apn,
    LteAuditRole role,
    String where,
    List<Finding> out,
  ) {
    final addsRoute = _yes(apn['add-default-route'], fallback: true);
    final distance = int.tryParse(apn['default-route-distance'] ?? '') ?? 2;
    switch (role) {
      case LteAuditRole.primary:
        out.add(Finding(
          addsRoute ? AuditSeverity.ok : AuditSeverity.warn,
          titleEn: addsRoute
              ? 'LTE default route is enabled'
              : 'No automatic LTE default route',
          titleRu: addsRoute
              ? 'Маршрут по умолчанию через LTE включён'
              : 'Автоматического маршрута через LTE нет',
          detailEn: addsRoute
              ? 'For the selected primary-link role RouterOS adds a route with distance $distance.'
              : 'A primary LTE link needs another explicit route or policy-routing design.',
          detailRu: addsRoute
              ? 'Для выбранного основного канала RouterOS добавляет маршрут с distance $distance.'
              : 'Основному LTE-каналу нужен другой явный маршрут или схема policy routing.',
          where: where,
          sourceUrl: documentationUrl,
        ));
      case LteAuditRole.backup:
        if (!addsRoute) {
          out.add(Finding(
            AuditSeverity.info,
            titleEn: 'Backup route is managed elsewhere',
            titleRu: 'Резервный маршрут управляется отдельно',
            detailEn:
                'The APN does not create a default route. Verify your static route, script or routing policy.',
            detailRu:
                'APN не создаёт маршрут по умолчанию. Проверь статический маршрут, скрипт или routing policy.',
            where: where,
            sourceUrl: documentationUrl,
          ));
        } else {
          out.add(Finding(
            distance > 1 ? AuditSeverity.ok : AuditSeverity.warn,
            titleEn: distance > 1
                ? 'Backup route has a higher distance'
                : 'Backup route distance is very low',
            titleRu: distance > 1
                ? 'У резервного маршрута повышен distance'
                : 'Слишком низкий distance резервного маршрута',
            detailEn:
                'RouterOS adds the LTE default route with distance $distance. This check does not infer the rest of the routing policy.',
            detailRu:
                'RouterOS добавляет LTE-маршрут с distance $distance. Проверка не пытается угадать остальную политику маршрутизации.',
            fixEn: distance <= 1
                ? 'Verify that LTE cannot unexpectedly outrank the intended primary route.'
                : null,
            fixRu: distance <= 1
                ? 'Проверь, что LTE неожиданно не получит приоритет над основным маршрутом.'
                : null,
            where: where,
            sourceUrl: documentationUrl,
          ));
        }
      case LteAuditRole.general:
      case LteAuditRole.monitor:
        out.add(Finding(
          AuditSeverity.info,
          titleEn: addsRoute
              ? 'APN adds a default route'
              : 'APN does not add a default route',
          titleRu: addsRoute
              ? 'APN добавляет маршрут по умолчанию'
              : 'APN не добавляет маршрут по умолчанию',
          detailEn: addsRoute
              ? 'Configured distance: $distance. Select Primary or Backup for a role-aware verdict.'
              : 'Routing may be managed manually.',
          detailRu: addsRoute
              ? 'Настроенный distance: $distance. Выбери Основной или Резервный для проверки с учётом роли.'
              : 'Маршрутизация может управляться вручную.',
          where: where,
          sourceUrl: documentationUrl,
        ));
      case LteAuditRole.passthrough:
        // In passthrough mode the downstream host owns the mobile address, so
        // a route on this router is not graded.
        break;
    }
  }

  void _passthroughChecks(
    Map<String, String> apn,
    LteAuditRole role,
    String where,
    List<Finding> out,
  ) {
    final target = (apn['passthrough-interface'] ?? '').trim();
    final enabled = target.isNotEmpty;
    if (role == LteAuditRole.passthrough && !enabled) {
      out.add(Finding(
        AuditSeverity.warn,
        titleEn: 'Passthrough role selected, but passthrough is not configured',
        titleRu: 'Выбран passthrough, но он не настроен',
        detailEn: 'This APN profile has no passthrough-interface.',
        detailRu: 'В APN-профиле не указан passthrough-interface.',
        fixEn:
            'Select the intended downstream interface, if the modem supports passthrough.',
        fixRu:
            'Укажи нужный downstream-интерфейс, если модем поддерживает passthrough.',
        where: where,
        sourceUrl: documentationUrl,
      ));
      return;
    }
    if (!enabled) return;

    final mac = (apn['passthrough-mac'] ?? 'auto').trim();
    out.add(Finding(
      mac.isEmpty || mac == 'auto' ? AuditSeverity.warn : AuditSeverity.ok,
      titleEn: mac.isEmpty || mac == 'auto'
          ? 'Passthrough learns the first client automatically'
          : 'Passthrough client is pinned',
      titleRu: mac.isEmpty || mac == 'auto'
          ? 'Passthrough автоматически выбирает первого клиента'
          : 'Клиент passthrough зафиксирован',
      detailEn: mac.isEmpty || mac == 'auto'
          ? 'Only one host can receive passthrough. On $target the first packet determines that host.'
          : 'The mobile address is assigned only to the configured MAC on $target.',
      detailRu: mac.isEmpty || mac == 'auto'
          ? 'Passthrough обслуживает только один хост. На $target его определит первый пакет.'
          : 'Мобильный адрес передаётся только заданному MAC на $target.',
      fixEn: mac.isEmpty || mac == 'auto'
          ? 'Pin passthrough-mac when more than one device can appear on that segment.'
          : null,
      fixRu: mac.isEmpty || mac == 'auto'
          ? 'Зафиксируй passthrough-mac, если в этом сегменте может появиться больше одного устройства.'
          : null,
      where: where,
      sourceUrl: documentationUrl,
    ));
    out.add(Finding(
      AuditSeverity.info,
      titleEn: 'Keep a separate management path',
      titleRu: 'Нужен отдельный путь управления',
      detailEn:
          'MikroTik recommends an additional connection, such as a management VLAN, because passthrough changes how the LTE address is reached.',
      detailRu:
          'MikroTik рекомендует отдельное подключение, например management VLAN: passthrough меняет доступ через LTE-адрес.',
      where: where,
      sourceUrl: documentationUrl,
    ));
  }

  void _ipChecks(
    Map<String, String> apn,
    Map<String, String> interface,
    List<Map<String, String>> ipv6Filter, {
    required bool ipv6FilterReadable,
    required String where,
    required List<Finding> out,
  }) {
    final ipType = (apn['ip-type'] ?? '').toLowerCase();
    final ipv6 = _usesIpv6(apn);
    if (ipType.isEmpty) {
      out.add(Finding(
        AuditSeverity.info,
        titleEn: 'PDN IP type uses the RouterOS/operator default',
        titleRu: 'Тип IP-сессии определяется RouterOS/оператором',
        detailEn:
            'The APN does not explicitly request IPv4, IPv6 or dual-stack.',
        detailRu: 'APN явно не запрашивает IPv4, IPv6 или dual-stack.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    } else {
      out.add(Finding(
        AuditSeverity.ok,
        titleEn: 'PDN type: $ipType',
        titleRu: 'Тип IP-сессии: $ipType',
        detailEn: ipv6
            ? 'The mobile session requests IPv6 support.'
            : 'The mobile session requests IPv4 only.',
        detailRu: ipv6
            ? 'Мобильная сессия запрашивает поддержку IPv6.'
            : 'Мобильная сессия запрашивает только IPv4.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    }

    if (ipv6 && ipv6FilterReadable) {
      final activeRules = ipv6Filter.where((row) => row['disabled'] != 'true');
      out.add(Finding(
        activeRules.isEmpty ? AuditSeverity.warn : AuditSeverity.ok,
        titleEn: activeRules.isEmpty
            ? 'IPv6 requested, but no active IPv6 filter rules found'
            : 'IPv6 firewall rules are present',
        titleRu: activeRules.isEmpty
            ? 'Запрошен IPv6, но активных IPv6 filter rules нет'
            : 'Правила IPv6 firewall присутствуют',
        detailEn: activeRules.isEmpty
            ? 'The audit checks presence only; it does not infer firewall coverage or rule correctness.'
            : '${activeRules.length} active rule(s) found. Their order and effectiveness are deliberately not assessed.',
        detailRu: activeRules.isEmpty
            ? 'Аудит проверяет только наличие и не пытается оценить покрытие или правильность firewall.'
            : 'Найдено активных правил: ${activeRules.length}. Порядок и эффективность намеренно не оцениваются.',
        fixEn: activeRules.isEmpty
            ? 'Add an intentional IPv6 firewall policy before using provider IPv6.'
            : null,
        fixRu: activeRules.isEmpty
            ? 'Настрой осознанную политику IPv6 firewall до использования IPv6 оператора.'
            : null,
        where: where,
      ));
    }

    final mtuText = (interface['mtu'] ?? '1500').toLowerCase();
    final mtu = int.tryParse(mtuText);
    if (mtuText == 'auto') {
      out.add(Finding(
        AuditSeverity.ok,
        titleEn: 'LTE MTU is automatic',
        titleRu: 'LTE MTU выбирается автоматически',
        detailEn:
            'Supporting MBIM modems can use the MTU advertised by the network.',
        detailRu:
            'Поддерживающий MBIM-модем может использовать MTU, сообщённый сетью.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    } else if (ipv6 && mtu != null && mtu < 1280) {
      out.add(Finding(
        AuditSeverity.critical,
        titleEn: 'MTU $mtu is too small for IPv6',
        titleRu: 'MTU $mtu слишком мал для IPv6',
        detailEn: 'IPv6 requires a link MTU of at least 1280 bytes.',
        detailRu: 'Для IPv6 требуется MTU канала не менее 1280 байт.',
        fixEn: 'Use a valid MTU or auto when this modem supports it.',
        fixRu: 'Установи корректный MTU или auto, если модем это поддерживает.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    } else {
      out.add(Finding(
        AuditSeverity.info,
        titleEn: 'LTE MTU is fixed at ${mtu ?? mtuText}',
        titleRu: 'LTE MTU зафиксирован: ${mtu ?? mtuText}',
        detailEn:
            'A fixed MTU is not automatically wrong. Investigate it only if large packets, VPNs or IPv6 have fragmentation problems.',
        detailRu:
            'Фиксированный MTU сам по себе не ошибка. Проверяй его при проблемах больших пакетов, VPN или IPv6.',
        where: where,
        sourceUrl: documentationUrl,
      ));
    }
  }

  void _radioPolicyChecks(
    Map<String, String> interface,
    List<Map<String, String>> settings,
    LteSignal? signal,
    int? routerOsMajor, {
    required bool settingsReadable,
    required String name,
    required List<Finding> out,
  }) {
    final networkMode = (interface['network-mode'] ?? '').trim();
    final bands = (interface['band'] ?? '').trim();
    final nrBands = (interface['nr-band'] ?? '').trim();
    final operator = (interface['operator'] ?? '').trim();
    final nativeLocks = [
      if (bands.isNotEmpty) 'LTE bands: $bands',
      if (nrBands.isNotEmpty) 'NR bands: $nrBands',
      if (operator.isNotEmpty) 'operator: $operator',
    ];

    out.add(Finding(
      networkMode.isEmpty ? AuditSeverity.ok : AuditSeverity.info,
      titleEn: networkMode.isEmpty
          ? 'Network technology is not forced'
          : 'Network mode is restricted: $networkMode',
      titleRu: networkMode.isEmpty
          ? 'Технология сети не зафиксирована'
          : 'Режим сети ограничен: $networkMode',
      detailEn: networkMode.isEmpty
          ? 'The modem can select among its supported network technologies.'
          : 'This may be intentional, but it can remove fallback technologies when LTE/5G coverage changes.',
      detailRu: networkMode.isEmpty
          ? 'Модем может выбирать из поддерживаемых технологий сети.'
          : 'Это может быть намеренно, но убирает резервные технологии при изменении покрытия LTE/5G.',
      where: name,
      sourceUrl: documentationUrl,
    ));

    out.add(Finding(
      nativeLocks.isEmpty ? AuditSeverity.ok : AuditSeverity.info,
      titleEn: nativeLocks.isEmpty
          ? 'No native band/operator lock found'
          : 'Radio selection is restricted',
      titleRu: nativeLocks.isEmpty
          ? 'Штатных ограничений диапазона/оператора нет'
          : 'Выбор радиосети ограничен',
      detailEn: nativeLocks.isEmpty
          ? 'RouterOS may select supported bands and the available operator.'
          : '${nativeLocks.join(' · ')}. Verify this against the operator and site; a narrow lock can reduce fallback or carrier aggregation.',
      detailRu: nativeLocks.isEmpty
          ? 'RouterOS может выбирать поддерживаемые диапазоны и доступного оператора.'
          : '${nativeLocks.join(' · ')}. Сверь с оператором и объектом: узкое ограничение может убрать fallback или агрегацию несущих.',
      where: name,
      sourceUrl: documentationUrl,
    ));

    final allowRoaming = _yes(interface['allow-roaming'], fallback: false);
    out.add(Finding(
      AuditSeverity.info,
      titleEn:
          allowRoaming ? 'Data roaming is allowed' : 'Data roaming is disabled',
      titleRu: allowRoaming
          ? 'Передача данных в роуминге разрешена'
          : 'Передача данных в роуминге запрещена',
      detailEn: allowRoaming
          ? 'Verify roaming cost and the intended operator policy.'
          : 'This is the safe default. Some partially supported modems may register but fail to establish IP data while roaming is disabled.',
      detailRu: allowRoaming
          ? 'Проверь стоимость роуминга и ожидаемую политику оператора.'
          : 'Это безопасное значение по умолчанию. Некоторые частично поддерживаемые модемы могут зарегистрироваться, но не поднять IP-сессию.',
      where: name,
      sourceUrl: documentationUrl,
    ));

    if (routerOsMajor != null && routerOsMajor < 7) {
      out.add(Finding(
        AuditSeverity.info,
        titleEn: 'RouterOS 6 LTE compatibility mode',
        titleRu: 'Режим совместимости LTE с RouterOS 6',
        detailEn:
            'RouterOS 7-only LTE settings and MBIM use-network-apn behaviour are not graded.',
        detailRu:
            'Настройки LTE только для RouterOS 7 и поведение MBIM use-network-apn не оцениваются.',
        where: name,
        sourceUrl: documentationUrl,
      ));
    } else if (settingsReadable) {
      final mode =
          settings.isEmpty ? 'auto' : (settings.first['mode'] ?? 'auto');
      out.add(Finding(
        mode == 'auto' ? AuditSeverity.ok : AuditSeverity.info,
        titleEn: mode == 'auto'
            ? 'LTE driver mode is automatic'
            : 'LTE driver mode is forced: $mode',
        titleRu: mode == 'auto'
            ? 'Режим драйвера LTE выбирается автоматически'
            : 'Режим драйвера LTE зафиксирован: $mode',
        detailEn: mode == 'auto'
            ? 'RouterOS selects MBIM/serial mode for the detected modem.'
            : 'A forced mode may be required for a specific modem; document why it is needed.',
        detailRu: mode == 'auto'
            ? 'RouterOS выбирает MBIM/serial для обнаруженного модема.'
            : 'Фиксированный режим может требоваться конкретному модему — стоит зафиксировать причину.',
        where: name,
        sourceUrl: documentationUrl,
      ));
    }

    if (signal?.modemModel != null || signal?.revision != null) {
      out.add(Finding(
        AuditSeverity.info,
        titleEn: 'Modem firmware inventory',
        titleRu: 'Информация о прошивке модема',
        detailEn:
            '${signal?.modemModel ?? 'Unknown modem'} · revision ${signal?.revision ?? 'not reported'}. Update availability is not queried because this audit uses plain reads only.',
        detailRu:
            '${signal?.modemModel ?? 'Неизвестный модем'} · ревизия ${signal?.revision ?? 'не сообщена'}. Наличие обновления не запрашивается: аудит использует только обычное чтение.',
        where: name,
        sourceUrl: documentationUrl,
      ));
    }
  }

  void _dataGaps(
    LteService service,
    Set<String> unreadable,
    List<Finding> out,
  ) {
    if (unreadable.isEmpty) return;
    final menus = (unreadable.toList()..sort()).join(', ');
    out.add(Finding(
      AuditSeverity.warn,
      titleEn: 'LTE audit is incomplete',
      titleRu: 'LTE-аудит неполный',
      detailEn:
          'Checks depending on these menus were skipped instead of guessed: $menus.',
      detailRu:
          'Зависящие от этих меню проверки пропущены, а не угаданы: $menus.',
      fixEn:
          'Retry the audit and verify that the RouterOS user has read access.',
      fixRu:
          'Повтори аудит и проверь наличие read-доступа у пользователя RouterOS.',
      where: service.host,
    ));
  }

  Map<String, String>? _selectedInterface(
    List<Map<String, String>> interfaces,
    String? selected,
  ) {
    for (final interface in interfaces) {
      if (interface['name'] == selected ||
          interface['default-name'] == selected) {
        return interface;
      }
    }
    return interfaces.length == 1 ? interfaces.first : null;
  }

  void _mergeInterfaceDetails(
    List<Map<String, String>> interfaces,
    List<Map<String, String>> details,
  ) {
    for (final interface in interfaces) {
      final name = interface['name'] ?? interface['default-name'];
      Map<String, String>? match;
      for (final detail in details) {
        if (name != null &&
            (detail['name'] == name || detail['default-name'] == name)) {
          match = detail;
          break;
        }
      }
      match ??=
          interfaces.length == 1 && details.length == 1 ? details.first : null;
      if (match != null) interface.addAll(match);
    }
  }

  int? _routerOsMajor(String? version) =>
      int.tryParse(RegExp(r'^\d+').firstMatch(version ?? '')?.group(0) ?? '');

  bool _yes(String? value, {required bool fallback}) => value == null
      ? fallback
      : value.toLowerCase() == 'true' || value.toLowerCase() == 'yes';

  bool _usesIpv6(Map<String, String> apn) =>
      (apn['ip-type'] ?? '').toLowerCase().contains('ipv6');

  List<String> _csv(String value) {
    final values = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return values.isEmpty ? const ['default'] : values;
  }

  List<Finding> _sorted(List<Finding> findings) => findings
    ..sort((left, right) => left.sev.index.compareTo(right.sev.index));
}
