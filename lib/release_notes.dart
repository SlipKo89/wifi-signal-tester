/// One released version's user-facing highlights (bilingual).
class Release {
  final String version;
  final String date;
  final List<String> en;
  final List<String> ru;
  const Release(this.version, this.date, this.en, this.ru);
}

/// Newest first. Drives the in-app changelog and the "What's new" popup.
const List<Release> kReleases = [
  Release('0.2.3', '2026-08-05', [
    'Expanded MikroTik hardening audit: MAC access, Neighbor Discovery, btest, DNS, proxy/SOCKS/UPnP/Cloud and SSH crypto',
    'Every hardening finding links to the official MikroTik recommendation, including in PDF reports',
    'IPv4 and IPv6 firewall checks now report presence only and never guess whether a service is internet-exposed',
    'Connected devices use access-list and DHCP comments plus hostnames for clearer identification',
  ], [
    'Расширенный hardening-аудит MikroTik: MAC-доступ, Neighbor Discovery, btest, DNS, proxy/SOCKS/UPnP/Cloud и криптография SSH',
    'У каждой hardening-проверки есть ссылка на официальную рекомендацию MikroTik, в том числе в PDF',
    'Проверки firewall для IPv4 и IPv6 показывают только наличие правил и не гадают о доступности сервиса из интернета',
    'Устройства понятнее подписаны комментариями access-list и DHCP, а также hostname',
  ]),
  Release('0.2.2', '2026-08-01', [
    'SSH transport for RouterOS 6/7 when REST or the binary API is unavailable',
    'SSH reconnects after a background pause; incomplete audits no longer guess',
    'System audit detects management services on standard and custom ports',
    'Plain FTP, Telnet, HTTP/WebFig and binary API are highlighted with real ports',
    'Bilingual user guide and GitHub, guide and release links inside the app',
    'Least-privilege Android permissions and the correct Wi-Fi Signal Tester system name',
  ], [
    'SSH-транспорт для RouterOS 6/7, когда REST или бинарный API недоступны',
    'SSH переподключается после фона; неполный аудит больше не делает догадок',
    'Системный аудит видит сервисы управления на стандартных и любых других портах',
    'FTP, Telnet, HTTP/WebFig и бинарный API без шифрования показаны с реальными портами',
    'Двуязычная инструкция и ссылки на GitHub, руководство и релизы в приложении',
    'Минимальные Android-разрешения и правильное системное имя Wi-Fi Signal Tester',
  ]),
  Release('0.2.1', '2026-07-26', [
    'Targets for signal and SNR, with a pass/fail strip on the dashboard',
    'Alerts now beep for signal, SNR or asymmetry out of target',
    'Phone-only mode — view your network without a router',
    'Audit split into Wi-Fi and System, plus router health & hardening checks',
    'Audit judges exposure by the firewall, not just the service ACL',
    'Devices on Wi-Fi list, enriched from DHCP leases',
    'Ping to the gateway, channel number, in-app changelog and licenses',
  ], [
    'Целевые значения сигнала и SNR + строка «в норме / вне цели» на дашборде',
    'Оповещения бипают при выходе сигнала, SNR или асимметрии за цель',
    'Режим без роутера — смотреть свою сеть с телефона',
    'Аудит разделён на Wi-Fi и системный, добавлены проверки здоровья и '
        'безопасности роутера',
    'Аудит оценивает открытость по firewall, а не только по ACL сервиса',
    'Список устройств в Wi-Fi с именами и IP из DHCP',
    'Пинг до шлюза, номер канала, история версий и лицензии в приложении',
  ]),
  Release('0.2.0', '2026-07-24', [
    'Connect to several MikroTiks at once — signal follows you as you roam',
    'Two-sided SNR from the real radio noise floor',
    'Tap the Δ badge for asymmetry advice (lower AP power / move closer)',
    'Settings screen with Russian / English',
    'Measurement history with CSV export',
    'Live metrics: throughput, router CPU, roam counter',
    'Config audit with a shareable PDF report',
    'Audible alert when the two sides diverge',
    'Tap any number for a plain-language explanation',
    'New app icon',
  ], [
    'Подключение к нескольким MikroTik сразу — сигнал едет за тобой при роуминге',
    'Двусторонний SNR по реальному уровню шума радио',
    'Тап по плашке Δ — советы по асимметрии (снизь мощность / подойди ближе)',
    'Экран настроек с русским / английским',
    'История замеров с экспортом в CSV',
    'Живые метрики: скорость, CPU роутера, счётчик роуминга',
    'Аудит настроек с выгрузкой отчёта в PDF',
    'Звуковой сигнал при расхождении сторон',
    'Тап по любой цифре — понятное объяснение',
    'Новая иконка приложения',
  ]),
  Release('0.1.0', '2026-07-24', [
    'First release: two-sided Wi-Fi signal tester for MikroTik',
    'Read-only, shows how the AP hears your device and vice versa',
  ], [
    'Первый релиз: двусторонний тестер Wi-Fi для MikroTik',
    'Только чтение: видно, как точка слышит устройство и наоборот',
  ]),
];
