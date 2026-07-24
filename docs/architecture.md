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
| Transport    | `mikrotik/rest_transport.dart`, `binary_api_transport.dart` | Talk RouterOS, read-only |
| Interface    | `mikrotik/router_os_transport.dart`     | One `read()` contract, no write method  |
| Service      | `mikrotik/mikrotik_service.dart`        | Transport fallback, stack detect, MAC→signal |
| Device       | `services/phone_wifi_service.dart`      | Local Wi-Fi chip readings               |
| State        | `state/monitor_controller.dart`         | Poll loop, history, delta               |
| UI           | `ui/…`                                   | Dashboard, form, sparkline              |

## Why two transports

`RouterOsTransport` exposes a single `read(menuPath, {filters})`. `RestTransport`
(RouterOS 7.1+, HTTPS) and `BinaryApiTransport` (8728/8729, RouterOS 6 & 7) both
implement it, so `MikrotikService` and everything above are transport-agnostic.
`TransportPreference.auto` tries REST first, then the binary API.

## Randomized-MAC workaround

Android 10+ presents a randomized MAC to each SSID and hides the real one from
apps. Instead of reading our MAC locally, we read our **IP** (which we always
know), then map IP→MAC on the router via ARP / DHCP leases, and look that MAC up
in the registration table.

## Read-only guarantee

The transport interface has no write method; both implementations only issue
`print`/`GET`. Combined with a read-only RouterOS user (see
`mikrotik-readonly-user.md`), the app cannot change router state.
