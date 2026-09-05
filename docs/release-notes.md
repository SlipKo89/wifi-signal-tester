# Wi-Fi Signal Tester 0.4.3b — Beta

This Beta adds the first usable Wi-Fi floor-survey workflow and includes the
macOS secure-storage hotfix for MikroTik Wi-Fi sites.

This is a **Beta pre-release**. It remains downloadable from GitHub but does
not replace the latest stable release.

- Both debug and release macOS builds now declare the Keychain Sharing
  entitlement required by `flutter_secure_storage`.
- The sites screen no longer waits forever when secure storage is unavailable.
  Reads and writes have a time limit and the interface shows a clear retryable
  error.
- Site creation, rename and deletion show operation progress; a failed Save is
  reported instead of appearing to do nothing.
- Android behaviour and the read-only router contract are unchanged.
- Wi-Fi floor maps now have named survey sessions, manual points averaged over
  fresh two-sided RSSI/SNR cycles and selectable Phone/AP RSSI/SNR heatmaps.
- `.wifimap` carries the survey history between Android and desktop. Optional
  per-point GPS context is off by default and is never tracked in background.

Assets:

- `wifi-signal-tester-0.4.3b.apk` — Android;
- `wifi-signal-tester-0.4.3b-macos-arm64.zip` — unpack to get
  `Wi-Fi Signal Tester.app` for an Apple-silicon Mac.

The Mac build remains an Alpha and is not yet Developer ID signed or notarized,
so Gatekeeper can show a warning.

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.4.3b — Beta

Эта Beta добавляет первый рабочий сценарий обследования Wi-Fi по плану и
включает исправление защищённого хранения объектов MikroTik Wi-Fi в macOS.

Это **предварительная Beta-версия**. Она доступна на GitHub, но не заменяет
последний стабильный релиз.

- В debug- и release-сборки macOS добавлена capability Keychain Sharing,
  обязательная для `flutter_secure_storage`.
- Экран объектов больше не остаётся в бесконечной загрузке при недоступном
  защищённом хранилище. Чтение и запись ограничены по времени, а интерфейс
  показывает понятную ошибку с кнопкой повтора.
- Создание, переименование и удаление объекта показывают ход операции; ошибка
  сохранения больше не выглядит как неработающая кнопка.
- Поведение Android и гарантия работы с роутерами только на чтение не изменены.
- В картах Wi-Fi появились именованные сессии, ручные точки с усреднением
  свежих двусторонних RSSI/SNR и отдельные heatmap-слои телефона и AP.
- `.wifimap` переносит историю обследований между Android и desktop. GPS-контекст
  точек выключен по умолчанию, фонового отслеживания нет.

Файлы:

- `wifi-signal-tester-0.4.3b.apk` — Android;
- `wifi-signal-tester-0.4.3b-macos-arm64.zip` — распакуй, внутри будет
  `Wi-Fi Signal Tester.app` для Mac на Apple Silicon.

Сборка для Mac остаётся Alpha и пока не подписана Developer ID с notarization,
поэтому Gatekeeper может показать предупреждение.

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
