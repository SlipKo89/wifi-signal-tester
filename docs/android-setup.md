# Android setup / Настройка Android

After running `scripts/bootstrap.sh`, add the Wi-Fi permissions the plugins need.
После запуска `scripts/bootstrap.sh` добавьте разрешения для Wi-Fi.

## `android/app/src/main/AndroidManifest.xml`

Add inside `<manifest>`, above `<application>`:

```xml
<!-- READ-ONLY set only. We deliberately do NOT request CHANGE_WIFI_STATE,
     so the app is physically unable to toggle/connect/forget Wi-Fi networks. -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.INTERNET"/>

<!-- Required to read SSID/BSSID and RSSI on Android 8+ -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

<!-- Android 13+: nearby Wi-Fi without location, if you target API 33+ -->
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation" />
```

> **Do not add `CHANGE_WIFI_STATE`.** The `wifi_iot` plugin may reference it, but
> we never call any state-changing method. If a plugin pulls it in transitively,
> strip it with a `tools:node="remove"` override so the app keeps zero ability to
> modify Wi-Fi state:
>
> ```xml
> <uses-permission android:name="android.permission.CHANGE_WIFI_STATE"
>     tools:node="remove"/>
> ```
> (add `xmlns:tools="http://schemas.android.com/tools"` to the `<manifest>` tag)

## Runtime permission

Location permission must be **granted at runtime** and **Location services turned
on**, otherwise Android returns a null/empty SSID and RSSI. A permission prompt
on first launch is on the TODO list; until then grant it in
Settings → Apps → Wi-Fi Tester → Permissions.

## Build config notes

- `minSdkVersion`: 21+ is fine; `flutter_secure_storage` wants 18+.
- Uses JDK 17 to build (see main README).

## iOS (later)

iOS needs the *Access WiFi Information* entitlement and
`NSLocationWhenInUseUsageDescription` in `Info.plist`. RSSI access is more
restricted than on Android — tracked in TODO under v0.3.
