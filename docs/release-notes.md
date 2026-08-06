# Wi-Fi Signal Tester 0.2.5

- Support diagnostics can be exported explicitly as a ZIP containing a
  readable report, structured JSON, a bounded event log and a privacy note.
- Network identifiers are masked by default. Passwords, tokens, private keys,
  raw RouterOS responses and full client lists are never included.
- Connection failures now have bilingual explanations, stable support codes
  and relevant Retry, Edit connection and Support report actions.
- The binary RouterOS API reconnects once and replays login after an idle socket
  is closed while Android is in the background.
- A push or merge to `main` now creates the version tag and GitHub Release
  automatically; no manual tag is required.

Download `wifi-signal-tester-0.2.5.apk` below and install it on your Android
device (allow installs from unknown sources when prompted).

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.2.5

- Диагностика для поддержки вручную выгружается в ZIP: читаемый отчёт,
  структурированный JSON, ограниченный журнал событий и памятка о приватности.
- Сетевые идентификаторы скрыты по умолчанию. Пароли, токены, приватные ключи,
  сырые ответы RouterOS и полные списки клиентов не попадают в архив никогда.
- Ошибки подключения получили двуязычные объяснения, стабильные коды и кнопки
  повтора, изменения подключения и создания отчёта.
- Бинарный API RouterOS один раз переподключается и повторяет вход, если Android
  или RouterOS закрыли неактивный сокет в фоне.
- Push или merge в `main` теперь сам создаёт тег версии и GitHub Release —
  вручную создавать тег не требуется.

Скачай `wifi-signal-tester-0.2.5.apk` ниже и установи на Android-устройство
(разреши установку из неизвестных источников, когда телефон спросит).

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
