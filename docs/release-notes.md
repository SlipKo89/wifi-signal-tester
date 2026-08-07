# Wi-Fi Signal Tester 0.3.1

- Persistent named LTE measurement sessions with scalable 1×…20× charts, raw
  CSV export and an A/B comparison of two antenna positions or visits.
- A shared LTE Quality Score from 0 to 100 combines RSRP, RSRQ, SINR, optional
  CQI and stability. It is used consistently by live monitoring, antenna
  alignment and saved history, while keeping every raw radio metric available.
- Initial macOS application for RouterOS connection, Wi-Fi/system audits and
  LTE diagnostics/alignment. Android-only local RSSI remains unavailable on Mac
  until the planned native CoreWLAN implementation.
- GitHub Actions now builds Android and Apple-silicon macOS together and adds
  both files to the same versioned Release.

Assets:

- `wifi-signal-tester-0.3.1.apk` — Android;
- `wifi-signal-tester-0.3.1-macos-arm64.zip` — unpack to get
  `Wi-Fi Signal Tester.app` for an Apple-silicon Mac.

The Mac build is currently intended for testing and is not yet Developer ID
signed or notarized, so Gatekeeper can show a warning.

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.3.1

- Постоянная история LTE с именованными сессиями, масштабируемыми графиками
  1×…20×, выгрузкой исходных данных в CSV и сравнением двух положений антенны
  или выездов A/B.
- Единая оценка LTE от 0 до 100 объединяет RSRP, RSRQ, SINR, CQI при наличии и
  стабильность. Одна формула используется в живом режиме, мастере юстировки и
  истории, а исходные радиометрики всегда остаются доступными.
- Первое приложение для macOS: подключение к RouterOS, Wi-Fi/системные аудиты и
  LTE-диагностика с юстировкой. Локальный RSSI самого Mac появится позже через
  запланированную нативную реализацию CoreWLAN.
- GitHub Actions теперь одновременно собирает Android и macOS под Apple Silicon
  и добавляет оба файла в единый релиз версии.

Файлы:

- `wifi-signal-tester-0.3.1.apk` — Android;
- `wifi-signal-tester-0.3.1-macos-arm64.zip` — распакуй, внутри будет
  `Wi-Fi Signal Tester.app` для Mac на Apple Silicon.

Сборка для Mac пока предназначена для тестирования и не подписана Developer ID
с notarization, поэтому Gatekeeper может показать предупреждение.

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
