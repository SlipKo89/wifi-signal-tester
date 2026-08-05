# MikroTik read-only user / Пользователь MikroTik только для чтения

> The app never writes to the router. To make that guarantee physical, create a
> dedicated user whose group has **no write policy**.
>
> Приложение никогда не пишет в роутер. Чтобы это стало физически невозможным,
> заведите отдельного пользователя в группе **без права записи**.

## RouterOS commands

```
# A group that can only read and use the APIs — no write, no policy, no reboot.
/user group add name=monitor policy=read,api,rest-api,ssh,test

# The user the app logs in with.
/user add name=monitor group=monitor password=CHANGE_ME
```

Drop `ssh` from the policy list if you never plan to use the SSH transport, and
`api`/`rest-api` likewise — keep only what you use.

## Enable the transport(s) you plan to use

```
# REST API (RouterOS 7.1+) — served over the www-ssl service:
/ip service enable www-ssl
/ip service set www-ssl port=443

# Binary API:
/ip service enable api          # plain, port 8728
/ip service enable api-ssl      # TLS,   port 8729

# SSH — usually already enabled; nothing else to switch on:
/ip service enable ssh          # port 22
```

Lock the services down to your test subnet if you can:

```
/ip service set www-ssl address=192.168.88.0/24
/ip service set api     address=192.168.88.0/24
/ip service set api-ssl address=192.168.88.0/24
/ip service set ssh     address=192.168.88.0/24
```

## The SSH transport, specifically

REST and the binary API are read-only because the app only ever issues
`print`/`GET`. SSH is different: a console session *could* write, so the app
enforces read-only itself.

- Commands are **built** by the app from a menu path plus a fixed verb — the UI
  never passes free text to the router.
- Only `print` (`print terse` / `print stats`) and `monitor … once` are allowed;
  `set`, `add`, `remove`, `reset`, `enable`, `disable`, `export`, `reboot`,
  `scan`, … are rejected before anything is sent.
- Console metacharacters (`;`, `[`, `]`, `{`, `}`, `$`, backticks, pipes,
  redirects) are refused, so a crafted value cannot chain a second command.
- `monitor` must carry `once`, otherwise it would stream forever.
- The app logs in as `<user>+cet1024w` — a documented RouterOS console hint
  (no colours, no terminal detection, wide output) so `print terse` rows don't
  wrap. If that form is rejected it retries with the plain username.

A group with `read` and **no** `write`/`policy` still makes this physical rather
than a promise — use one.

## Why read-only matters here

- The group policy above grants `read` + API access but **not** `write`,
  `policy`, `reboot`, `password`, or `sensitive`. Even a bug in the app cannot
  change router configuration.
- The app only issues `print` (API) and `GET` (REST) requests, and only ever
  reads `/ip/arp`, DHCP leases and the registration table for **your** MAC.

## Menus the app reads

| Purpose            | Menu                                            |
|--------------------|-------------------------------------------------|
| IP → MAC           | `/ip/arp`, `/ip/dhcp-server/lease`              |
| WifiWave2          | `/interface/wifi/registration-table`            |
| CAPsMAN (wifi)     | `/interface/wifi/capsman/registration-table`    |
| CAPsMAN (legacy)   | `/caps-man/registration-table`                  |
| Classic wireless   | `/interface/wireless/registration-table`        |
| Noise floor        | `/interface/wireless/monitor once` (and `/interface/wifi/…`) |
| Audit (Wi-Fi)      | `/caps-man/…`, `/interface/wifi/…`, `/interface/wireless` |
| Audit (system)     | `/system/resource`, `/system/ntp/client`, `/system/package/update`, `/ip/service`, `/user`, `/ip/pool`, `/ip/firewall/filter` |
