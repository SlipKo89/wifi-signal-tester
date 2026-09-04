# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] - 2026-09-05

### Security
- Pin the official SHA-256 checksum for the Gradle 8.11.1 complete
  distribution used by the Android wrapper. Gradle and F-Droid can now reject
  a modified distribution before it is used by the build. No application
  runtime behaviour changed.

## [0.4.0] - 2026-09-04

### Added
- **Optional TCP/UDP port knocking for MikroTik Wi-Fi and LTE profiles.** A
  profile can hold 1–8 ordered steps plus inter-step and post-knock delays. The
  sequence runs before the selected REST, binary API or SSH connection and at
  most once more after a genuine network/session failure. Authentication,
  RouterOS command and SSH host-key errors never trigger another knock.
- **Optional read-only Zabbix history integration** using a user-supplied API
  token. It discovers readable hosts and active numeric items, shows raw
  `history.get` data for 1/24 hours and hourly `trend.get` aggregates for 7/30
  days, with a bounded raw-history fallback, min/average/max/latest summary and
  a searchable metric picker. Zabbix 5.4/6.0 legacy and 6.4+ Bearer-style
  authentication are selected from the unauthenticated API version probe.
- In-app bilingual guidance for creating a dedicated Zabbix User role, granting
  host-group Read access and allowing only `host.get`, `item.get`,
  `history.get` and `trend.get`. Saved server profiles keep their tokens in
  platform secure storage.
- Zabbix profiles can select HTTPS or HTTP and specify a custom port separately
  from the host/path. HTTPS remains the default; cleartext HTTP is labelled in
  saved profiles and shows a persistent token-exposure warning.
- Saved Wi-Fi and LTE sessions can now be linked to a Zabbix host and a checked
  semantic mapping of signal, CPU, latency, loss, traffic or client-count
  items. Opening the session requests Zabbix values for the same time window
  and shows local and remote tracks on one synchronized timeline with a shared
  cursor and separate honest Y scales. A combined long-form CSV can be shared.
  Mapping metadata contains no token; external points are read on demand and
  are never silently copied into the local SQLite histories.
- **Keenetic Wi-Fi integration (Alpha)** over HTTPS RCI. The first compatibility
  baseline is Runner 4G (KN-2212) with KeeneticOS 5.01.C.3.0-1 and provides the
  current phone's AP-side RSSI, PHY rates and association facts alongside the
  existing phone metrics, plus router model/version/CPU/uptime. Other Keenetic
  models and releases are intentionally shown as unverified. Thanks to Netspay
  for providing the test hardware.
- LTE connection profiles now keep several routers in secure platform storage.
  The connection screen lets the operator select or forget one router, and
  transparently migrates the previous single-profile format.
- **Read-only LTE configuration audit** with role-aware advice for a primary,
  backup, passthrough or monitoring-only link. It checks the selected
  interface, referenced APN profiles, registration, network-vs-manual APN,
  PAP/CHAP mode, route distance, peer DNS, IPv4/IPv6 PDN type, IPv6 firewall
  presence, MTU, roaming, driver/network mode and native band/operator locks.
  Passed checks, compatibility notes, MikroTik documentation links and a
  dedicated PDF export are included.
- **F-Droid/Fastlane store metadata** in English and Russian, with the app icon,
  redacted screenshots and version-specific release notes. The listing remains
  maintained and versioned beside the source code without adding signing keys
  or a Fastlane runtime dependency.

### Changed
- Wi-Fi monitoring now offers Fast, Normal, Economical and Custom polling
  profiles. Live signal/ping, router health/CPU and IP-to-MAC discovery have
  independent intervals; the latter two are cached instead of being requested
  on every signal sample. A network/BSSID change invalidates client discovery
  immediately, and the BSSID-owning/serving router is queried first.
- Live Wi-Fi polling and ping pause while the app is in the background and
  resume with an immediate fresh sample. This avoids invisible router traffic
  and stale throughput spikes without weakening roaming detection while the app
  is on screen.
- New Wi-Fi recordings remember the serving router address and open as detailed
  sessions with signal, SNR and client-traffic timelines. Existing databases
  migrate in place; old sessions remain readable and can use a per-session
  Zabbix link.

### Removed
- Removed the unused `cupertino_icons` direct dependency and the unused GitHub
  issues URL constant. This does not change the application UI or behaviour.

### Security
- Port-knocking sequences are stored only inside the existing platform-secure
  router profiles, concealed by default in the UI and excluded from support
  reports and transport events. Knocking requires one explicitly selected
  transport, so it cannot fan out into REST/API/SSH probing. The app sends only
  the configured TCP/UDP packets and never creates or changes RouterOS firewall
  rules; an existing rule may temporarily place the device IP in a dynamic
  address list as the intended network-side effect.
- SSH connections now use trust on first use (TOFU). The key is remembered in
  platform secure storage only after authentication and a successful read-only
  identity probe. If the same host later presents another key, Wi-Fi and LTE
  connections stop and show the previous/new fingerprints; replacing the saved
  key requires an explicit user action.
- Self-signed TLS certificates on MikroTik REST/API remain accepted by design
  for typical private-LAN installations. This exception does not apply to
  Zabbix or Keenetic HTTPS.
- The Zabbix client has a compiled read-only JSON-RPC allowlist and no public
  generic call. It never creates users/tokens, changes monitoring objects or
  acknowledges problems. HTTPS uses normal certificate validation. Explicitly
  selected HTTP is unencrypted and therefore warns that the token and metrics
  are exposed in transit; it is intended only for a trusted LAN/VPN. Tokens are
  excluded from logs and support bundles. Forgetting a profile only removes its
  local secure-storage copy and explicitly does not claim to revoke the
  server-side token.
- The Keenetic client exposes no generic RCI command method. Its only POST is
  the required x-ndw2 `/auth` exchange; all diagnostic reads are limited to a
  compiled whitelist of five `GET /rci/show/...` paths. Credentials remain in
  secure platform storage, and association/DHCP rows are filtered in memory to
  the exact requested MAC/IP.
- LTE audit menu reads use explicit field projections. SIM PIN, APN username
  and password, `modem-init`, IMEI, IMSI and ICCID are never requested. The
  audit does not run `at-chat`, scan, cell-monitor or any write-capable command.
### Fixed
- Wi-Fi and LTE controllers now expose an idempotent, awaitable shutdown path.
  It stops timers and new work, waits for in-flight connect/poll operations,
  then independently closes ping/audio, RouterOS sessions and SQLite stores.
  Synchronous Flutter `dispose()` starts that same guarded Future, so cleanup
  errors are observed and one failed resource cannot prevent the others from
  closing.
- Wi-Fi measurement history now serialises concurrent SQLite opening, retries
  cleanly after an opening failure, deletes related session rows atomically and
  closes its database when the monitoring controller is disposed. Its existing
  database schema and recorded sessions remain compatible.
- Every full-screen view and modal detail sheet now follows one shared bottom
  safe-area policy. Long lists, cards and action buttons remain fully scrollable
  above Android gesture navigation and Samsung three-button navigation.
- LTE configuration audit over SSH now falls back to plain `print` for the two
  explicitly safe singleton menus `/system/resource` and
  `/interface/lte/settings` when that RouterOS build rejects
  `terse/proplist`. The complete output is immediately projected locally.
- LTE interface identity is read separately from model/version-dependent
  properties. A failed optional projection can no longer turn an already
  selected and monitored `lte1` into the false critical finding “Selected LTE
  interface is unavailable”; dependent checks are marked incomplete instead.
- An initial zero-filled `monitor once` response, seen on some SSH/modem
  combinations, is no longer treated as a real LTE measurement. The dashboard
  shows a bilingual loading/status card and keeps polling until plausible radio
  metrics arrive; an explicit not-registered/searching modem state is still
  reported immediately.
- PDF titles now match Wi-Fi, system, phone and LTE audit types; long location
  labels in shared audit cards are width-bounded on narrow screens.

## [0.3.2] - 2026-08-08

### Added
- **Read-only RouterOS Wi-Fi event analysis** for the current phone or any
  currently-associated device selected from the Devices screen. It recognizes
  client connect/disconnect and association attempts, access-list rejects,
  authentication/key-exchange failures, weak-signal policies, extensive radio
  loss, DFS radar events and CAP/CAPsMAN control-path failures.
- **Measured reconnect and roaming gaps** from RouterOS log timestamps, with
  confirmed/likely/context confidence labels and bilingual explanations.

### Security
- Log analysis requests only `time`, `topics` and `message`, examines at most
  the newest 2,000 rows per router, retains normalized events only and never
  stores raw logs or unrelated client MAC addresses. The app only reads
  `/system/logging`; it never enables debug topics or changes the router.
- REST, binary API and SSH share the same analysis. Transport selection remains
  automatic; binary/REST use field projection and SSH projects locally.

### Changed
- macOS builds now show a persistent `macOS ALPHA` badge in the title bar and
  About dialog, with a concise explanation of the desktop preview limitations.

### Fixed
- macOS Wi-Fi discovery calls are now time-bounded and avoid the plugin's
  synchronous gateway lookup, so a stalled local-adapter query cannot freeze
  the initial monitoring screen.
- macOS no longer launches `ping` subprocesses for the optional gateway metric.
  This preserves the client-only app sandbox and prevents orphaned high-CPU
  processes after the app exits. Other platforms explicitly stop each ping on
  completion, timeout, disconnect and controller disposal.

## [0.3.1] - 2026-08-07

### Added
- **Initial macOS target** with the proper Wi-Fi Signal Tester product name,
  app sandboxing and outgoing/local-network access needed to read explicitly
  configured MikroTik routers. RouterOS audits and LTE diagnostics share the
  existing read-only transports. Android-only RSSI and permission plugins are
  skipped cleanly; native Mac Wi-Fi RSSI remains a tracked follow-up.
- **GitHub macOS build**: pushes and pull requests now build an Apple-silicon
  `.app` on GitHub's macOS runner and retain it as a ZIP artifact. A successful
  push/manual run for a new version publishes that ZIP beside the Android APK
  in the same GitHub Release.
- **Persistent LTE measurement history**: the LTE dashboard can record every
  poll into a local, named session. Sessions show RSRP/RSRQ/SINR/RSSI/CQI
  min/average/max/spread, radio/cell facts, can be renamed or exported as CSV,
  and two recordings can be selected for an A/B comparison. IMEI, IMSI and
  ICCID remain outside the data model and are never stored.
- **Scalable LTE charts** on the dashboard, in the antenna-alignment assistant
  and in saved sessions. At 1× the full series fits; use −/+, the 1×…20× slider
  or a two-finger pinch to zoom, then pan horizontally through individual
  measurements.
- **LTE Quality Score (0–100)** adds one plain-language “higher is better” line
  above the technical LTE charts. The shared formula combines RSRP, RSRQ, SINR
  and optional CQI, changes emphasis under weak coverage, penalises unstable
  peaks and resets smoothing after a band/cell handoff. Current/best values,
  coloured quality zones, raw-metric tap details and saved-session P10/A/B
  comparisons are included. It is explicitly a radio score, not a speed test.

## [0.3.0] - 2026-08-07

### Added
- **Guided LTE antenna alignment assistant** with separate live RSRP, RSRQ and
  SINR charts. The operator records a stable baseline, moves the dish by one
  repeatable physical step and confirms each position; the app samples six
  fresh values, scores the checkpoint, suggests the next relative move and
  remembers how to return to the best position. It marks band/cell handoffs,
  penalises unstable peaks and offers a second fine pass after finding a local
  optimum. No router setting is changed: it only repeats the existing
  `/interface/lte/monitor ... once` read.
- **Focused Wi-Fi connection diagnosis** can now be started manually from the
  dashboard. Each run clears the old measurement window, collects six fresh
  samples for the current access point, then freezes the verdict together with
  the AP name and completion time. A pending or active run can be started
  immediately, repeated or cancelled.
- **Separate LTE signal diagnostics** from ⋮ → LTE diagnostics. It connects to
  a MikroTik over REST, the binary API or the read-only SSH transport; Auto
  tries them in that order. It auto-selects an enabled LTE interface and polls
  `monitor once` for RSRP, RSRQ, SINR and optional RSSI/CQI.
  The screen shows the operator/modem, LTE band, bandwidth, EARFCN, PCI/cell,
  recent min/average/max stability, and a plain-language diagnosis that
  distinguishes weak-but-clean coverage from interference/sector load.
  R11e-LTE and FG621-EA output formats are covered. IMEI, IMSI and ICCID are
  deliberately discarded immediately and are never stored or displayed.

### Changed
- The LTE connection form now has the same transport, TLS and custom-port
  controls as Wi-Fi monitoring and shows the transport actually selected.
  Existing SSH-only LTE profiles migrate as SSH profiles, so saved port 22/2222
  settings are not reinterpreted as REST or API settings.
- Automatic connection diagnosis no longer samples the unstable handoff
  itself. After connecting or roaming it waits for the radio link to settle;
  automatic runs can be disabled and the delay can be set from 0 to 30 seconds
  in Settings → Connection diagnosis. The default delay is 10 seconds.

### Fixed
- Long access-point names in the latest-roam display are now width-bounded and
  rendered as a dedicated responsive transition instead of overflowing the
  router-health card.
- LTE verdict text and colour now come from the same complete classification:
  a weak-but-usable `−108 dBm / 7 dB SINR` link is amber and explicitly says
  that LTE works with weak power, while red is reserved for genuinely critical
  radio conditions. The verdict includes an explicit Good/Attention/Poor badge.

## [0.2.5] - 2026-08-06

### Added
- **Support diagnostics** from ⋮ → Support report: a user-triggered ZIP with a
  readable `report.txt`, structured `report.json`, a bounded in-memory
  `events.log` and a privacy note. It contains app/device state, current
  two-sided measurements, link-diagnosis facts, router health and controlled
  connection events — never credentials, private keys, raw RouterOS responses
  or full client lists. SSID/BSSID/MAC/IP/router and AP names are masked by
  default and can be included only with an explicit switch. Nothing is uploaded
  automatically.
- **Typed bilingual failure banners** with stable support codes and relevant
  actions for authentication, permissions, timeout, refused/unreachable host,
  TLS, closed session, off-Wi-Fi and missing-station cases.

### Fixed
- The binary RouterOS API now serialises reads and reconnects once after its
  long-lived socket dies while Android is in the background, replaying login
  before retrying the same read-only command. Reconnect attempts and outcomes
  are recorded in the support event log.

### Changed
- A push or merge to `main` now builds the APK, derives `vX.Y.Z` from `VERSION`
  and publishes the GitHub Release automatically. Manual tag creation is no
  longer required; pull requests still run analysis/tests/build without
  publishing a release.

## [0.2.4] - 2026-08-06

### Added
- **Smart link diagnosis** correlates phone/AP RSSI and SNR, CCQ, negotiated
  rates, MikroTik `p-throughput`, gateway ping/loss and router CPU over a
  stable rolling window. The dashboard shows a plain-language verdict; tapping
  it opens the observed facts, likely causes and concrete checks in English or
  Russian. Samples reset on AP changes, and causes are explicitly presented as
  probabilities rather than proven facts.

### Changed
- GitHub Actions now builds and uploads a release APK artifact on every push to
  `main`, on pull requests to `main`, and on manual runs. A `v*` tag is only
  needed when the same APK should also be published as a GitHub Release.

## [0.2.3] - 2026-08-05

### Added
- **MikroTik hardening audit** now checks MAC Telnet/WinBox/Ping, Neighbor
  Discovery, Bandwidth Test Server and its authentication, DNS client requests,
  proxy, SOCKS, UPnP, MikroTik Cloud and SSH strong crypto. Applicable findings
  link directly to the relevant official MikroTik recommendation in both the UI
  and exported PDF.
- Separate IPv4 and IPv6 firewall-presence checks. They deliberately report only
  whether active filter rules exist; rule order, coverage and effectiveness are
  not inferred.

### Changed
- The connected-device list now uses operator-authored access-list comments
  (legacy CAPsMAN, classic wireless and WifiWave2), then DHCP comments and DHCP
  hostnames. Device details show every source separately, and search covers all
  of them. Only currently associated stations are still listed.
- Management-service findings now report only facts visible in `/ip service`,
  including its own `address` restriction. The audit no longer claims that a
  service is exposed based on a simplified firewall interpretation. Queue and
  FastTrack analysis are explicitly outside the audit scope.

## [0.2.2] - 2026-08-01

### Added
- **SSH transport** — a third way into RouterOS, next to REST and the binary API:
  the app runs console reads over SSH. It is the rescue path for routers where
  REST doesn't exist (RouterOS 6) and the API service is switched off, and needs
  nothing enabled beyond the `ssh` policy on the read-only user. `Auto` now tries
  REST → API → SSH; the connection form gained an **SSH** option and an optional
  **Port** field.
  - Still read-only, enforced in code because a console *could* write: commands
    are composed by the app from a menu path plus a fixed verb, only `print` and
    `monitor once` pass the whitelist, console metacharacters are refused, and
    `monitor` without `once` is rejected.
  - Console output is normalised back into the rows REST returns: unquoted terse
    values with spaces, `print stats` for the runtime numbers registration tables
    hide from `print terse`, aligned `label: value` blocks for single-record
    menus, flag letters → `disabled`/`dynamic`/`running`, and `yes`/`no` →
    `true`/`false`. Verified by running the full audit over REST and over SSH
    against the same router: 16 findings each, identical.
  - Measured on a hAP ac³: connect ~0.9 s, poll ~124 ms (REST ~0.4 s / ~62 ms).
- **User guide** — [docs/usage.md](docs/usage.md) and
  [docs/usage.ru.md](docs/usage.ru.md): router preparation, connecting, reading
  both sides and the Δ badge, what good numbers look like, typical jobs, audits,
  history, targets/alerts, settings, and a troubleshooting table. Linked from
  both READMEs.
- **Links to the project in-app**: About now has a PROJECT block (GitHub, the
  usage guide in the UI language, latest release), the Reference screen has a
  guide button, and ⋮ gained *How to use (GitHub)*. Tapping opens a browser;
  long-press copies the URL, and if no browser answers the link is copied instead.

### Fixed
- **System audit now sees management services on non-standard ports.** FTP,
  Telnet, plain HTTP/WebFig, SSH, WinBox and both APIs are audited by service
  state rather than by matching their default port; findings show the actual
  port, and unrestricted custom-port services are still checked against the
  input firewall. Plain `www` and the unencrypted binary `api` are now called
  out alongside FTP/Telnet.
- **The audit no longer draws conclusions from data it couldn't read.** Found on
  a real device: after the app had been in the background the SSH session was
  gone, every menu read failed, and the report cheerfully announced "No input
  firewall" on a router with a default-deny chain. Now a failed read is *unknown*
  rather than *empty* — the checks that infer absence are skipped, a "Report
  incomplete: N menu(s) unreadable" warning names them, and if nothing at all can
  be read the audit reports that instead of producing a report.
- **The SSH transport reconnects once** when the session died between commands
  (Android suspends sockets in the background; RouterOS drops idle sessions).
  Before this, everything after a resume failed silently.
- Editing a saved router in the connection form and pressing *Connect* now uses
  what's in the fields; previously the saved entry with the same host won, so a
  changed transport or password was quietly ignored.

### Changed
- Android now uses a verified least-privilege manifest: transitive
  `CHANGE_WIFI_STATE`, `CHANGE_NETWORK_STATE` and `WRITE_SETTINGS` permissions
  are rejected, the unused `NEARBY_WIFI_DEVICES` declaration is gone, and the
  launcher/system label is now **Wi-Fi Signal Tester** instead of `wifi_apk`.
- The audit treats a CAPsMAN interface as on-air when `current-state` says
  `running-…`, not only when `running=true` — the two transports report that
  state differently, and the verdict must not depend on how we connected.
- Android Gradle plugin 8.7.3 → 8.9.1 (`url_launcher` pulls androidx.browser 1.9
  / core 1.17, which refuse anything older). AGP 9.x still breaks Flutter 3.44.

## [0.2.1] - 2026-07-26

### Added
- **Targets for signal and SNR** (Settings → Targets) and a dashboard strip that
  reads "All metrics within target" or lists what's out of spec. Alerts now beep
  for any breach — phone/AP signal, phone/AP SNR or asymmetry — not just
  asymmetry, completing the threshold-alerts feature.

### Changed
- The router audit is split into **Wi-Fi audit** and **System audit** (two menu
  entries), so RF checks and health/hardening checks are separate reports.
- The default-`admin` check now reports OK when the account is disabled, and
  when it's active advises changing its password (rename/disable).

### Added
- A "What this app is for" intro at the top of the Reference.
- **Audit expansion — router health & hardening** (beyond Wi-Fi): NTP time sync,
  RouterOS update available, FTP/Telnet enabled, management services open to any
  IP, default `admin` user, input firewall present, and IP-pool exhaustion —
  each read-only, with plain explanations and fixes.
- **Scan-throttling tip** in the Reference: Android limits Wi-Fi scan frequency;
  how to disable it in Developer options.
- **Ping / latency to the gateway** on the dashboard — a real ICMP round-trip
  measured over Wi-Fi each poll (colour-coded, with a reference entry). Latency
  spikes or loss under a strong signal flag interference / a busy AP.
- **Inspect any device** (⋮ → Devices): pick a device from the routers' DHCP
  leases (by IP / name / MAC) and see how the APs hear it — signal, AP, rates,
  uptime. Great for checking a TV, laptop or a neighbour's phone.
- **Open-source licenses** page (About → Licenses) listing all bundled
  components; the bundled Noto Sans font's OFL licence is registered.
- "Built with AI" note in About and the READMEs.
- A small easter egg (tap the version in About seven times).
- **Phone-only mode** — "Just view my network (no router)" on the connection
  form shows the device's own Wi-Fi (SSID, band, channel, signal, link speed,
  standard, security) without connecting to any MikroTik.
- **Phone-side audit** — audits the connection from what the phone reports:
  signal strength, band, 2.4 GHz channel (1/6/11), security (open/WEP → flagged),
  Wi-Fi generation, and link-rate-vs-signal. Shareable as PDF.
- Richer phone facts via a native WifiManager channel: negotiated/tx/rx link
  speed, 802.11 generation (Wi-Fi 4/5/6/7), and security type.
- **In-app changelog** (⋮ → Changelog): browsable, bilingual release notes.
- **"What's new" popup**: after an app update, the new version's highlights are
  shown once at startup (skipped on a fresh install).

## [0.2.0] - 2026-07-24

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

### Added
- **Router health on the dashboard**: CPU load (colour-coded), board, RouterOS
  version and uptime for the serving router, plus a roam counter (how many times
  the client switched AP this session, with the last transition).
- **Audit now shows passed checks and policies**, not just problems — so a
  healthy router gets a substantive report: router info (board/version/CPU/
  uptime), clean 2.4 GHz channel plan (20 MHz on 1/6/11), country set, TX power
  at default, WPA2/WPA3, client isolation, and sticky-client mitigation
  (signal-range access rules that push weak clients to roam). "Issues" now
  counts only critical/warnings.

### Fixed
- REST transport now handles single-object responses (e.g. /system/resource),
  not just arrays — CPU/health and the audit's router info were coming back empty.

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

[Unreleased]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.2.5...v0.3.0
[0.2.5]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/SlipKo89/wifi-signal-tester/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/SlipKo89/wifi-signal-tester/releases/tag/v0.1.0
