# Wi-Fi Signal Tester 0.4.2

This release makes the growing application easier to navigate and reduces
noise on MikroTik routers monitored over SSH.

- A new start screen separates MikroTik Wi-Fi, MikroTik LTE and Keenetic Wi-Fi
  Alpha into dedicated tools.
- Named MikroTik Wi-Fi sites keep an independent router set for each home,
  office or customer location. Sites can be created, renamed, annotated and
  deleted; a quick connection can remain temporary.
- Existing saved routers migrate once into an "Imported routers" site. MikroTik
  and Keenetic credentials remain separate in platform secure storage, and the
  legacy record is retained for a safe downgrade.
- MikroTik Wi-Fi and LTE dashboards now compare the installed RouterOS release
  with official security update recommendations. The check is branch-aware,
  cites MikroTik's source and never starts or installs an update.
- The SSH transport now remembers a working RouterOS `print` flavour for each
  menu. Missing wireless generations and rejected registration-table fallbacks
  are probed only once per connection instead of filling `script,error` logs on
  every live poll.
- The official SHA-256 checksum remains pinned for the Gradle 8.11.1 wrapper
  distribution used by Android and F-Droid builds.

Assets:

- `wifi-signal-tester-0.4.2.apk` — Android;
- `wifi-signal-tester-0.4.2-macos-arm64.zip` — unpack to get
  `Wi-Fi Signal Tester.app` for an Apple-silicon Mac.

The Mac build is currently intended for testing and is not yet Developer ID
signed or notarized, so Gatekeeper can show a warning.

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.4.2

Этот релиз упрощает навигацию по выросшему приложению и уменьшает количество
служебных ошибок на MikroTik при мониторинге через SSH.

- Новый стартовый экран разделяет MikroTik Wi-Fi, MikroTik LTE и Keenetic
  Wi-Fi Alpha на самостоятельные инструменты.
- Именованные объекты MikroTik Wi-Fi хранят отдельный набор роутеров для дома,
  офиса или объекта заказчика. Объекты можно создавать, переименовывать,
  дополнять описанием и удалять; быстрое подключение можно не сохранять.
- Существующие профили один раз переносятся в объект «Импортированные роутеры».
  Данные MikroTik и Keenetic разделены в защищённом хранилище платформы, а
  прежняя запись сохранена для безопасного отката приложения.
- Экраны MikroTik Wi-Fi и LTE сопоставляют установленную версию RouterOS с
  официальными рекомендациями по обновлениям безопасности. Проверка учитывает
  ветку выпуска, показывает ссылку MikroTik и никогда не запускает обновление.
- SSH-транспорт запоминает рабочий вариант команды RouterOS `print` для каждого
  меню. Отсутствующие поколения Wi-Fi и неподдерживаемые варианты registration
  table проверяются один раз за подключение, а не засоряют `script,error` при
  каждом цикле мониторинга.
- Для Android/F-Droid по-прежнему закреплена официальная контрольная сумма
  SHA-256 дистрибутива Gradle 8.11.1.

Файлы:

- `wifi-signal-tester-0.4.2.apk` — Android;
- `wifi-signal-tester-0.4.2-macos-arm64.zip` — распакуй, внутри будет
  `Wi-Fi Signal Tester.app` для Mac на Apple Silicon.

Сборка для Mac пока предназначена для тестирования и не подписана Developer ID
с notarization, поэтому Gatekeeper может показать предупреждение.

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
