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
