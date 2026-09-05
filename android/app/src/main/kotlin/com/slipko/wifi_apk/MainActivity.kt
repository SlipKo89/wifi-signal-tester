package com.slipko.wifi_apk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.location.Location
import android.location.LocationManager
import android.content.pm.PackageManager
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val channel = "wifi_apk/phone"
    private val pickerChannel = "wifi_apk/floor_plan_picker"
    private val pickerRequest = 4107
    private val maxImageBytes = 25 * 1024 * 1024
    private val maxProjectBytes = 35 * 1024 * 1024
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingPickerLimit = maxImageBytes
    private var pendingProject = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(wifiInfo())
                    "deviceInfo" -> result.success(deviceInfo())
                    "lastKnownLocation" -> result.success(lastKnownLocation())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pickerChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickImage" && call.method != "pickProject") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingPickerResult != null) {
                    result.error("picker_busy", "An image picker is already open", null)
                    return@setMethodCallHandler
                }
                pendingPickerResult = result
                pendingProject = call.method == "pickProject"
                pendingPickerLimit = if (pendingProject) maxProjectBytes else maxImageBytes
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    if (pendingProject) {
                        type = "*/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                            "application/vnd.wifi-signal-tester.floor-map",
                            "application/zip", "application/octet-stream"
                        ))
                    } else {
                        type = "image/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                            "image/png", "image/jpeg", "image/webp"
                        ))
                    }
                }
                startActivityForResult(intent, pickerRequest)
            }
    }

    @Deprecated("FlutterActivity still dispatches the document picker result here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickerRequest) return
        val result = pendingPickerResult ?: return
        pendingPickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        try {
            var name = if (pendingProject) "floor-map.wifimap" else "floor-plan.jpg"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) name = cursor.getString(index) ?: name
                    }
                }
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > pendingPickerLimit) {
                        throw IllegalArgumentException("Selected file is too large")
                    }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: throw IllegalArgumentException("The selected file cannot be read")
            result.success(mapOf("name" to name, "bytes" to bytes))
        } catch (error: Throwable) {
            result.error("image_read_failed", error.message, null)
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

    // Best-effort location context for an explicitly placed map point. This
    // never subscribes to updates and therefore cannot track in background.
    private fun lastKnownLocation(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED) return null
        return try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val fixes = listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER
            ).mapNotNull { provider ->
                try { manager.getLastKnownLocation(provider) } catch (_: Throwable) { null }
            }
            val fix: Location = fixes.maxWithOrNull(
                compareBy<Location> { it.time }.thenBy { -it.accuracy }
            ) ?: return null
            mapOf(
                "latitude" to fix.latitude,
                "longitude" to fix.longitude,
                "accuracy" to fix.accuracy.toDouble(),
                "altitude" to if (fix.hasAltitude()) fix.altitude else null
            )
        } catch (_: Throwable) {
            null
        }
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
