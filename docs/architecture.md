# Architecture / Архитектура

## One measurement pass

```
        ┌────────────────────────── MonitorController ──────────────────────────┐
        │                                                                        │
 PhoneWifiService.read()                                    MikrotikService      │
   RSSI, SSID, BSSID, IP  ─────────► our IP ──► resolveMacForIp(ip)              │
        │                                          │  /ip/arp, dhcp lease         │
        │                                          ▼                              │
        │                                       our MAC ──► fetchStation(mac)     │
        │                                                     registration-table  │
        ▼                                                          ▼              │
   PhoneSignal (phone side)                              StationSignal (AP side)  │
        └───────────────────────────► Home dashboard ◄──────────────────────────┘
                                     phone | AP | Δ + history
```

## Layers

| Layer        | Files                                   | Responsibility                         |
|--------------|-----------------------------------------|----------------------------------------|
| Transport    | `mikrotik/rest_transport.dart`, `binary_api_transport.dart`, `ssh_transport.dart` | Talk RouterOS, read-only |
| Interface    | `mikrotik/router_os_transport.dart`     | One `read()` contract, no write method  |
| Service      | `mikrotik/mikrotik_service.dart`        | Transport fallback, stack detect, MAC→signal |
| Device       | `services/phone_wifi_service.dart`      | Local Wi-Fi chip readings               |
| State        | `state/monitor_controller.dart`         | Poll loop, history, delta               |
| UI           | `ui/…`                                   | Dashboard, form, sparkline              |

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

The transport interface has no write method; all implementations only issue
`print`/`GET`. Combined with a read-only RouterOS user (see
`mikrotik-readonly-user.md`), the app cannot change router state.
