# How to use Wi-Fi Signal Tester

*Русская версия — [usage.ru.md](usage.ru.md)*

This is the user guide: what the app shows, how to read it, and how to run the
typical checks. For the project overview see [README.md](../README.md); for the
version history see [CHANGELOG.md](../CHANGELOG.md).

## Contents

1. [What the app is for](#1-what-the-app-is-for)
2. [What you need before you start](#2-what-you-need-before-you-start)
3. [Preparing the router](#3-preparing-the-router)
4. [First launch and permissions](#4-first-launch-and-permissions)
5. [Connecting](#5-connecting)
6. [Reading the dashboard](#6-reading-the-dashboard)
7. [What good numbers look like](#7-what-good-numbers-look-like)
8. [Typical jobs](#8-typical-jobs)
9. [Audits](#9-audits)
10. [History and recording](#10-history-and-recording)
11. [Targets and alerts](#11-targets-and-alerts)
12. [Settings](#12-settings)
13. [Reference and help](#13-reference-and-help)
14. [LTE signal diagnostics](#14-lte-signal-diagnostics)
15. [Zabbix history](#15-zabbix-history)
16. [Support report](#16-support-report)
17. [Troubleshooting](#17-troubleshooting)
18. [What the app never does](#18-what-the-app-never-does)

---

## 1. What the app is for

Every phone Wi-Fi analyzer shows one half of the link: **how your phone hears the
access point**. That half is not enough. A phone can show a comfortable −50 dBm
while the AP hears the phone at −75 dBm — the AP shouts, the phone whispers, and
the connection stutters in one direction only.

This app reads the **other half** from the router itself — MikroTik (CAPsMAN or
plain Wi-Fi), plus an initial Keenetic Alpha integration — for **your device's
MAC only**, and puts both halves side by side with the difference between them:

<img src="screenshots/dashboard.png" width="300" alt="Two-sided dashboard">

## 2. What you need before you start

- An Android phone with the APK from the
  [Releases page](../../../releases/latest).
- A supported router reachable from that phone: MikroTik, or the Keenetic Alpha
  compatibility baseline described below.
- A dedicated account for monitoring (see the next section).
- The phone connected to the Wi-Fi you want to test (not mobile data) — the app
  identifies your station by its IP on the router.

Nothing needs to be installed on the router, and nothing about its configuration
has to change beyond enabling the service you connect through.

## 3. Preparing the router

### MikroTik

Full walkthrough: [mikrotik-readonly-user.md](mikrotik-readonly-user.md). Short
version — a group without `write`, plus the service you prefer:

```
/user group add name=monitor policy=read,api,rest-api,ssh,test
/user add name=monitor group=monitor password=CHANGE_ME

/ip service enable www-ssl     # REST  (RouterOS 7.1+)
/ip service enable api         # binary API (RouterOS 6 & 7)
                               # SSH is usually already on
```

Three transports are supported and you can just leave the app on **Auto**:

| Transport | Port | Needs | Notes |
|-----------|------|-------|-------|
| REST | 443 | RouterOS 7.1+, `www-ssl` | Fastest, tried first |
| Binary API | 8728 / 8729 | `api` / `api-ssl` service | Works on RouterOS 6 |
| SSH | 22 | `ssh` policy on the user | Nothing extra to enable; runs only `print` and `monitor once` |

SSH is the rescue path for a router where REST doesn't exist and the API service
is switched off. It is a bit slower (a console command per read — about 120 ms
per poll against 60 ms over REST), and it stays read-only: the app builds every
command itself from a menu path plus `print`/`monitor once`, and refuses
anything else.

**Optional port knocking.** If the management service is protected by an
existing RouterOS port-knocking firewall sequence, enable the advanced block in
the Wi-Fi or LTE connection profile. Add 1–8 TCP/UDP steps in their exact order,
then choose one transport explicitly; `Auto` is intentionally refused so the
app will not probe several management ports. The default delay is 300 ms
between packets and 500 ms before connecting. Adjust both to the timeouts of
your firewall rules. Ports are hidden by default and the sequence is stored
with the password in platform secure storage.

The app does not create the firewall sequence. It only sends the configured
packets before the first connection and once after a real network/session
failure. Depending on the existing RouterOS rules, this can temporarily add the
phone/computer IP to a dynamic address list. Authentication, command and SSH
host-key errors do not repeat the sequence.

### Keenetic Alpha

The first Keenetic integration uses HTTPS RCI and is developed and verified on
**Runner 4G (KN-2212) with KeeneticOS 5.01.C.3.0-1**. It is deliberately marked
Alpha: other models and releases may return different fields. Thanks to
**Netspay** for providing the test router.

Create a separate Keenetic user and make sure HTTPS RCI is reachable either at
the local router address or through its KeenDNS hostname. In the connection
form choose *Keenetic (Alpha)*. There is no transport chooser in this mode:
HTTPS RCI is the only implemented Keenetic transport.

The client performs the required x-ndw2 challenge-response login, then only
reads a fixed whitelist of `show` endpoints for system/version, associations,
DHCP bindings and ARP. The sole POST is `/auth`; the client has no generic RCI
configuration call. The current Alpha covers the two-sided dashboard for the
phone running the app. Keenetic audits, logs and browsing other clients are not
enabled yet.

## 4. First launch and permissions

The app asks for **location** once. That is not tracking: Android only reveals
the SSID, BSSID and RSSI of the current network to apps holding a location
permission. Deny it and you will still see IP, gateway and the router side, but
the network name and the AP identity stay hidden.

The app does not request background location and never reads physical
coordinates. It also deliberately rejects every permission that could change
Wi-Fi or network settings, so it cannot connect, disconnect or forget networks.

## 5. Connecting

Fill in the form on the first screen:

- **Router vendor** — MikroTik, or Keenetic (Alpha).
- **Host / IP** — the router's address, e.g. `192.168.88.1`.
- **Username / Password** — the read-only user.
- **Transport** — `Auto (REST → API → SSH)` unless you have a reason.
- **Port** — leave empty for the standard port; the field is enabled only when
  you pin a transport (a custom port belongs to one protocol).
- **TLS** — on for HTTPS/api-ssl. Self-signed certificates are accepted, which is
  the norm on a private RouterOS LAN. This encrypts the connection but does not
  authenticate that certificate, so use it only on a trusted LAN/VPN.
- **Port knocking (advanced)** — use only with an already configured MikroTik
  firewall sequence and an explicitly selected REST/API/SSH transport. Add the
  exact TCP/UDP ports and tune the two delays if the router uses short timeouts.

On the first successful SSH connection the app remembers the router's host-key
fingerprint in platform secure storage. If that host later presents another
key, the connection stops and shows both fingerprints. Trust the new key only
after confirming a RouterOS reinstall, SSH-key regeneration or device change.

**Several routers.** Press *Add another router* to build a list — a central
CAPsMAN box plus standalone APs, for example. The app polls all of them and
follows your phone as it roams between them; the dashboard shows which AP
currently serves you. Credentials go into the Android Keystore, never into plain
preferences.

**No router at hand?** Tap *Just view my network (no router)* for phone-only
mode: everything the phone knows about the link (RSSI, band, channel, standard,
security, link speeds, ping) plus a phone-side audit. The AP card is hidden
because there is nothing to read it from.

<img src="screenshots/dashboard-phone.png" width="300" alt="Phone-only mode">

## 6. Reading the dashboard

**Status strip** (top). Green — every metric is inside your targets. Amber — it
lists exactly what is out of target (phone signal, AP signal, either SNR,
asymmetry).

**Connection summary.** SSID, band, channel and frequency, the AP that serves
you, your IP and BSSID, the transport in use, and the **Δ badge**.

> The Δ badge is the point of the app: the difference between how the AP hears
> you and how you hear the AP. **Tap it** for a plain-language verdict and
> advice — e.g. "the AP is louder than your phone: lower AP TX power or move
> closer", which is the usual fix for a one-sided link.

**Phone → hears AP** (green card). RSSI, SNR, link speeds (tx/rx), 802.11
generation, security, channel.

**AP → hears phone** (blue card). The registration-table numbers for your MAC:
signal, SNR (measured, or estimated from the radio's noise floor where the table
doesn't report it — marked as an estimate), tx/rx rate, CCQ, per-chain signal,
throughput derived from byte counters, uptime on this AP, and a roam counter for
the session.

**Router health.** Model, RouterOS/KeeneticOS version, CPU load, uptime.

**Ping.** Real ICMP round-trip to the gateway each poll. Latency spikes or loss
while the signal looks strong point at interference or a busy AP.

**Connection diagnosis.** This is a bounded six-sample check, not an endless
rolling verdict. Press *Run diagnosis* to start it at the current position. The
card shows progress, then freezes the result with the AP name and completion
time; tap the verdict for facts, likely causes and checks. After connecting or
roaming the app can run the same check automatically, but waits for the link to
settle first so handoff transients do not distort the result. While waiting,
*Run now* skips the delay; an active run can be cancelled or repeated.

**Sparkline.** Both sides over time — walk around the flat or office and watch
where it collapses.

Any number can be **tapped** for an explanation of what it means and what to do
about it.

## 7. What good numbers look like

| Metric | Good | Usable | Poor |
|--------|------|--------|------|
| Signal (either side) | −30…−60 dBm | −60…−70 dBm | below −75 dBm |
| SNR | above 25 dB | 15…25 dB | below 15 dB |
| Asymmetry Δ | under 6 dB | 6…12 dB | over 12 dB |
| Ping to gateway | under 20 ms | 20…80 ms | over 80 ms, or loss |

A large Δ with a *strong* phone signal is the classic "AP too loud" case: the
phone hears a distant AP fine and keeps clinging to it, but its own transmit
never arrives. Lowering AP TX power or adding an access-list signal range fixes
more problems than raising power ever does.

## 8. Typical jobs

**Walk-around survey.** Connect, press ⏺ *Record*, walk the route slowly, stop
at the dead spots for a few seconds, press ⏹ to stop. The session lands in
*History* and can be exported as CSV.

**Diagnose a one-sided link.** Stand where the complaint is, look at Δ, tap it,
follow the advice. Re-check after the change — the same spot, the same poll
interval.

**Check a TV, laptop or a guest's phone.** ⋮ → *Devices*: every station
currently associated, enriched with IP and name from the DHCP leases. Pick one to
see how the APs hear *it*. Useful for devices that cannot run an analyzer.

**Explain a disconnect or roam.** Open ⋮ → *Wi-Fi events* for this phone, or
open a currently-associated device and press *Analyze Wi-Fi events*. The app
reads the latest RouterOS `wireless`/`caps` events on demand, classifies explicit
reasons and pairs a disconnect with the next connection to measure the handoff.
The source card shows the transport actually used; Auto is recommended because
REST, binary API and SSH provide the same result.

Only `time`, `topics` and `message` are requested, and no more than the newest
2,000 rows per router are examined. The app keeps normalized findings, not raw
router logs or unrelated client MACs. If wireless debug logging is absent, the
screen says so. It never enables logging itself: that would be a RouterOS write
and is deliberately outside the app's read-only contract.

**Before/after a config change.** Run the Wi-Fi audit, apply the fixes yourself
on the router, run the audit again, export both to PDF.

## 9. Audits

Three read-only reports, all from ⋮:

- **Wi-Fi audit** — RF and Wi-Fi configuration: channel plan (1/6/11), co-channel
  overlap between your own APs, width on 2.4 GHz, country/regulatory, TX power,
  security of the configurations that are actually applied to a running radio,
  client isolation, sticky-client policy.
- **System audit** — health and hardening: NTP sync, RouterOS update available,
  FTP/Telnet, management services exposed, the default `admin` account, an input
  firewall, IP-pool exhaustion.
- **Network audit (phone)** — in phone-only mode: signal, band, 2.4 GHz channel,
  security, 802.11 generation, and link rate against the signal.

<img src="screenshots/audit.png" width="300" alt="Audit screen">

Each finding is bilingual, carries a severity, says *where* it applies and *what
to do*. **Checks that pass are shown too** — a report that lists only problems
never tells you what is already right. Tap *Export PDF* to share a report.

The audit is deliberately conservative and says so when it is unsure:

- it judges the **operating state** (`current-channel`) rather than a config
  field, because CAPsMAN overrides local settings;
- a CAPsMAN configuration that isn't applied to a running radio is not treated as
  a live risk;
- a service is only called "exposed" when there is neither an address ACL nor a
  default-deny firewall rule;
- a disabled `admin` account is reported as **OK**, not as a finding;
- if a menu could not be read, the report says **"Report incomplete: N menu(s)
  unreadable"** and skips the checks that depend on it — an unreadable firewall
  must never be mistaken for a missing firewall.

## 10. History and recording

⏺ in the app bar records every poll into an on-device SQLite database. ⋮ →
*History* lists sessions; open one for the samples, share it as CSV, or delete
it. A Wi-Fi session detail keeps phone/AP signal, AP SNR and client traffic on
separate synchronized tracks. Deleting removes only the app's own data.

## 11. Targets and alerts

*Settings → Targets* sets the minimum acceptable signal and SNR and the maximum
tolerable asymmetry. The status strip is judged against these numbers.

The bell icon in the app bar toggles **alerts**: on a breach the app beeps
(880 Hz) and vibrates, so you can walk with the phone in your hand and listen
instead of watching. Everything is generated in memory — no media files, no
notification permission.

## 12. Settings

| Setting | Meaning |
|---------|---------|
| Language | Russian / English, switches immediately |
| Polling profile | Fast / Normal / Economical presets, or Custom. The default Normal profile reads live signal and ping every 2 s, router health/CPU every 15 s and refreshes IP→MAC discovery every 30 s |
| Custom polling intervals | Separate periods for signal/ping, router health/CPU and IP→MAC client discovery |
| History length | How many points the sparkline keeps |
| Connection diagnosis | Automatic run after connect/roam and its settling delay (default 10 s); manual run remains available |
| Targets | Minimum signal, minimum SNR, maximum Δ |
| Alerts | Beep + vibrate on a breach, and the Δ threshold |

The app pauses live Wi-Fi requests and ping while it is in the background. On
return it immediately takes a fresh sample and continues the selected profile.
Changing the network or BSSID bypasses the IP→MAC cache, so roaming remains
responsive even with an economical discovery interval.

## 13. Reference and help

⋮ → *Reference* explains every metric the app shows — signal, SNR, CCQ, rates,
throughput, ping, Δ, bands, uptime — in plain language, including what to do when
a number is bad. Tapping a number anywhere in the app opens the same entry.

<img src="screenshots/reference.png" width="300" alt="Reference screen">

The book icon in the Reference app bar (and ⋮ → *How to use*) opens this guide.
About → *GitHub* opens the project page.

Two entries worth reading up front: **Δ / asymmetry**, and **Wi-Fi scan
throttling** — Android limits how often apps may scan, which is why some numbers
refresh more slowly than the poll interval.

## 14. LTE signal diagnostics

⋮ → *LTE diagnostics* opens a completely separate tool for a MikroTik with an
LTE modem. It does not use the phone's Wi-Fi measurements and does not require
the phone to be associated with the MikroTik's Wi-Fi. The router only needs to
be reachable over one supported management transport.

Enter the host, read-only username and password. *Auto* tries REST → binary API
→ SSH, or you can pin one transport, its TLS mode and a custom port. Leave *LTE
interface* empty to auto-select a running interface, or enter a name such as
`lte1`. Every successfully connected router is added to the **Saved LTE
routers** list; tap one to refill all fields or × to forget only that router.
Profiles and passwords are stored in the device Keystore separately from Wi-Fi
router profiles. Existing profiles created by the single-profile SSH-only
version are migrated automatically and remain SSH profiles after the update.

The first valid modem sample may take several polls over SSH. While waiting,
the dashboard explicitly says that the router is connected and continues
polling; zero-filled modem placeholders are hidden rather than diagnosed as a
real signal. A genuine `searching`, `denied` or `not-registered` status is shown
immediately.

The app runs only these read-only commands:

```
/interface lte print
/interface lte monitor <interface> once
/interface lte apn print
/interface lte settings print          # RouterOS 7
/ipv6 firewall filter print            # presence only, when APN requests IPv6
/system resource print
```

### LTE configuration audit

Open ⋮ → *LTE configuration audit* after connecting. Select how the link is
used: general/unspecified, primary Internet, backup, passthrough or monitoring
and alignment only. The role changes only route and passthrough advice; it does
not change RouterOS.

The audit checks the selected interface and applied APN profiles, registration,
manual APN together with `use-network-apn`, PAP/CHAP mode, default-route and
distance, operator DNS, PDN IP type, IPv6 firewall presence, MTU, passthrough
target/MAC, roaming, driver/network mode and native band/operator restrictions.
It shows passed checks as well as warnings, links each applicable finding to
MikroTik documentation, and exports a separate `lte-audit.pdf`.

This is a static, read-only audit. It never reads SIM PIN, APN username or
password, `modem-init`, IMEI, IMSI or ICCID. It does not run `at-chat`, scan,
cell-monitor or firmware upgrade. Arbitrary AT locks and the complete routing
or firewall policy are therefore deliberately not inferred.

The dashboard refreshes every three seconds and shows:

- **RSRP** — received LTE reference-signal power; the main coverage/antenna
  level;
- **RSRQ** — reference-signal quality, affected by interference and sector load;
- **SINR** — useful signal versus interference/noise; strongly affects speed;
- **RSSI/CQI** where the modem reports them;
- band, channel width, EARFCN, PCI, eNodeB/sector and Cell ID;
- min/average/max values over the latest 60 samples.

Above the technical charts, **LTE Quality 0–100** provides one simpler line:
higher is better. It combines RSRP, RSRQ, SINR and optional CQI, gives received
power more weight when coverage is weak, and penalises unstable readings. The
line is smoothed over five recent samples; a known band/cell handoff is marked
and starts a fresh window instead of mixing two radios. The card shows the
current and best stable result. Tap a point for its underlying radio values or
expand the technical charts. The zones are 0–39 poor, 40–59 attention, 60–79
good and 80–100 excellent.

This score compares **radio conditions**, not Internet speed. Sector load,
routing and provider congestion can still make a high-scoring link slow.

The verdict deliberately separates **weak but clean** coverage (alignment,
height, cable/connectors are likely limiting) from **strong enough but noisy**
radio (interference, reflections or sector load are more likely). Tap RSRP,
RSRQ, SINR, RSSI or CQI for thresholds and an explanation.

### Antenna alignment assistant

On the LTE dashboard, press *Start antenna alignment assistant*. Choose a small
physical movement that you can repeat consistently — for example, one mark on
the bracket. The app cannot know the antenna's absolute azimuth or elevation,
so its X/Y coordinates mean operator-confirmed **steps**, not degrees.

1. Keep the dish still and capture the baseline.
2. Follow the proposed relative move, then press *I moved — measure*.
3. The app waits four seconds for the radio to settle and records six fresh
   readings. Do not move the dish during this window.
4. Repeat the suggested probes. The assistant continues in an improving
   direction, then checks the unvisited neighbours around the confirmed best
   checkpoint.
5. When no neighbouring checkpoint is meaningfully better, return by the shown
   number of steps, halve the physical step and start the fine pass.

The same Quality Score line is used here and on the dashboard; expand the
technical block to keep RSRP, RSRQ and SINR visible separately. The checkpoint
score is only a navigation aid: when RSRP is very weak it gives coverage more
weight; once power is usable it prioritises SINR/RSRQ, includes CQI where
available and penalises unstable peaks. Always verify the raw metrics.
A band or serving-cell handoff is marked because a score change may then come
from the handoff rather than antenna movement alone.

The checkpoints remain available if you leave and reopen the assistant, but
the current alignment grid is cleared when you disconnect from the LTE router.
Use the restart icon to discard it and take a new baseline.

### LTE recording history

Tap the red record icon on the LTE dashboard to start a persistent session.
Every successful LTE poll is then stored locally; tap Stop or disconnect to
finish it. Open *LTE history* from the dashboard menu to rename, inspect,
export or delete a session. Select exactly two sessions to compare their
RSRP/RSRQ/SINR/RSSI/CQI averages, spreads, bands and serving cells.
The comparison also includes the average LTE Quality Score and P10: the score
that 90% of stable measurements were no worse than.

At 1× each live or saved chart fits its whole series into the available width.
Use −/+, the 1×…20× slider or a two-finger pinch to expand it, then pan
horizontally. This does not discard points; it only changes their display scale.
Saved history contains only app-created radio measurements and can be deleted
from the history screen.

RouterOS often includes IMEI, IMSI and ICCID in the monitor response. The app
does not model, display, log or persist those identifiers; they are discarded
immediately after the response is parsed.

## 15. Zabbix history

Open ⋮ → *Zabbix history*, or *Settings → Integrations → Zabbix*. This optional
integration reads metrics that Zabbix has already collected; it does not replace
the app's live RouterOS reads or phone/LTE recordings.

Paste an existing API token, select HTTPS or HTTP, enter the frontend host/path
and optionally a custom port. For example: HTTPS,
`zabbix.example.com/zabbix`, port `8443`, or HTTP, `192.168.1.20/zabbix`, port
`8080`. Tap *Test and save*. The app then:

1. detects the Zabbix API version;
2. shows only hosts readable by that token;
3. loads active supported numeric items for the selected host;
4. lets you search by item name, key or units;
5. shows latest/minimum/average/maximum and a chart.

For one hour and 24 hours it requests bounded raw `history.get` values. Seven
and 30 days use hourly `trend.get` averages and retain the hourly min/max in the
summary. If trends are unavailable, a clearly labelled bounded raw-history
fallback is shown. Reaching the 1,500-point cap is also called out, so a partial
raw series is never presented as complete.

The standalone Zabbix screen remains an explorer for arbitrary metrics. To put
those metrics into a real measurement, open a saved Wi-Fi or LTE session and
use *Zabbix context → Link Zabbix*:

1. select the saved Zabbix profile and the host representing that router;
2. map the useful slots (Wi-Fi RSSI/SNR/CCQ, LTE RSRP/RSRQ/SINR/RSSI/CQI,
   CPU, latency, loss, traffic and client count) to the exact items;
3. check every suggested mapping — name/key matching is only a convenience and
   custom templates may use different semantics;
4. save the link. New sessions for the same router reuse it.

The session then reads Zabbix values for exactly its start/end interval and
draws stacked tracks with one movable time cursor. Every track has its own Y
scale, so dBm, percent, milliseconds and traffic are not mixed. Matching local
and Zabbix radio metrics share a track only when their units match. *Export
combined CSV* produces a long-form file with source, metric, timestamp, value
and unit for retrospective analysis.

Only the mapping metadata is saved outside secure storage. The API token stays
in the protected Zabbix profile. Zabbix points are requested on demand and are
not copied into either local SQLite history. Removing a Zabbix profile therefore
makes its context unavailable until the link is configured again; it does not
damage the local session.

Tap the help icon on the Zabbix screen for the exact least-privilege setup, or
read [zabbix-readonly-user.md](zabbix-readonly-user.md). Use a dedicated User
role, Host permission **Read**, and an API method allow-list containing only
`host.get`, `item.get`, `history.get` and `trend.get`. An administrator should
create the expiring token for that service user.

The token is stored in platform secure storage and never enters support
reports. Forgetting the profile removes only its local copy; revoke the token
in Zabbix separately. HTTPS remains the default and validates the certificate.
HTTP is available for legacy/local installations, but it sends the API token
and metrics without encryption: use it only on a trusted LAN or through a VPN.

## 16. Support report

⋮ → *Support report* creates troubleshooting material you can send to the
developer. Nothing is collected remotely and nothing is uploaded automatically.
Only pressing *Create and share ZIP* writes a temporary archive containing:

- `report.txt` — readable app/device state, current two-sided metrics and link
  diagnosis;
- `report.json` — the same facts in a structured form;
- `events.log` — up to 200 controlled connection/lifecycle events kept only in
  memory until the app restarts or you clear them;
- `README.txt` — a privacy reminder.

SSID, BSSID, MAC, IP and router/AP names are masked by default. You may include
them with the switch when they are necessary to reproduce a problem. Passwords,
tokens, private keys, raw RouterOS responses and full lists of other clients are
never included, even with that switch enabled. Review `report.txt` before
sharing. *Copy readable report* is available when a ZIP is inconvenient.

## 17. Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| "Not connected to Wi-Fi" while you are | Location permission denied, or the phone is on mobile data. Grant location; the app also judges by IP, so check you have a LAN address. |
| AP card empty / phone absent from the association table | Your phone associated with an AP this router doesn't manage, or the association has not appeared yet. Add the serving router too and retry. |
| Authentication failed | Wrong user/password, or the group lacks the policy for that transport (`rest-api`, `api`, `ssh`). |
| "REST API not available" | RouterOS 6, or `www-ssl` disabled. Switch the transport to Auto, API or SSH. |
| Router unreachable | Wrong host, or you're not on its network. Check the gateway shown in the summary. |
| Values refresh slowly | Android Wi-Fi scan throttling — see the Reference entry, or raise the poll interval. |
| SNR marked as estimate | The registration table doesn't report SNR (typical for CAPsMAN); it is derived from the radio's measured noise floor. |
| Nothing at all over SSH | The user's group needs the `ssh` policy; check `/ip service` allows your subnet. LTE can also use REST or the binary API. |
| SSH host key changed | Compare the shown fingerprint with the router. If RouterOS was reinstalled or the device/key was intentionally replaced, choose **Trust new SSH key**; otherwise do not continue. |
| LTE says no interface was found | Check that `/interface lte print` contains an enabled interface, or clear/correct the optional interface name in the LTE form. |
| LTE says that data is still loading | The router is connected, but valid modem metrics have not arrived. Let the automatic polling continue; if it persists, check that the LTE interface is running and the modem is registering. |
| LTE is registered but metrics remain empty | Some modem/RouterOS combinations need a current modem firmware before they expose radio metrics. |
| Zabbix rejects the token | Check token expiry, API access in the role, the four-method allow-list and Host permission Read for the selected host groups. |
| Zabbix connects but shows no hosts | The token is valid, but its user cannot read any host groups. Add Read—not Read-write—host permission. |
| Zabbix history is empty | The item may have no values in that period, or Zabbix housekeeping no longer retains raw history/trends. Try another range and check item retention. |
| Zabbix TLS validation fails | Use a trusted certificate for the frontend. This version does not silently accept invalid or self-signed Zabbix certificates. |
| Audit says "Report incomplete" | Those menus couldn't be read — usually a session dropped while the app was in the background (it reconnects, so just re-run), or a user without rights to them. |

## 18. What the app never does

- **On the router:** no writes, ever. There is no write path in the code — the
  transport interface exposes only reads, and the SSH transport additionally
  whitelists `print` / `monitor once` and refuses anything else. It reads only
  what it needs: ARP/DHCP for IP→MAC, the registration table for your MAC,
  wireless and system menus for the audit, or the LTE interface/monitor in the
  separate LTE tool. LTE modem/SIM identifiers returned by RouterOS are
  discarded rather than stored.
- **In Zabbix:** it only calls `host.get`, `item.get`, `history.get` and
  `trend.get`. It cannot create users/tokens, modify monitoring configuration,
  acknowledge problems or send values. Removing a local profile does not issue
  a server-side delete.
- **On the phone:** it reads the Wi-Fi chip but never changes, connects,
  disconnects or forgets a network — the permission to do so is explicitly
  removed from the manifest. It accesses no contacts or media. The only data it
  stores is its own: router credentials in the Keystore, settings, measurement
  history, and a temporary support ZIP created only on request — and only app
  data can be deleted from inside the app.

Questions, bugs and ideas: [GitHub issues](../../../issues), or Telegram
[@slipko](https://t.me/slipko).
