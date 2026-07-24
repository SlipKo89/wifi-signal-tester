# TODO / Backlog

Legend: `[ ]` planned · `[~]` in progress · `[x]` done · `(vX.Y)` target version

## MVP (v0.1.x)
- [x] Project scaffold, versioning, changelog, bilingual README
- [x] Read-only MikroTik client (REST + binary API) behind one interface
- [x] Wireless-stack autodetection
- [x] MAC resolution via ARP / DHCP lease (Android randomized-MAC workaround)
- [x] Phone-side signal service (RSSI / SSID / BSSID / IP / gateway)
- [x] Two-sided dashboard + live sparkline
- [x] Runtime location permission request (SSID/BSSID need it on Android 8+)
- [ ] Wire native RSSI reliability check on real devices (Android 13/14 perms)
- [x] Connection profiles: save/select multiple routers (multi-router support)
- [x] BSSID → AP identification across routers
- [ ] Graceful error banners for each failure mode (auth, timeout, no-station)

## Next (v0.2) — agreed with user ✅
- [ ] **Threshold alerts** — user-set targets (signal / SNR / delta); colour the
      dashboard good/warn/bad and vibrate+beep when a metric crosses the line,
      for hands-free walk testing
- [~] **Asymmetry diagnosis with advice** — turn the AP−phone delta into a
      verdict. Done: tap the Δ badge for explanation + rule-based advice.
      Left: fold in rate/CCQ ("strong signal but low rate → interference") and
      surface a short inline verdict without tapping

## Next (v0.2)
- [ ] Per-MIMO-chain view (signal-strength-ch0/ch1) with bar visualization
- [ ] Persistent measurement history — store each pass (timestamp, both-side
      signal/SNR/rates, SSID/BSSID) in a local DB (sqflite/drift), our own app
      data only. Session list, view past runs, clear, export CSV/JSON
- [ ] Roaming test mode: log signal vs timestamp while walking, export CSV
- [ ] Floor-map / heatmap capture (drop pins, record both-side signal)
- [ ] Multi-AP view when CAPsMAN reports the client on several radios
- [ ] Configurable poll interval and history length in settings
- [ ] Dark/light theme toggle

## Later (v0.3+)
- [ ] iOS build pass + platform-specific Wi-Fi permission flows
- [ ] Localization framework (proper i18n, not hardcoded RU/EN strings)
- [ ] Optional read-only user auto-check (warn if the API user has write policy)
- [ ] Speed/latency probe alongside signal (ping the gateway)
- [ ] App icon, splash, store listing assets

## Ideas parking lot (brainstormed, to triage later)

> Captured so nothing is lost. Not scheduled yet — pull items up into a version
> when we decide to build them.

### A. Squeeze more from data we already fetch
- [ ] Real noise-floor from `/interface/wireless/monitor` (and wifi equivalent)
      → honest SNR on both sides + on-channel interference level
- [ ] `p-throughput` (RouterOS's own estimated client throughput) as a headline
      metric — more honest than raw dBm
- [ ] Highlight signal↔rate/CCQ mismatch (strong signal but low rate = interference)
- [ ] Retransmit / frame-error rate from counters over time (link quality depth)

### B. New diagnostic features
- [ ] Pass/Fail site-survey mode driven by the thresholds above
- [ ] CAPsMAN roaming tracking — log which AP/radio the client sits on over time,
      catch sticky-client / handover issues
- [ ] Named measurement spots ("kitchen") with min/max/avg over a dwell window,
      compare spots
- [ ] Ping / latency probe to the gateway alongside signal (correlate signal↔lag)

### C. Bigger directions
- [ ] A/B before/after snapshots (channel / power / AP placement change) with diff
- [ ] Two-sided heatmap over a floor plan
- [ ] SSH as a third read-only transport (setups where only SSH is open)
- [ ] Exportable survey report (PDF/CSV with spots + verdicts) for clients

## Tech debt / risks
- [ ] Binary-API reader uses `List<int>` with O(n) removes — fine for tiny
      registration tables, revisit if we ever stream large menus
- [ ] Self-signed TLS is accepted by default (LAN assumption) — make it a
      user-visible toggle with a warning
- [ ] wifi_iot RSSI availability varies by OEM ROM — needs field testing
- [ ] AGP pinned to 8.7.3 / Gradle 8.11.1 — revisit once Flutter fully supports
      AGP 9 (default toolchain installs 9.0.1, which broke the build)
