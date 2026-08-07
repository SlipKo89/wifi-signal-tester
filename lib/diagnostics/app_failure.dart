import 'dart:async';
import 'dart:io';

import '../l10n/l10n.dart';

enum AppFailureKind {
  authentication,
  accessDenied,
  timeout,
  connectionRefused,
  unreachable,
  tls,
  unsupported,
  sessionClosed,
  offWifi,
  locationPermission,
  stationNotFound,
  unmanagedAp,
  partialConnection,
  unknown,
}

enum AppFailureSeverity { info, warning, error }

/// A stable, localisable failure shown to the user and written to a support
/// report. [technical] is never shown as the main UI text and is redacted again
/// when an archive is generated.
class AppFailure {
  final AppFailureKind kind;
  final String code;
  final AppFailureSeverity severity;
  final String? technical;
  final int occurrences;

  const AppFailure({
    required this.kind,
    required this.code,
    required this.severity,
    this.technical,
    this.occurrences = 1,
  });

  factory AppFailure.classify(Object error) {
    final raw = _clean(error);
    final text = raw.toLowerCase();

    if (error is TimeoutException ||
        text.contains('timed out') ||
        text.contains('timeout')) {
      return AppFailure(
        kind: text.contains('connection closed')
            ? AppFailureKind.sessionClosed
            : AppFailureKind.timeout,
        code: text.contains('connection closed') ? 'SESSION-01' : 'NET-03',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (text.contains('401') ||
        text.contains('auth') ||
        text.contains('login rejected') ||
        text.contains('invalid user name or password')) {
      return AppFailure(
        kind: AppFailureKind.authentication,
        code: 'AUTH-01',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (text.contains('permission denied') ||
        text.contains('not enough permissions') ||
        text.contains('not permitted') ||
        text.contains('not allowed')) {
      return AppFailure(
        kind: AppFailureKind.accessDenied,
        code: 'AUTH-02',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (text.contains('connection closed') ||
        text.contains('not connected') ||
        text.contains('transport is closed') ||
        text.contains('broken pipe') ||
        text.contains('reset by peer')) {
      return AppFailure(
        kind: AppFailureKind.sessionClosed,
        code: 'SESSION-01',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (text.contains('connection refused')) {
      return AppFailure(
        kind: AppFailureKind.connectionRefused,
        code: 'NET-02',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (text.contains('certificate') ||
        text.contains('handshake') ||
        text.contains('tls')) {
      return AppFailure(
        kind: AppFailureKind.tls,
        code: 'TLS-01',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (text.contains('no wireless registration table') ||
        text.contains('no enabled lte interface') ||
        text.contains('lte interface has no name') ||
        text.contains('lte interface "') ||
        text.contains('rest api not available') ||
        text.contains('unexpected login reply')) {
      return AppFailure(
        kind: AppFailureKind.unsupported,
        code: 'API-01',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    if (error is SocketException ||
        text.contains('network is unreachable') ||
        text.contains('no route to host') ||
        text.contains('host lookup') ||
        text.contains('socket')) {
      return AppFailure(
        kind: AppFailureKind.unreachable,
        code: 'NET-01',
        severity: AppFailureSeverity.error,
        technical: raw,
      );
    }
    return AppFailure(
      kind: AppFailureKind.unknown,
      code: 'UNKNOWN-01',
      severity: AppFailureSeverity.error,
      technical: raw,
    );
  }

  factory AppFailure.offWifi() => const AppFailure(
        kind: AppFailureKind.offWifi,
        code: 'WIFI-01',
        severity: AppFailureSeverity.warning,
      );

  factory AppFailure.station({required bool knownAp}) => AppFailure(
        kind: knownAp
            ? AppFailureKind.stationNotFound
            : AppFailureKind.unmanagedAp,
        code: knownAp ? 'STATION-01' : 'STATION-02',
        severity: AppFailureSeverity.warning,
      );

  factory AppFailure.partial(int failed, int total) => AppFailure(
        kind: AppFailureKind.partialConnection,
        code: 'ROUTER-01',
        severity: AppFailureSeverity.warning,
        technical: '$failed of $total router connections failed',
      );

  String title(L10n l) => switch (kind) {
        AppFailureKind.authentication =>
          l.t('MikroTik login failed', 'Не удалось войти в MikroTik'),
        AppFailureKind.accessDenied =>
          l.t('Not enough read permissions', 'Не хватает прав на чтение'),
        AppFailureKind.timeout =>
          l.t('MikroTik did not answer in time', 'MikroTik не ответил вовремя'),
        AppFailureKind.connectionRefused =>
          l.t('Connection was refused', 'Соединение отклонено'),
        AppFailureKind.unreachable =>
          l.t('MikroTik is unreachable', 'MikroTik недоступен'),
        AppFailureKind.tls =>
          l.t('Secure connection failed', 'Ошибка защищённого подключения'),
        AppFailureKind.unsupported => l.t(
            'Transport or required RouterOS menu is unavailable',
            'Транспорт или нужное меню RouterOS недоступны'),
        AppFailureKind.sessionClosed =>
          l.t('Router session was closed', 'Сессия с роутером закрылась'),
        AppFailureKind.offWifi =>
          l.t('Phone is not on Wi-Fi', 'Телефон не подключён к Wi-Fi'),
        AppFailureKind.locationPermission =>
          l.t('Wi-Fi identity is hidden', 'Данные Wi-Fi скрыты системой'),
        AppFailureKind.stationNotFound => l.t(
            'Phone is not in the registration table',
            'Телефон не найден в registration table'),
        AppFailureKind.unmanagedAp => l.t(
            'This access point is not managed by the selected routers',
            'Эта точка не управляется выбранными роутерами'),
        AppFailureKind.partialConnection => l.t(
            'Some routers could not be reached',
            'Не ко всем роутерам удалось подключиться'),
        AppFailureKind.unknown =>
          l.t('Unexpected connection error', 'Неожиданная ошибка подключения'),
      };

  String description(L10n l) => switch (kind) {
        AppFailureKind.authentication => l.t(
            'The router answered but rejected the username or password. Also '
                'check the policy required by REST, API or SSH.',
            'Роутер ответил, но не принял логин или пароль. Также проверь права, '
                'необходимые для REST, API или SSH.'),
        AppFailureKind.accessDenied => l.t(
            'The account connected, but RouterOS denied one of the read-only '
                'menus. Check the user group policies.',
            'Учётная запись подключилась, но RouterOS запретил чтение одного из '
                'меню. Проверь политики группы пользователя.'),
        AppFailureKind.timeout => l.t(
            'Check that the phone is on the router network, the host and port '
                'are correct, and the selected service is enabled.',
            'Проверь, что телефон находится в сети роутера, адрес и порт верны, '
                'а выбранный сервис включён.'),
        AppFailureKind.connectionRefused => l.t(
            'The host is reachable, but nothing accepts this connection. Check '
                'the transport, port and RouterOS service state.',
            'Узел доступен, но соединение на этом порту никто не принимает. '
                'Проверь транспорт, порт и состояние сервиса RouterOS.'),
        AppFailureKind.unreachable => l.t(
            'Check the router address and make sure the phone is connected to '
                'a network that can reach it.',
            'Проверь адрес роутера и убедись, что телефон подключён к сети, из '
                'которой он доступен.'),
        AppFailureKind.tls => l.t(
            'The TLS handshake failed. Verify the HTTPS/API-SSL port and '
                'certificate settings, or select the correct transport.',
            'Не удалось установить TLS-соединение. Проверь порт HTTPS/API-SSL, '
                'сертификат или выбери правильный транспорт.'),
        AppFailureKind.unsupported => l.t(
            'The selected protocol or required Wi-Fi/LTE menu is not available '
                'on this RouterOS installation.',
            'На этой установке RouterOS нет выбранного протокола или нужного '
                'меню Wi-Fi/LTE.'),
        AppFailureKind.sessionClosed => l.t(
            'Android or RouterOS closed an idle session. The app retries once; '
                'use Retry if the session did not recover.',
            'Android или RouterOS закрыли неактивную сессию. Приложение делает '
                'одну попытку восстановления; при необходимости нажми «Повторить».'),
        AppFailureKind.offWifi => l.t(
            'Connect to Wi-Fi to measure the link. Mobile data cannot provide '
                'Wi-Fi signal information.',
            'Подключись к Wi-Fi для измерения связи. Мобильный интернет не может '
                'дать показатели Wi-Fi.'),
        AppFailureKind.locationPermission => l.t(
            'Android needs location permission and the location service enabled '
                'to reveal SSID and BSSID.',
            'Android требует разрешение геолокации и включённую службу, чтобы '
                'показать SSID и BSSID.'),
        AppFailureKind.stationNotFound => l.t(
            'The phone is on a known AP, but has not appeared in its registration '
                'table for several polls. It may be roaming or reconnecting.',
            'Телефон подключён к известной точке, но несколько опросов не '
                'появляется в registration table. Возможно, идёт роуминг или '
                'переподключение.'),
        AppFailureKind.unmanagedAp => l.t(
            'The phone is on Wi-Fi, but none of the configured MikroTiks reports '
                'this BSSID/client. Only phone-side metrics are available.',
            'Телефон в Wi-Fi, но ни один настроенный MikroTik не сообщает эту '
                'BSSID/станцию. Доступны только показатели телефона.'),
        AppFailureKind.partialConnection => l.t(
            'Monitoring continues with the routers that answered. Open the '
                'support report to see the failed attempts.',
            'Мониторинг продолжится через ответившие роутеры. Неудачные попытки '
                'видны в диагностическом отчёте.'),
        AppFailureKind.unknown => l.t(
            'Retry the operation. If it repeats, send the support archive to '
                'the developer.',
            'Повтори операцию. Если ошибка повторится, отправь разработчику '
                'диагностический архив.'),
      };

  bool get canRetry => kind != AppFailureKind.locationPermission;

  bool get wantsConnectionEdit => switch (kind) {
        AppFailureKind.authentication ||
        AppFailureKind.accessDenied ||
        AppFailureKind.connectionRefused ||
        AppFailureKind.tls ||
        AppFailureKind.unsupported =>
          true,
        _ => false,
      };

  bool get wantsSystemSettings => kind == AppFailureKind.locationPermission;

  Map<String, Object?> toJson() => {
        'code': code,
        'kind': kind.name,
        'severity': severity.name,
        if (technical != null) 'technical': technical,
        'occurrences': occurrences,
      };

  static String _clean(Object error) {
    final text = error.toString().replaceFirst('RouterOsException: ', '');
    return text.length <= 500 ? text : '${text.substring(0, 500)}…';
  }
}
