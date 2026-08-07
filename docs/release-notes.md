# Wi-Fi Signal Tester 0.3.2

- Added read-only RouterOS Wi-Fi event analysis for the current phone and any
  currently-associated device selected from the Devices screen. It explains
  explicit disconnect, access-list, authentication, weak-radio, DFS and
  CAP/CAPsMAN control-path events, and measures reconnect/roaming gaps.
- REST, binary API and SSH produce the same normalized report; Auto remains the
  recommended transport setting. Only `time`, `topics` and `message` are read,
  with at most the latest 2,000 rows analyzed per router. Raw logs and unrelated
  client MACs are not retained, and logging settings are never changed.
- The macOS app now carries a visible `macOS ALPHA` badge in its title bar and
  About dialog. The dialog also explains which desktop-preview features are
  still incomplete; the Android interface is unchanged.
- Fixed a macOS startup freeze while reading the local Wi-Fi adapter. Every
  platform query now has a hard timeout, independent facts are read in parallel
  and the potentially blocking gateway lookup is skipped on Mac.
- The macOS build no longer launches system ICMP `ping` processes. This keeps
  the client-only app sandbox and prevents orphaned high-CPU processes after
  the application is closed or killed.
- The desktop dashboard explicitly explains that local Mac RSSI is not exposed
  by the current plugin. Router-side signal, RouterOS audits and all LTE tools
  remain available.
- Android retains gateway ping; every probe is now stopped explicitly after a
  response, timeout, disconnect or controller disposal.

Assets:

- `wifi-signal-tester-0.3.2.apk` — Android;
- `wifi-signal-tester-0.3.2-macos-arm64.zip` — unpack to get
  `Wi-Fi Signal Tester.app` for an Apple-silicon Mac.

The Mac build is currently intended for testing and is not yet Developer ID
signed or notarized, so Gatekeeper can show a warning.

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.3.2

- Добавлен read-only анализ событий Wi-Fi из RouterOS для текущего телефона и
  любого подключённого устройства, выбранного на экране «Устройства». Он
  объясняет явные причины разрывов, access-list, аутентификации, слабого
  радиоканала, DFS и сбоев CAP/CAPsMAN, а также измеряет время роуминга.
- REST, binary API и SSH формируют одинаковый нормализованный отчёт; Auto
  остаётся рекомендуемым выбором транспорта. Читаются только `time`, `topics` и
  `message`, анализируются максимум 2000 последних строк каждого роутера. Сырые
  логи и MAC посторонних клиентов не сохраняются, настройки логов не меняются.
- В верхней панели и окне «О программе» сборка теперь явно помечена бейджем
  `macOS ALPHA`. Там же перечислены ещё не готовые части десктопной версии;
  интерфейс Android не изменился.
- Исправлено зависание macOS при чтении локального Wi-Fi-адаптера. У каждого
  платформенного вызова теперь есть жёсткий таймаут, независимые сведения
  читаются параллельно, а потенциально зависающий поиск шлюза на Mac пропущен.
- Сборка macOS больше не запускает системные процессы ICMP `ping`. Sandbox
  остаётся только клиентским, а после закрытия или kill приложения не остаются
  сиротские процессы с высокой загрузкой CPU.
- Десктопный дашборд прямо сообщает, что текущий плагин не отдаёт локальный
  RSSI Mac. Сигнал со стороны роутера, аудиты RouterOS и все LTE-инструменты
  продолжают работать.
- На Android ping до шлюза сохранён; каждый процесс теперь явно завершается
  после ответа, таймаута, отключения или уничтожения контроллера.

Файлы:

- `wifi-signal-tester-0.3.2.apk` — Android;
- `wifi-signal-tester-0.3.2-macos-arm64.zip` — распакуй, внутри будет
  `Wi-Fi Signal Tester.app` для Mac на Apple Silicon.

Сборка для Mac пока предназначена для тестирования и не подписана Developer ID
с notarization, поэтому Gatekeeper может показать предупреждение.

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
