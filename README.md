# Wi-Fi Signal Tester for MikroTik + Keenetic Alpha

*Русская версия — [README.ru.md](README.ru.md)*

A Flutter app (Android plus an initial macOS target, iOS later) for **testing
Wi-Fi from both sides**.
Regular analyzers show only how your phone hears the access point. For real
site-survey work you also need to know **how the access point hears your
device** — signal, SNR, rates. This app reads that from a MikroTik (running
CAPsMAN or plain Wi-Fi), or from the initial Keenetic integration, **read-only**,
for **your device's MAC only**, and puts it next to your phone's own readings.

Keenetic support is explicitly **Alpha**. Its current compatibility baseline is
**Runner 4G (KN-2212), KeeneticOS 5.01.C.3.0-1**; other models and releases may
use different RCI fields and must be verified separately. Thanks to **Netspay**
for providing the Keenetic test hardware.

The app also contains a **separate LTE diagnostics and antenna-alignment tool**
for MikroTik LTE routers. It reads modem radio quality over REST, the binary API
or SSH and does not depend on or mix with the Wi-Fi dashboard.

<table>
<tr>
<td width="33%"><img src="docs/screenshots/dashboard.png" alt="Two-sided dashboard"></td>
<td width="33%"><img src="docs/screenshots/audit.png" alt="Wi-Fi audit"></td>
<td width="33%"><img src="docs/screenshots/devices.png" alt="Devices on Wi-Fi"></td>
</tr>
<tr>
<td align="center"><b>Both sides at once</b><br/>the phone hears the AP at −48 dBm, the AP hears the phone at −45 dBm</td>
<td align="center"><b>Read-only audit</b><br/>Wi-Fi and system checks with plain-language fixes, exportable to PDF</td>
<td align="center"><b>Any device on Wi-Fi</b><br/>see how the APs hear a TV, laptop or a guest's phone</td>
</tr>
</table>

## Download

Grab the latest build from the [Releases page](../../releases/latest):

- Android: `wifi-signal-tester-<version>.apk`;
- Apple-silicon Mac (**Alpha**): `wifi-signal-tester-<version>-macos-arm64.zip` — unpack it
  to get `Wi-Fi Signal Tester.app`.

Optional Alpha/Beta builds are listed separately under
[all releases](../../releases).

Every push/merge to `main` builds both platforms, creates the `v<version>` tag
from `VERSION` and publishes one GitHub Release automatically. Both files are
also available from that workflow run under
[Actions](../../actions/workflows/release.yml) → *Artifacts*. Do not create
release tags manually; bump the app version before the merge instead.

Release channels are encoded in `VERSION`:

- `X.Y.Z` — stable; GitHub marks it as the latest release;
- `X.Y.Za` — Alpha pre-release;
- `X.Y.Zb` — Beta pre-release.

Alpha and Beta builds remain downloadable from the Releases page and workflow
artifacts, but never move the `releases/latest` link away from the newest stable
version. Dart package metadata uses the equivalent valid SemVer suffixes
`-alpha` and `-beta`; the app and GitHub tag keep the compact `a`/`b` spelling.

The Mac app is explicitly marked **Alpha** in its title bar and About dialog.
The ZIP is currently an ad-hoc-signed test build, so Gatekeeper can warn
when it is opened on another Mac. Developer ID signing and Apple notarization
remain a separate distribution step.

## How to use it

**[docs/usage.md](docs/usage.md)** is the user guide: preparing the router,
connecting, reading the two sides and the Δ badge, running the audits, recording
a walk-around survey, targets and alerts, and a troubleshooting table. The same
guide is reachable in-app from ⋮ → *How to use* and from the Reference screen.

## Features

- **Separate field tools**: a mode screen opens MikroTik Wi-Fi, MikroTik LTE or
  Keenetic Wi-Fi Alpha. MikroTik Wi-Fi profiles are grouped into named sites,
  each with its own multi-router/AP set; one-off connections can stay unsaved.
- **Two-sided view**: phone RSSI vs. the AP's signal for your station, plus the
  delta between them.
- **From MikroTik**: `signal-strength` (dBm), `signal-to-noise` (SNR),
  tx/rx-rate, per-MIMO-chain signal, CCQ.
- **Keenetic Alpha over HTTPS RCI**: AP-side RSSI, tx/rx PHY rates, interface,
  association time, Wi-Fi mode, channel width, MCS/NSS, security and PMF, plus
  router model, KeeneticOS version, CPU and uptime. Developed and verified on
  Runner 4G (KN-2212) with KeeneticOS 5.01.C.3.0-1.
- **Auto everything**: detects the wireless stack (WifiWave2 / CAPsMAN new /
  CAPsMAN legacy / classic) and the transport (REST → binary API → SSH).
- **Three ways in**: REST (RouterOS 7.1+), the binary API (6 & 7) and the
  RouterOS **SSH console** — for routers where REST doesn't exist and the API
  service is off. SSH runs only `print` / `monitor once`.
- **Optional MikroTik port knocking**: a Wi-Fi or LTE profile can send a fixed
  1–8 step TCP/UDP sequence before opening one explicitly selected REST, API or
  SSH service. The app does not configure the router or scan other ports.
- **Randomized-MAC safe**: finds your station by IP→MAC via ARP/DHCP, so
  Android 10+ MAC randomization doesn't break it.
- **Read-only & scoped**: only `print`/`GET`, only your MAC.
- **Live**: the Normal profile samples signal/ping every ~2 s, but caches
  IP→MAC discovery and reads router health less often. Fast, Economical and
  fully Custom profiles are available; background polling pauses automatically.
- **Focused link diagnosis**: run a fixed six-sample check manually, or let it
  start automatically after a configurable post-roam settling delay. The result
  is frozen for the current AP with likely causes and practical advice.
- **Editable Wi-Fi floor surveys**: start from a metric grid or an
  imported plan/photo, trace snap-to-grid walls, doors and windows with material
  metadata, then create dated/named sessions and place measurement points. Each
  pin averages fresh Phone/AP RSSI and SNR readings; four selectable local
  heatmap layers leave unmeasured space unknown. Optional GPS is off by default.
- **Phone ↔ desktop map transfer**: export or import one versioned `.wifimap`
  package containing editable geometry, materials, measurements and an optional
  background. GPS is opt-in; credentials and connection profiles are excluded.
- **RouterOS Wi-Fi event analysis**: read the latest wireless/CAPsMAN logs for
  the current phone or a selected associated device, explain disconnect and
  authentication reasons, and measure reconnect/roaming gaps. It works through
  REST, binary API or SSH without changing the router; raw logs and unrelated
  client MACs are not retained.
- **Support report**: creates a ZIP only when you ask, with current diagnostics
  and a bounded event log. Network identifiers are masked by default;
  credentials and raw router responses are never included or uploaded.
- **Separate LTE diagnostics**: read-only REST / binary API / SSH polling of
  RSRP, RSRQ, SINR, optional RSSI/CQI, band and serving-cell facts, stability
  and practical antenna/interference advice. Auto tries REST → API → SSH; no
  Wi-Fi connection is required for this mode. Several LTE routers can be saved
  in secure platform storage and selected from the connection screen.
- **LTE configuration audit**: checks interface/APN consistency, registration,
  manual-vs-network APN compatibility, route role, passthrough, IPv4/IPv6, MTU,
  roaming and radio restrictions, with passed checks, official MikroTik links
  and PDF export. It never reads SIM/APN secrets or runs active modem commands.
- **Guided LTE antenna alignment**: record stable checkpoints while moving the
  dish in repeatable steps. The assistant combines signal power, quality and
  stability, proposes the next move and tells you how to return to the best
  measured position before a finer pass.
- **Persistent LTE history and A/B comparison**: record named sessions locally,
  inspect scalable 1×…20× radio charts and min/average/max/spread, compare two
  visits or antenna positions, and export the raw samples as CSV.
- **One understandable LTE score**: a 0–100 “higher is better” line combines
  power, quality and stability, shows the current and best result, and keeps
  the raw radio charts one tap away. It grades the radio link, not Internet speed.
- **Optional Zabbix history**: connect with a user-supplied read-only API token,
  choose any readable host and numeric item, then inspect raw 1h/24h history or
  hourly 7d/30d trends. The searchable picker and min/average/max/latest summary
  work with custom templates without assuming their item keys. HTTPS/HTTP and a
  custom port are selectable; cleartext HTTP carries an explicit warning.
  Saved Wi-Fi/LTE sessions can also link a Zabbix host/items and compare local
  and remote tracks over the same time range, with a combined CSV export.

## Requirements (build machine — macOS)

Android builds need Flutter, JDK 17 and the Android SDK. Native Mac builds need
Flutter, the full Xcode application and CocoaPods. Xcode Command Line Tools
alone are not enough.

```bash
# 1) JDK 17 (the bundled Java 8 is too old for the Android toolchain)
brew install --cask temurin@17

# 2) Flutter SDK (brings Dart with it)
brew install --cask flutter

# 3) Android SDK + platform tools (Android Studio is the simplest source)
brew install --cask android-studio
#    then launch Android Studio once → it installs the SDK, or use the SDK Manager

# 4) Point tooling at the JDK and accept Android licenses
flutter config --jdk-dir "$(/usr/libexec/java_home -v 17)"
flutter doctor --android-licenses

# 5) For the macOS app (install Xcode from the App Store first)
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
brew install cocoapods

flutter doctor              # fix anything still flagged
```

> Prefer no Android Studio? Install just the command-line tools with
> `brew install --cask android-commandlinetools` and run
> `sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"`.

## Build & run

```bash
cd wifi-apk
./scripts/bootstrap.sh        # generates platform runners, runs flutter pub get

# add permissions once — see docs/android-setup.md

flutter run                   # on a connected phone (USB debugging on)
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk

flutter run -d macos          # run the desktop app
flutter build macos --release # → build/macos/Build/Products/Release/
```

Copy that `.apk` to your Android device to install it.

The macOS **Alpha** supports RouterOS connection, audits and LTE tools. The
current Android-only `wifi_iot` plugin cannot provide the Mac's local RSSI and
frequency yet; a native CoreWLAN implementation is tracked in TODO. The Mac
build also avoids spawning a sandboxed system `ping`, so gateway latency is
currently Android-only. A locally built `.app` is suitable for testing.
Distribution to other Macs additionally requires Developer ID signing and
Apple notarization.

## Router side

For **Keenetic Alpha**, select its dedicated mode and enter either
the router address or its KeenDNS HTTPS hostname. The app uses Keenetic's
challenge-response HTTPS RCI login and then only fixed `GET /rci/show/...`
endpoints. It does not expose generic RCI calls. This first integration covers
the two-sided dashboard for the current phone; Keenetic audits, logs and the
third-party device screen remain future work.

For **MikroTik**, create a read-only user and enable the API/REST service — full
steps in [docs/mikrotik-readonly-user.md](docs/mikrotik-readonly-user.md). Short
version:

```
/user group add name=monitor policy=read,api,rest-api,ssh,winbox,test
/user add name=monitor group=monitor password=CHANGE_ME
/ip service enable www-ssl     # for REST
/ip service enable api         # for binary API
                               # SSH needs nothing beyond the `ssh` policy
```

## How it works

See [docs/architecture.md](docs/architecture.md). In one line: read the phone's
IP → map IP→MAC on the router via ARP/DHCP → read the registration table for
that MAC → show both sides side by side.

## Security — read-only on **both** sides

- **Router:** no configuration write path exists in the code. MikroTik
  transports expose menu reads plus a fixed whitelist of wireless/Wi-Fi/LTE `monitor once`
  commands. REST, API and SSH all pass through that gate. Pair it with a
  read-only RouterOS user so writes are impossible even in principle. SSH also
  rejects console metacharacters and every verb except `print`/`monitor once`.
  Keenetic uses one POST solely for x-ndw2 authentication and permits data reads
  only from a compiled whitelist of five `GET /rci/show/...` paths; no generic
  RCI command method exists.
- **Device:** the app only reads the Wi-Fi chip (RSSI, SSID, frequency). It never
  changes, connects, disconnects or forgets any network. The manifest explicitly
  rejects `CHANGE_WIFI_STATE`, `CHANGE_NETWORK_STATE` and `WRITE_SETTINGS`; it
  does not access contacts and uses a system picker instead of broad media
  access. It stores only its own data: router credentials in the Keystore,
  settings, measurement history, selected floor-plan copies, and a temporary
  support ZIP when the user explicitly creates one.
- Credentials are stored in the Android Keystore / iOS Keychain, never in plain
  preferences.
- Port-knocking sequences share that secure profile storage, stay concealed by
  default and are excluded from support archives. Their only network-side
  effect is the one intended by existing router firewall rules (usually a
  temporary dynamic address-list entry); the app never creates those rules.
- Zabbix access has a separate compiled allowlist containing only
  `host.get`, `item.get`, `history.get` and `trend.get`. Its token also lives in
  secure storage; the app never creates or changes Zabbix objects. HTTPS is the
  validated default. Explicit HTTP is unencrypted and should be used only over
  a trusted LAN/VPN. Setup:
  [docs/zabbix-readonly-user.md](docs/zabbix-readonly-user.md).
- MikroTik REST/API deliberately accepts self-signed TLS certificates because
  they are common on private RouterOS installations. Use those transports only
  on a trusted LAN/VPN: encryption is present, but certificate identity is not
  validated. SSH is stricter: the app remembers the first successful host key
  and blocks with old/new fingerprints if it changes. When HTTPS is selected,
  Zabbix and Keenetic must present certificates trusted by the device.

## Project docs

- [docs/usage.md](docs/usage.md) — **user guide** (RU: [usage.ru.md](docs/usage.ru.md))
- [docs/zabbix-readonly-user.md](docs/zabbix-readonly-user.md) — least-privilege
  Zabbix user, role and API-token setup
- [CHANGELOG.md](CHANGELOG.md) — versioned history (SemVer)
- [TODO.md](TODO.md) — backlog / roadmap
- [docs/](docs/) — architecture, MikroTik & Android setup

## Built with AI

This app — code, documentation and design — was built with Claude (an AI) by
Anthropic, working alongside the author.

## License

[MIT](LICENSE) © 2026 SlipKo

Open-source components are listed in-app under About → Licenses.
