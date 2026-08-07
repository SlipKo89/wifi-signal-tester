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
  Release('0.3.1', '2026-08-07', [
    'Persistent named LTE history with scalable charts, CSV export and two-session A/B comparison',
    'One LTE Quality Score from 0 to 100 combines power, quality and stability across live, alignment and history views',
    'Initial macOS app for RouterOS audits and LTE tools, built automatically by GitHub Actions for Apple silicon',
    'Android APK and zipped macOS app are published together in one GitHub Release',
  ], [
    'Постоянная история LTE: именованные сессии, масштабируемые графики, CSV и сравнение двух замеров A/B',
    'Единая оценка LTE 0–100 объединяет мощность, качество и стабильность в живом режиме, юстировке и истории',
    'Первое приложение для macOS с аудитами RouterOS и LTE-инструментами; сборка под Apple Silicon выполняется на GitHub',
    'Android APK и ZIP с приложением macOS публикуются вместе в одном GitHub Release',
  ]),
  Release('0.3.0', '2026-08-07', [
    'Separate MikroTik LTE diagnostics over REST, binary API or read-only SSH',
    'Guided antenna alignment with live RSRP/RSRQ/SINR charts, stable checkpoints and return-to-best directions',
    'LTE diagnosis distinguishes weak coverage from interference and marks serving band/cell handoffs',
    'Wi-Fi connection diagnosis can be run manually or automatically after a configurable post-roam delay',
    'Long access-point names and LTE verdict cards are now responsive and use consistent severity colours',
  ], [
    'Отдельная LTE-диагностика MikroTik через REST, бинарный API или SSH только на чтение',
    'Мастер юстировки антенны: живые графики RSRP/RSRQ/SINR, устойчивые точки и возврат к лучшей позиции',
    'LTE-диагностика различает слабое покрытие и помехи, а также отмечает смену диапазона/соты',
    'Анализ Wi-Fi-соединения запускается вручную или автоматически после настраиваемой паузы при роуминге',
    'Длинные имена точек и LTE-вердикты стали адаптивными и используют согласованные цвета важности',
  ]),
  Release('0.2.5', '2026-08-06', [
    'Support ZIP with readable/structured diagnostics and an in-memory event log',
    'Network identifiers are masked by default; credentials and raw RouterOS responses are never included',
    'Bilingual failure banners with stable codes and retry/edit/report actions',
    'Binary API reconnects once after Android or RouterOS closes an idle session',
    'Merging to main now publishes the versioned GitHub Release automatically',
  ], [
    'ZIP для поддержки: читаемый/структурированный отчёт и журнал событий в памяти',
    'Сетевые идентификаторы скрыты по умолчанию; креды и сырые ответы RouterOS не выгружаются',
    'Двуязычные ошибки со стабильными кодами и кнопками повтора/настройки/отчёта',
    'Бинарный API один раз переподключается после закрытия фоновой сессии',
    'После merge в main версия теперь автоматически публикуется в GitHub Releases',
  ]),
  Release('0.2.4', '2026-08-06', [
    'Smart connection diagnosis correlates RSSI/SNR, CCQ, rates, p-throughput, gateway ping/loss and router CPU',
    'A dashboard verdict opens detailed observed facts, likely causes and concrete checks',
    'Diagnosis uses a stable rolling window, ignores isolated spikes and resets after an AP change',
    'Every push to main now produces a downloadable APK artifact without requiring a tag',
  ], [
    'Умная диагностика сопоставляет RSSI/SNR, CCQ, rates, p-throughput, ping/потери до шлюза и CPU роутера',
    'Вердикт на главном экране открывает факты, вероятные причины и конкретные рекомендации',
    'Диагностика использует устойчивое окно, игнорирует одиночные скачки и сбрасывается при смене точки',
    'Каждый push в main теперь создаёт скачиваемый APK в Artifacts без обязательного тега',
  ]),
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
