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
                if (call.method == "info") {
                    result.success(wifiInfo())
                } else {
                    result.notImplemented()
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
}
