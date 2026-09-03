# Architecture / Архитектура

## One measurement pass

```
        ┌────────────────────────── MonitorController ──────────────────────────┐
        │                                                                        │
 PhoneWifiService.read()                                  WifiRouterService      │
   RSSI, SSID, BSSID, IP  ─────────► our IP ──► cached resolveMacForIp(ip)       │
        │                                    │  periodic / on link change         │
        │                                          ▼                              │
        │                                       our MAC ──► fetchStation(mac)     │
        │                                                     registration-table  │
        ▼                                                          ▼              │
   PhoneSignal (phone side)                              StationSignal (AP side)  │
        └───────────────────────────► Home dashboard ◄──────────────────────────┘
                                     phone | AP | Δ + history
```

The loop has three independent cadences. A signal tick reads the phone,
registration table and gateway ping. Router health/CPU uses a slower cache, and
IP→MAC discovery uses another cache. A changed network or BSSID invalidates the
identity cache immediately; otherwise the BSSID-owning/last-serving router is
queried first. The presets are 1/10/15 s (Fast), 2/15/30 s (Normal) and
5/30/60 s (Economical) for signal/health/identity respectively, plus Custom.
Timers and ping pause in the background and an immediate refresh runs on resume.

## Layers

| Layer        | Files                                   | Responsibility                         |
|--------------|-----------------------------------------|----------------------------------------|
| Transport    | `mikrotik/*_transport.dart`, `mikrotik/knock_aware_transport.dart`, `keenetic/keenetic_rci_client.dart` | Talk to RouterOS or the whitelisted Keenetic RCI reads; optionally open one selected RouterOS service with a fixed knock sequence |
| Interface    | `router/wifi_router_service.dart`, `mikrotik/router_os_transport.dart` | Vendor-neutral dashboard reads plus RouterOS menu reads; no write method |
| Service      | `mikrotik/mikrotik_service.dart`, `keenetic/keenetic_service.dart` | Vendor dispatch, IP→MAC→signal and normalized router health |
| Device       | `services/phone_wifi_service.dart`      | Local Wi-Fi chip readings               |
| State        | `state/monitor_controller.dart`         | Poll loop, history, delta               |
| UI           | `ui/…`                                   | Dashboard, form, sparkline              |

## Optional MikroTik port knocking

Port knocking is a narrow decorator around one explicitly selected RouterOS
transport, not a fourth transport and not a scanner:

```
secure Wi-Fi/LTE profile → PortKnocker (1–8 fixed TCP/UDP packets)
                                      → settle delay
                                      → REST or API or SSH → read-only gate
```

`Auto` is rejected while knocking is enabled, so the client cannot try several
management services after one sequence. The decorator knocks before the first
connection. If an established session later fails with a recognized network or
closed-session error, it closes that same transport, repeats the sequence once,
reconnects and replays the same read-only operation once. Authentication,
RouterOS syntax/permission failures, TLS setup failures and SSH host-key changes
are not recovery signals.

The sequence lives only in the platform-secure router profile and is omitted
from diagnostic events/support archives. The app never creates RouterOS rules.
An administrator configures the firewall independently; its intended response
may be a temporary dynamic source-address entry before the management service
becomes reachable.

## Optional Zabbix history path

Zabbix is an external archive, not another live router transport and not a
replacement for app-created phone/LTE sessions:

```
ZabbixScreen → ZabbixApiClient → HTTP(S) /api_jsonrpc.php
                                  ├─ apiinfo.version (unauthenticated)
                                  ├─ host.get
                                  ├─ item.get (numeric items only)
                                  ├─ history.get (1h / 24h, max 1,500 rows)
                                  └─ trend.get (7d / 30d hourly aggregates)
```

The API client has a fixed method allowlist and no public generic call. HTTPS
is the default and validates certificates; explicitly selected HTTP uses the
same read-only dispatcher but provides no transport encryption and is visibly
marked as such. Older
supported APIs receive the supplied token in the JSON-RPC `auth` property;
newer APIs receive it as `Authorization: Bearer`, selected after the version
probe. Profiles live in platform secure storage. The token is not copied to
settings, measurement databases, diagnostic events or support bundles.

The standalone explorer exposes Zabbix's own host/item model. Saved Wi-Fi and
LTE sessions add an explicit semantic layer:

```
local session ──► ZabbixBindingStore (no secrets) ──► profile URL + host/item IDs
                                                            │
secure profile/token ──► ZabbixContextService ──────────────┘
                                   │ exact session time range
                                   ▼
                 synchronized local + remote timeline / combined CSV
```

Name/key matching only proposes item mappings; the operator confirms them.
Bindings in SharedPreferences contain no token. The context service resolves
the matching secure profile only while the session is open, fetches bounded
history and closes its HTTP client. Remote points remain transient and are not
inserted into `wifi_history.db` or `lte_history.db`. Every metric track retains
its own Y scale; only same-unit local/remote radio series may share a track.

## Separate LTE path

LTE deliberately does not enter `MonitorController` or the Wi-Fi IP→MAC path:

```
LteScreen → LteController → LteService → RouterOsTransport (REST / API / SSH)
                                      ├─ /interface/lte print
                                      ├─ /interface/lte/monitor … once
                                      └─ /system/resource print
```

`LteService` uses the same `TransportPreference` semantics as Wi-Fi monitoring
(Auto = REST → API → SSH), selects an enabled/running LTE interface and
immediately reduces the monitor response to `LteSignal`. RouterOS returns
IMEI/IMSI/ICCID alongside radio data on many modems; `LteSignal` has no such
fields, so those identifiers do not cross the service boundary. `LteDiagnostics`
evaluates RSRP/RSRQ/SINR, optional RSSI/CQI and recent stability independently
of all Wi-Fi state.

The alignment screen reuses the same live controller and does not introduce a
new RouterOS command:

```
LteAlignmentScreen → LteAlignmentController → LteController.refresh()
                              │
                              └─ LteAlignmentSession + LteAlignmentAnalyzer
                                 stable window → checkpoint → next relative step
```

While the screen is open, polling is temporarily reduced from three to two
seconds. Each checkpoint starts after a four-second settling delay and contains
six fresh samples. The pure analyzer combines RSRP/RSRQ/SINR/CQI, penalises
spread and marks a serving band/cell change. `LteAlignmentSession` stores an
operator-relative integer grid; coordinates are physical steps, never claimed
degrees or compass headings. The in-memory session survives leaving and
reopening the assistant, and is cleared when the LTE router disconnects.

Longer measurements are separate persistent sessions:

```
LteController record toggle → LteHistoryStore → lte_history.db
                                      │
                                      ├─ session metadata + radio samples
                                      └─ detail / CSV / two-session comparison
```

Only the sanitised `LteSignal` fields cross into the LTE history database.
Zoomable charts keep up to 600 current samples in memory, while the live
diagnosis intentionally evaluates only the latest 60 so old movement does not
contaminate the current verdict.

`LteQualityScorer` is the single source of truth for the 0–100 radio score used
by live monitoring, alignment checkpoints and persisted-session comparison. It
uses a five-sample rolling median for charts, applies the same instability
penalty as a six-sample alignment checkpoint and resets the rolling window on a
known band/cell change. Low-confidence warm-up points remain visible but are
excluded from “best” and summary statistics when stable points exist.

## Why three transports

`RouterOsTransport` exposes `read(menuPath, {filters})` plus `command()` for
`monitor once`. Three implementations satisfy it, so `MikrotikService` and
everything above are transport-agnostic:

| Implementation | Reaches | Speaks |
|----------------|---------|--------|
| `RestTransport` | RouterOS 7.1+, `www-ssl` | JSON over HTTPS |
| `BinaryApiTransport` | RouterOS 6 & 7, 8728/8729 | the API word/sentence protocol |
| `SshTransport` | anything with SSH on | the RouterOS console |

`TransportPreference.auto` tries REST → API → SSH. SSH comes last because it
costs a console round-trip per read (~120 ms vs ~60 ms measured on a hAP ac³),
but it is the most widely available: on a RouterOS 6 box with the API service off
it is the only way in.

## Keenetic Alpha path

Keenetic does not implement `RouterOsTransport`. Its small adapter satisfies
only the vendor-neutral `WifiRouterService` contract required by the two-sided
dashboard:

```
MonitorController → KeeneticService → KeeneticRciClient
                                      ├─ POST /auth (x-ndw2 login only)
                                      ├─ GET /rci/show/version
                                      ├─ GET /rci/show/system
                                      ├─ GET /rci/show/associations
                                      ├─ GET /rci/show/ip/dhcp/bindings
                                      └─ GET /rci/show/ip/arp
```

`KeeneticRciClient` has no public generic POST or command method and rejects a
GET path outside that compiled set before making an HTTP request. Full DHCP and
association responses exist only for the duration of a poll; `KeeneticService`
returns the exact MAC resolved from the phone's IP and never persists those
tables. The Alpha compatibility flag is exact, not aspirational: currently only
Runner 4G (KN-2212) with KeeneticOS 5.01.C.3.0-1 is marked verified.

Vendor-specific MikroTik audits, devices and Wi-Fi log analysis remain outside
`WifiRouterService`. They are hidden for a Keenetic-only connection until the
corresponding RCI schemas and semantics have been field-tested.

### What the SSH transport has to reconcile

The console is made for humans, so its output needs normalising back into the
rows REST returns. Each of these was found against a live router:

* `print terse` does **not** quote values, and they contain spaces
  (`interface=hAP AC2 2GHz ssid=SlipKo Wi-Fi`) — fields are cut at the next
  `key=` boundary, never at whitespace.
* Registration tables hide the runtime numbers from `print terse`; the signal,
  rates and uptime only appear under `print stats`. Single-record menus
  (`/system/resource`) reject both and answer with an aligned `label: value`
  block. `read()` walks these flavours in order.
* State that REST returns as a field (`disabled`, `dynamic`, `running`) is a flag
  *letter* on the console — the letters are translated back, otherwise the audit
  would read a disabled service as enabled.
* Booleans print as `yes`/`no` rather than `true`/`false`.

Verified by running the whole audit over both transports against the same
router: 16 findings each, identical (`test/ssh_transport_parse_test.dart` pins
the parsing).

### Sessions die; reads must not lie

Android suspends sockets in the background and RouterOS drops idle sessions, so
a long-lived SSH or binary-API connection may be gone by the time the app is
resumed. Both transports serialise their commands, reconnect once, replay login
and retry the same read-only operation. `RestTransport` is unaffected because
every request opens its own connection.

The audit layer covers the other half: a *failed* read is recorded as unknown
rather than empty, checks that infer absence are skipped, and the report says
which menus it couldn't see — before this, an unreadable
`/ip/firewall/filter` was reported as "No input firewall" on a router with a
default-deny chain.

### Read-only on a channel that could write

REST and the API are read-only because callers can only print menus or execute
the fixed `monitor once` reads exposed by the transport contract. A console
could do anything, so `SshTransport` enforces the rule in code: commands
are composed from a menu path plus a fixed verb, only `print` and `monitor once`
pass the whitelist, console metacharacters are refused, and `monitor` without
`once` is rejected. See `mikrotik-readonly-user.md`.

## Randomized-MAC workaround

Android 10+ presents a randomized MAC to each SSID and hides the real one from
apps. Instead of reading our MAC locally, we read our **IP** (which we always
know), then map IP→MAC on the router via ARP / DHCP leases, and look that MAC up
in the registration table.

## Read-only guarantee

The RouterOS transport interface has no write method; all implementations only
issue `print`/`GET` or a fixed `monitor once`. Combined with a read-only
RouterOS user (see `mikrotik-readonly-user.md`), the app cannot change router
state. The Keenetic client separately allows one POST for authentication and
only five fixed `GET /rci/show/...` reads after it; it exposes no configuration
surface.
