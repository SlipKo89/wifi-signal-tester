package com.slipko.wifi_apk

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "wifi_apk/phone"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(wifiInfo())
                    "deviceInfo" -> result.success(deviceInfo())
                    else -> result.notImplemented()
                }
            }
    }

    // Read-only snapshot of the current Wi-Fi link. Never changes anything.
    private fun wifiInfo(): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        try {
            val wm = applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val info = wm.connectionInfo ?: return map
            map["rssi"] = info.rssi
            map["linkSpeed"] = info.linkSpeed // Mbps, negotiated
            map["frequency"] = info.frequency // MHz
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                map["txLinkSpeed"] = info.txLinkSpeedMbps
                map["rxLinkSpeed"] = info.rxLinkSpeedMbps
                map["standard"] = info.wifiStandard
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                map["security"] = info.currentSecurityType
            }
        } catch (_: Throwable) {
            // Leave partial/empty on any failure.
        }
        return map
    }

    // Intentionally excludes serial, Android ID, IMEI and other unique IDs.
    private fun deviceInfo(): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["platform"] = "android"
        map["manufacturer"] = Build.MANUFACTURER
        map["model"] = Build.MODEL
        map["android_release"] = Build.VERSION.RELEASE
        map["android_sdk"] = Build.VERSION.SDK_INT
        try {
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageInfo(packageName, 0)
            map["app_version"] = info.versionName
            map["app_build"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        } catch (_: Throwable) {
            // The Dart side also carries a compile-time version fallback.
        }
        return map
    }
}
