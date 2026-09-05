# Wi-Fi Signal Tester 0.4.4b — Beta

This Beta adds exact two-point calibration to the Wi-Fi floor-survey workflow.

This is a **Beta pre-release**. It remains downloadable from GitHub but does
not replace the latest stable release.

- Select two exact points on a plan or photo and enter their known real-world
  distance to establish the map scale.
- The app previews the resulting dimensions before applying the calibration.
- Walls, doors, windows and historical measurement pins are rescaled together,
  so they remain at the same visual positions on the image.
- The physical grid-cell size remains unchanged.
- The calibration reference is saved in `.wifimap` and is compatible with a
  future optional AR ruler.
- Existing projects remain readable. Android permissions, credentials and the
  read-only router contract are unchanged.

Assets:

- `wifi-signal-tester-0.4.4b.apk` — Android;
- `wifi-signal-tester-0.4.4b-macos-arm64.zip` — unpack to get
  `Wi-Fi Signal Tester.app` for an Apple-silicon Mac.

The Mac build remains an Alpha and is not yet Developer ID signed or notarized,
so Gatekeeper can show a warning.

See [CHANGELOG.md](../blob/main/CHANGELOG.md) for the full history.

---

# Wi-Fi Signal Tester 0.4.4b — Beta

Эта Beta добавляет точную двухточечную калибровку карт обследования Wi-Fi.

Это **предварительная Beta-версия**. Она доступна на GitHub, но не заменяет
последний стабильный релиз.

- На плане или фотографии можно указать две точные точки и ввести известное
  реальное расстояние между ними.
- До применения приложение показывает рассчитанные размеры плана.
- Стены, двери, окна и исторические точки замеров пересчитываются вместе и
  остаются на прежних местах изображения.
- Физический размер клетки сетки не меняется.
- Эталонный отрезок сохраняется в `.wifimap` и совместим с будущей
  необязательной AR-линейкой.
- Старые проекты продолжают открываться. Разрешения Android, хранение учётных
  данных и гарантия работы с роутерами только на чтение не изменены.

Файлы:

- `wifi-signal-tester-0.4.4b.apk` — Android;
- `wifi-signal-tester-0.4.4b-macos-arm64.zip` — распакуй, внутри будет
  `Wi-Fi Signal Tester.app` для Mac на Apple Silicon.

Сборка для Mac остаётся Alpha и пока не подписана Developer ID с notarization,
поэтому Gatekeeper может показать предупреждение.

Полная история изменений — в [CHANGELOG.md](../blob/main/CHANGELOG.md).
