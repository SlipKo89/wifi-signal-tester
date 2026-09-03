# Wi-Fi Signal Tester 0.4.0

- Added optional read-only Zabbix history. Saved Wi-Fi and LTE sessions can map
  external items, align local and remote tracks on one timeline and export a
  combined CSV. HTTPS remains the default; HTTP requires an explicit choice and
  carries a token-exposure warning.
- Added Keenetic Wi-Fi support as an explicit Alpha, currently verified on
  Runner 4G (KN-2212) with KeeneticOS 5.01.C.3.0-1. The restricted HTTPS RCI
  client reads AP-side association data without exposing generic commands.
- MikroTik Wi-Fi and LTE profiles can optionally send a fixed TCP/UDP
  port-knocking sequence before one explicitly selected REST, API or SSH
  transport. The application never creates or changes RouterOS firewall rules.
- LTE profiles now save several routers securely. A separate read-only LTE
  configuration audit checks APN references, route role, passthrough, MTU,
  roaming, IPv4/IPv6 and native radio restrictions, with PDF export.
- Added Fast, Normal, Economical and Custom polling profiles. Expensive router
  facts are cached, and monitoring plus gateway ping pause while the app is in
  the background.
- SSH now uses trust on first use. A changed key stops the connection and shows
  the previous and new fingerprints before the user can explicitly replace it.
- Improved asynchronous shutdown and SQLite history reliability. Long screens
  and detail sheets now remain above Android gesture and three-button navigation.
- Added English and Russian F-Droid/Fastlane metadata with the icon, redacted
  screenshots and version-specific release notes.

Assets:

- `wifi-signal-tester-0.4.0.apk` — Android;
- `wifi-signal-tester-0.4.0-macos-arm64.zip` — unpack to get
  `Wi-Fi Signal Tester.app` for an Apple-silicon Mac.

The Mac build is currently intended for testing and is not yet Developer ID
signed or notarized, so Gatekeeper can show a warning.

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.4.0

- Добавлена необязательная read-only история Zabbix. Внешние метрики можно
  привязать к сохранённым Wi-Fi/LTE-сессиям, совместить с локальными на одной
  шкале времени и выгрузить общим CSV. По умолчанию используется HTTPS; HTTP
  включается явно и сопровождается предупреждением об открытой передаче токена.
- Добавлена явно помеченная Alpha-поддержка Wi-Fi Keenetic, проверенная на
  Runner 4G (KN-2212) с KeeneticOS 5.01.C.3.0-1. Ограниченный HTTPS RCI-клиент
  читает данные клиента точки и не предоставляет произвольных команд.
- Профили MikroTik Wi-Fi и LTE могут выполнить фиксированную TCP/UDP
  последовательность port knocking перед одним явно выбранным REST, API или SSH.
  Приложение не создаёт и не изменяет правила firewall RouterOS.
- LTE-профили безопасно сохраняют несколько роутеров. Отдельный read-only
  LTE-аудит проверяет APN, роль маршрута, passthrough, MTU, roaming, IPv4/IPv6 и
  ограничения радио и умеет выгружать PDF.
- Добавлены профили опроса «Быстрый», «Обычный», «Экономный» и «Свой». Тяжёлые
  сведения о роутере кэшируются, а мониторинг и ping приостанавливаются в фоне.
- SSH использует trust on first use. При смене известного ключа подключение
  останавливается и показывает старый и новый fingerprints до явной замены.
- Улучшены асинхронное освобождение ресурсов и надёжность SQLite-историй.
  Длинные экраны больше не перекрываются навигационными кнопками Android.
- Добавлены русские и английские метаданные F-Droid/Fastlane, иконка,
  обезличенные скриншоты и отдельные заметки для каждой версии.

Файлы:

- `wifi-signal-tester-0.4.0.apk` — Android;
- `wifi-signal-tester-0.4.0-macos-arm64.zip` — распакуй, внутри будет
  `Wi-Fi Signal Tester.app` для Mac на Apple Silicon.

Сборка для Mac пока предназначена для тестирования и не подписана Developer ID
с notarization, поэтому Gatekeeper может показать предупреждение.

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
