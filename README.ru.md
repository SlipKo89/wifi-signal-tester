# Тестер уровня Wi-Fi для MikroTik

*English version — [README.md](README.md)*

Приложение на Flutter (сейчас Android, позже iOS) для **тестирования Wi-Fi с
двух сторон**. Обычные анализаторы показывают только то, как телефон слышит
точку доступа. Для реального обследования нужно ещё и то, **как точка слышит
ваше устройство** — сигнал, SNR, скорости. Приложение читает это с MikroTik (с
CAPsMAN или обычным Wi-Fi) **только на чтение**, **только для MAC вашего
устройства**, и показывает рядом с показаниями самого телефона.

```
┌──────────────────────────────────────────────┐
│ Wi-Fi Signal Tester            API · WifiWave2 │
├──────────────────────────────────────────────┤
│ HomeNet_5G     192.168.88.42     Δ AP−phone    │
│ e8:9f:..:1a                        +6 dB       │
├──────────────────────────────────────────────┤
│ ТЕЛЕФОН → слышит точку                         │
│  -48 dBm  ██████████████░░░░                   │
│  SNR оц. 47 dB   Диап. 5 GHz   Частота 5180    │
├──────────────────────────────────────────────┤
│ ТОЧКА → слышит телефон                         │
│  -42 dBm  ████████████████░░                   │
│  SNR 51 dB  TX 866Mbps  RX 780Mbps  Ch0 -44    │
├──────────────────────────────────────────────┤
│  ╱╲    история сигнала   ── телефон  ── точка  │
│ ╱  ╲__╱╲___╱──                                 │
└──────────────────────────────────────────────┘
```

## Возможности

- **Две стороны**: RSSI телефона против сигнала точки по вашей станции, плюс
  дельта между ними.
- **С MikroTik**: `signal-strength` (dBm), `signal-to-noise` (SNR),
  tx/rx-rate, сигнал по цепочкам MIMO, CCQ.
- **Всё автоматически**: определяет стек Wi-Fi (WifiWave2 / новый CAPsMAN /
  старый CAPsMAN / классический) и транспорт (REST → бинарный API).
- **Устойчиво к рандомизации MAC**: находит станцию по IP→MAC через ARP/DHCP,
  поэтому рандомизация MAC на Android 10+ не ломает поиск.
- **Только чтение и по делу**: только `print`/`GET`, только ваш MAC.
- **В реальном времени**: опрос каждые ~2 с и мини-график, чтобы ходить по
  помещению и ловить провалы.

## Что поставить на ноут (macOS)

Нужны Flutter, JDK 17 и Android SDK. На этом маке Homebrew и Xcode есть, а вот
**Flutter, Android SDK и свежая Java — нет**. Ставим:

```bash
# 1) JDK 17 (встроенная Java 8 слишком старая для Android-тулчейна)
brew install --cask temurin@17

# 2) Flutter SDK (Dart идёт в комплекте)
brew install --cask flutter

# 3) Android SDK + platform tools (проще всего через Android Studio)
brew install --cask android-studio
#    затем один раз запустить Android Studio → он поставит SDK

# 4) Указать тулчейну JDK и принять лицензии Android
flutter config --jdk-dir "$(/usr/libexec/java_home -v 17)"
flutter doctor --android-licenses
flutter doctor              # починить всё, что подсветит
```

> Не хочешь Android Studio? Поставь только командные инструменты:
> `brew install --cask android-commandlinetools`, затем
> `sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"`.

## Сборка и запуск

```bash
cd wifi-apk
./scripts/bootstrap.sh        # создаёт android/ и ios/, делает flutter pub get

# один раз добавить разрешения — см. docs/android-setup.md

flutter run                   # на подключённом телефоне (включён USB-debug)
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk
```

Готовый `.apk` копируем на телефон и ставим.

## Сторона MikroTik

Заводим пользователя только для чтения и включаем сервис API/REST — полностью в
[docs/mikrotik-readonly-user.md](docs/mikrotik-readonly-user.md). Кратко:

```
/user group add name=monitor policy=read,api,rest-api,winbox,test
/user add name=monitor group=monitor password=СМЕНИ_МЕНЯ
/ip service enable www-ssl     # для REST
/ip service enable api         # для бинарного API
```

## Как это работает

См. [docs/architecture.md](docs/architecture.md). Одной строкой: читаем IP
телефона → на роутере сопоставляем IP→MAC через ARP/DHCP → читаем таблицу
регистрации для этого MAC → показываем обе стороны рядом.

## Безопасность — только чтение с **обеих** сторон

- **Роутер:** в коде нет ни одного пути записи; в интерфейсе транспорта только
  `read()`. В паре с read-only пользователем RouterOS запись невозможна в
  принципе.
- **Устройство:** приложение только читает Wi-Fi-модуль (RSSI, SSID, частота).
  Оно не меняет, не подключает, не отключает и не забывает сети, не запрашивает
  разрешение `CHANGE_WIFI_STATE`, не трогает файлы, контакты и медиа.
  Единственное, что оно хранит, — *свои же* креды роутера в Keystore.
- Пароль хранится в Android Keystore / iOS Keychain, не в открытых настройках.
- Самоподписанный TLS принимается (расчёт на LAN) — станет видимым
  переключателем (см. [TODO.md](TODO.md)).

## Документы проекта

- [CHANGELOG.md](CHANGELOG.md) — история версий (SemVer)
- [TODO.md](TODO.md) — бэклог / роадмап
- [docs/](docs/) — архитектура, настройка MikroTik и Android

## Лицензия

Уточняется.
