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
- [x] Graceful bilingual error banners for each failure mode (auth, access,
      timeout/refused/unreachable, TLS, closed session, off-Wi-Fi, no-station),
      with stable support codes, retry/edit actions and a support-report shortcut

## Next (v0.2) — agreed with user ✅
- [x] **Threshold alerts** — configurable targets for signal, SNR and asymmetry;
      beep + vibrate on any breach; dashboard pass/fail strip listing what's out
      of target
- [x] **Smart link diagnosis with advice** — inline verdict + detailed facts and
      suggestions from a stable window of RSSI/SNR, AP−phone delta, rate/CCQ,
      p-throughput, gateway ping/loss and router CPU

## Next (v0.2)
- [x] User-triggered support ZIP: readable + structured report, bounded
      in-memory event log, identifiers masked by default, secrets always removed
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
- [x] System audit: management services on standard and non-standard ports;
      actual port shown, plaintext FTP/Telnet/HTTP/API highlighted, and each
      service's own `address` restriction reported without guessing WAN
      exposure from firewall rules
- [x] System audit: MikroTik hardening baseline — RouterOS updates, default
      admin, MAC Telnet/WinBox/Ping, Neighbor Discovery, btest authentication,
      DNS cache, proxy/SOCKS/UPnP/Cloud and SSH strong crypto; every applicable
      finding links to the official MikroTik recommendation
- [x] System audit scope boundary: IPv4/IPv6 firewall checks presence only;
      firewall rule semantics and all Queue/FastTrack analysis are intentionally
      out of scope
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
- [x] Inspect currently associated third-party devices (AP-side signal),
      enriched with IP/hostname/DHCP comment and comments from legacy CAPsMAN,
      classic wireless and WifiWave2 access lists
- [x] In-app changelog + "what's new on update"
- [x] Open-source licenses page + "built with AI" note + easter egg
- [ ] LTE mode for LHG LTE (RSRP/RSRQ/SINR alignment) — high value, next
- [ ] GPS-tagged samples for a coverage map (phase 1: record + CSV)

## Docs & discoverability
- [x] User guide in both languages (docs/usage.md / usage.ru.md), linked from the
      READMEs and from inside the app
- [x] GitHub / guide / releases links in About, Reference and the ⋮ menu
- [x] Field-test the SSH transport on Android (emulator against a live hAP ac³:
      connect, poll, both audits, background/resume reconnect)
- [ ] Short screen-recording / GIF of a walk-around survey for the README

## Later (v0.3+)
- [ ] iOS build pass + platform-specific Wi-Fi permission flows
- [ ] Localization framework (proper i18n, not hardcoded RU/EN strings)
- [ ] Optional read-only user auto-check (warn if the API user has write policy)
- [x] Latency probe alongside signal (rolling gateway ping + loss)
- [x] App icon (two-sided signal, SVG → adaptive/iOS)
- [ ] Splash screen + store listing assets

## Ideas parking lot (brainstormed, to triage later)

> Captured so nothing is lost. Not scheduled yet — pull items up into a version
> when we decide to build them.

### A. Squeeze more from data we already fetch
- [x] Real noise-floor from `/interface/wireless/monitor` (and wifi equivalent)
      → honest SNR on both sides (done as AP-side SNR estimate)
- [x] `p-throughput` (RouterOS's own estimated client throughput) as a headline
      metric — more honest than raw dBm
- [x] Highlight signal↔rate/CCQ mismatch with a stable-window diagnosis and advice
- [ ] Retransmit / frame-error rate from counters over time (link quality depth)

### B. New diagnostic features
- [ ] Pass/Fail site-survey mode driven by the thresholds above
- [ ] CAPsMAN roaming tracking — log which AP/radio the client sits on over time,
      catch sticky-client / handover issues
- [ ] Named measurement spots ("kitchen") with min/max/avg over a dwell window,
      compare spots
- [x] Ping / latency probe to the gateway alongside signal (correlate signal↔lag)

### C. Bigger directions
- [ ] A/B before/after snapshots (channel / power / AP placement change) with diff
- [ ] Two-sided heatmap over a floor plan
- [x] SSH as a third read-only transport (setups where only SSH is open) —
      console reads with a `print`/`monitor once` whitelist; audit output
      verified identical to REST on a live router
- [ ] Exportable survey report (PDF/CSV with spots + verdicts) for clients

## Tech debt / risks
- [x] Binary API dead-session recovery: serialised commands reconnect once,
      replay login and retry the same read-only command after a background socket
      closure. REST remains stateless; SSH has the equivalent one-shot recovery.
- [ ] Binary-API reader uses `List<int>` with O(n) removes — fine for tiny
      registration tables, revisit if we ever stream large menus
- [ ] Self-signed TLS is accepted by default (LAN assumption) — make it a
      user-visible toggle with a warning
- [ ] wifi_iot RSSI availability varies by OEM ROM — needs field testing
- [ ] Android toolchain compatibility pass: current AGP is 8.9.1 and Gradle is
      8.11.1; Flutter 3.44.8 warns that support will soon require AGP ≥8.11.1
      and Gradle ≥8.14.0. Upgrade those together and run analyze/tests/release
      build on JDK 17. Do not jump to AGP 9 until Flutter explicitly supports it
      (AGP 9.0.1 previously broke this project).
- [ ] Bump Kotlin from 2.1.0 to ≥2.2.20 in the same compatibility pass (Flutter
      3.44.8 warns that 2.1.0 support will be dropped).
- [ ] Full i18n framework (gen-l10n/.arb) — currently a lightweight inline
      L10n.t table covers the main strings only

## Out of scope / declined
- **Native WinBox protocol** — REST, binary API and SSH already expose the
  read-only data the app needs; another proprietary transport would add major
  complexity without a meaningful diagnostic benefit.
- **SNMP transport** — duplicates metrics available through the existing
  transports while requiring another enabled service and credential set.
