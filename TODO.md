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
- [~] **Threshold alerts** — done: beep + vibrate when AP−phone asymmetry
      exceeds a configurable threshold (bell toggle + Settings). Left: alerts on
      signal/SNR thresholds too, and colour the dashboard good/warn/bad
- [~] **Asymmetry diagnosis with advice** — turn the AP−phone delta into a
      verdict. Done: tap the Δ badge for explanation + rule-based advice.
      Left: fold in rate/CCQ ("strong signal but low rate → interference") and
      surface a short inline verdict without tapping

## Next (v0.2)
- [ ] Per-MIMO-chain view (signal-strength-ch0/ch1) with bar visualization
- [x] Persistent measurement history — SQLite store, Record button, session
      list, CSV export (share), delete/clear
- [ ] Roaming test mode: log signal vs timestamp while walking (history covers
      the storage; left: dedicated walk UI + per-AP timeline)
- [ ] Floor-map / heatmap capture (drop pins, record both-side signal)
- [ ] Multi-AP view when CAPsMAN reports the client on several radios
- [x] Configurable poll interval and history length in settings
- [ ] Dark/light theme toggle (needs theme-aware colors across widgets)
- [x] Settings screen + language selection (RU/EN, lightweight i18n)
- [x] Live throughput, CCQ, p-throughput, uptime metrics

## v0.2 — added mid-cycle ✅
- [x] Config audit (read-only): audits operating state (current-channel) and
      applied configs only; inline+named security; RF best-practices with fixes
- [x] Audit: co-channel / non-1-6-11 check across a router's own APs
- [x] Reference / help for every metric (tap-a-number + Reference screen)
- [x] Audit: PDF export (NotoSans for Cyrillic)
- [x] Audit: show passed checks/policies (channel plan, country, TX, isolation,
      sticky-client, router info) — not just problems
- [x] Router health metric on dashboard (CPU / board / version / uptime)
- [x] Roam counter (AP switches this session)
- [ ] Audit: extend to WifiWave2 (/interface/wifi) config
- [ ] Audit: PMF/802.11w recommendation (careful — "required" drops old clients)
- [ ] Wireless log analysis — /log is often huge (12k+ entries) and wifi
      logging is off by default; needs a filtered/limited read + "enable
      topic wireless/caps" hint. Deferred
- [ ] Roaming handoff time (proper reconnect-speed measurement, not just count)
- [ ] Verify PDF export on a real device (built, not yet field-tested)
- [x] Phone-only mode + phone-side audit (native WifiManager facts)
- [x] Inspect third-party devices from DHCP leases (AP-side signal)
- [x] In-app changelog + "what's new on update"
- [x] Open-source licenses page + "built with AI" note + easter egg
- [ ] LTE mode for LHG LTE (RSRP/RSRQ/SINR alignment) — high value, next
- [ ] GPS-tagged samples for a coverage map (phase 1: record + CSV)

## Later (v0.3+)
- [ ] iOS build pass + platform-specific Wi-Fi permission flows
- [ ] Localization framework (proper i18n, not hardcoded RU/EN strings)
- [ ] Optional read-only user auto-check (warn if the API user has write policy)
- [ ] Speed/latency probe alongside signal (ping the gateway)
- [x] App icon (two-sided signal, SVG → adaptive/iOS)
- [ ] Splash screen + store listing assets

## Ideas parking lot (brainstormed, to triage later)

> Captured so nothing is lost. Not scheduled yet — pull items up into a version
> when we decide to build them.

### A. Squeeze more from data we already fetch
- [x] Real noise-floor from `/interface/wireless/monitor` (and wifi equivalent)
      → honest SNR on both sides (done as AP-side SNR estimate)
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
- [ ] Bump Kotlin from 2.1.0 (build warns it will be dropped; wants ≥2.2.20)
- [ ] Full i18n framework (gen-l10n/.arb) — currently a lightweight inline
      L10n.t table covers the main strings only
      