# MikroTik read-only user / Пользователь MikroTik только для чтения

> The app never writes to the router. To make that guarantee physical, create a
> dedicated user whose group has **no write policy**.
>
> Приложение никогда не пишет в роутер. Чтобы это стало физически невозможным,
> заведите отдельного пользователя в группе **без права записи**.

## RouterOS commands

```
# A group that can only read and use the APIs — no write, no policy, no reboot.
/user group add name=monitor policy=read,api,rest-api,winbox,test

# The user the app logs in with.
/user add name=monitor group=monitor password=CHANGE_ME
```

## Enable the transport(s) you plan to use

```
# REST API (RouterOS 7.1+) — served over the www-ssl service:
/ip service enable www-ssl
/ip service set www-ssl port=443

# Binary API:
/ip service enable api          # plain, port 8728
/ip service enable api-ssl      # TLS,   port 8729
```

Lock the services down to your test subnet if you can:

```
/ip service set www-ssl address=192.168.88.0/24
/ip service set api     address=192.168.88.0/24
/ip service set api-ssl address=192.168.88.0/24
```

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
