package it.whynotmake.apple_liquid_glass_example

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bench/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "passport" -> result.success(passport())
                    "thermal" -> result.success(thermal())
                    "keepOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "share" -> result.success(
                        share(
                            call.argument<String>("name")!!,
                            call.argument<String>("text")!!,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun passport(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "hardware" to Build.HARDWARE,
        "board" to Build.BOARD,
        "soc" to if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else null,
        "sdk" to Build.VERSION.SDK_INT,
    )

    private fun thermal(): Map<String, Any?> {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val sticky = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return mapOf(
            "status" to if (Build.VERSION.SDK_INT >= 29) power.currentThermalStatus else null,
            "headroom" to if (Build.VERSION.SDK_INT >= 30) power.getThermalHeadroom(10).toDouble() else null,
            "battery_c" to sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)?.div(10.0),
            "current_ua" to battery.getLongProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),
            "plugged" to sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0),
        )
    }

    // Goes through Downloads, whose file another app may read without a
    // provider in the manifest. Older phones have no such store.
    private fun share(name: String, text: String): Boolean {
        if (Build.VERSION.SDK_INT < 29) return false
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return false
        contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
            ?: return false
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(send, name))
        return true
    }
}
