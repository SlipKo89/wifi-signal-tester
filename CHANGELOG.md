# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multiple routers.** Add several MikroTiks (central CAPsMAN + standalone
  APs); the app connects to all and, on every poll, reads the AP side from
  whichever router currently serves the client. As you roam between them the
  AP-side data follows you. The serving router is shown as "Via …".
- **AP identification by BSSID.** Each router's radio/BSSID MACs are mapped to
  AP names, so the phone's BSSID reveals which AP it's on — even before it
  appears in a registration table, and it can name a foreign AP too.
- About screen (ⓘ in the app bar): app name, version, description and author
  block — SlipKo, email and Telegram, each tap-to-copy to the clipboard.
- Runtime location permission request on connect (via permission_handler) so
  Android reveals the real SSID/BSSID. A hint with a Settings shortcut appears
  when the name is hidden because permission/GPS is off.

### Changed
- Header no longer says "Not connected to Wi-Fi" when there is an IP and live
  data — connection is judged by IP, SSID is shown when available. The Android
  `02:00:00:00:00:00` BSSID placeholder is hidden instead of displayed.

### Changed
- **Config audit reworked to be accurate and deeper.** It now audits the
  *operating state* (`current-channel` → real width / TX power / frequency) and
  only *applied* CAPsMAN configs, and reads security both inline and via named
  profiles — fixing two false-positive classes (unapplied "open" configs and
  local 2.4 GHz width overridden by CAPsMAN). New checks grounded in MikroTik
  best practices: real 2.4 GHz width, high TX power, co-channel / non-1-6-11
  channels, `tx-power-mode=all-rates-fixed`, missing country, WMM, legacy basic
  rates, and open/WEP/WPA1/TKIP vs WPA2/WPA3. Configs not on air are listed once
  as info instead of flagged.

### Added
- **PDF audit report**: export the audit as a shareable PDF (bundled NotoSans
  font for Cyrillic). Adds a 512×512 icon export alongside the source.
- **App icon**: a "two-sided signal" mark — a green source (phone) and a blue
  source (AP) with waves meeting in the middle, on a dark blue-tinted
  background. Drawn as SVG, with Android adaptive + iOS icons generated via
  flutter_launcher_icons.
- **Audible asymmetry alert**: a bell toggle in the app bar beeps (and vibrates)
  whenever the AP−phone signal divergence exceeds a threshold — a hands-free
  walk-test aid. Threshold is configurable in Settings → Alerts. The tone is
  synthesised in memory (no bundled audio asset).
- **Config audit** (⋮ menu, when connected): reads Wi-Fi config read-only from
  the routers and flags common mistakes for non-experts — open networks,
  WPA1/TKIP/WEP, 2.4 GHz 40 MHz, WMM off, no country, legacy basic rates, very
  high TX power — each with a plain explanation and a suggested fix. Skips
  CAPsMAN-managed radios (their local config is overridden), so it doesn't
  raise false positives.
- **Reference / help for the numbers**: tap any metric for a sheet explaining
  it with good/ok/bad ranges, plus a browsable Reference screen with all
  metrics. Bilingual.
- **Settings screen** (⋮ menu): language (System / English / Русский, applied
  live), poll interval and chart-history length.
- **Persistent measurement history**: a Record button on the dashboard stores
  each pass to a local SQLite DB (our own app data). A History screen lists
  sessions, exports any session to CSV (share sheet), and deletes / clears.
- **More signal metrics**: live throughput (down/up, derived from the AP byte
  counters — works even on CAPsMAN), TX/RX CCQ where reported, RouterOS's own
  `p-throughput` estimate, and session uptime.
- Lightweight RU/EN localization for the main UI (full i18n framework still on
  the backlog). Covers the connection form, the Δ asymmetry sheet and its
  advice, About, and the off-Wi-Fi banner (previously English-only).
- Tap the Δ AP−phone badge for an explanation of the signal-asymmetry metric
  plus rule-based advice from the current numbers (e.g. "AP hears you 24 dB
  weaker → lower AP TX power / move closer").
- MIT license.
- **AP-side SNR** even on legacy CAPsMAN, which doesn't report it: the app reads
  each router's radio noise floor (`monitor once`) and estimates SNR as
  rx-signal − noise-floor (shown as "SNR est."). The phone-side SNR now uses the
  same measured noise floor instead of a fixed −95 dBm assumption. Added a
  read-only `command()` to the transports for `monitor`.

### Fixed
- **No more stale AP-side numbers.** The MAC is re-resolved from ARP every poll
  (the phone gets a new randomized MAC when it roams to another SSID), and when
  the client is in none of the router's registration tables the AP card now
  says so explicitly — "not on a MikroTik-managed AP (standalone / non-CAPsMAN)"
  — instead of showing a leftover reading from the previous association.
- **AP-side data now shows on real routers.** Two bugs found while testing
  against a live hAP AC3 (legacy wireless + CAPsMAN):
  - Stack detection committed to the first table that answered, even if empty.
    On a box where `/interface/wifi/registration-table` (WifiWave2) returns
    200-but-empty, the client in `/caps-man` was never read. Now we probe all
    tables and search every one for our MAC (last-found first — roaming-safe).
  - CAPsMAN reports client signal in `rx-signal`, which we weren't reading.
    Added it alongside `signal` / `signal-strength`.
- Show which access point the client is on (`interface`) — useful with roaming.
- Signal history chart no longer draws below its frame: clip the plot area,
  clamp readings to the axis range and stop the curve overshooting.
- Switching to mobile data no longer throws a raw exception. The app detects
  "off Wi-Fi" and shows a clear message; socket/timeout/auth failures are
  mapped to human-readable banners. MAC cache resets when the IP changes.

### Build
- First successful Android build. Generated `android/`+`ios/`, added the
  read-only permission set to the manifest, and got a clean `flutter analyze`.
- Pinned Android Gradle Plugin to 8.7.3 / Gradle 8.11.1: the toolchain's default
  AGP 9.0.1 dropped the old DSL and broke the Flutter 3.44 Gradle plugin.

### Security
- Documented and enforced read-only on the **device** side too: only
  `wifi_iot` getters are used (no connect/disconnect/forget), `CHANGE_WIFI_STATE`
  is dropped from the manifest, and no file/contacts/media access is requested.

## [0.1.0] - 2026-07-24

### Added
- Initial project scaffold (Flutter, Android + iOS ready).
- Read-only MikroTik client with two interchangeable transports behind one
  interface:
  - `RestTransport` — HTTPS REST API (RouterOS 7.1+).
  - `BinaryApiTransport` — binary API on ports 8728/8729, modern and legacy
    (MD5 challenge) login, works on RouterOS 6 and 7.
- Automatic wireless-stack detection: WifiWave2 → new CAPsMAN → legacy
  CAPsMAN → classic `/interface/wireless`.
- MAC resolution via `/ip/arp` and DHCP leases to work around Android 10+
  randomized MAC.
- Phone-side signal service (RSSI, SSID, BSSID, IP, gateway, frequency).
- Live monitoring controller with polling, history buffer and delta between
  the two sides.
- Home screen: connection form + two-sided signal dashboard + live sparkline.
- Secure credential storage (Android Keystore / iOS Keychain).
- Bilingual documentation (EN/RU), versioning and TODO backlog.

### Security
- Client issues read-only (`print`/GET) requests only — no `set`/`remove`
  anywhere in the code.
- Only the current device's MAC is queried and displayed; other stations are
  ignored.

[Unreleased]: https://example.com/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/releases/tag/v0.1.0
