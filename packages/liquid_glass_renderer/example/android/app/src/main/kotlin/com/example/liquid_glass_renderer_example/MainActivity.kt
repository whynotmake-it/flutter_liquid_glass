package com.example.liquid_glass_renderer_example

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "configuration") {
                result.success(configurationFromIntent())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun configurationFromIntent(): Map<String, Any> {
        val extras = intent.extras ?: return emptyMap()
        val configuration = mutableMapOf<String, Any>()
        extras.getString(EXTRA_SCENARIO)?.let { configuration["scenario"] = it }
        if (extras.containsKey(EXTRA_WARMUP_SECONDS)) {
            configuration["warmupSeconds"] = extras.getInt(EXTRA_WARMUP_SECONDS)
        }
        if (extras.containsKey(EXTRA_MEASURE_SECONDS)) {
            configuration["measureSeconds"] = extras.getInt(EXTRA_MEASURE_SECONDS)
        }
        if (extras.containsKey(EXTRA_REPETITION)) {
            configuration["repetition"] = extras.getInt(EXTRA_REPETITION)
        }
        return configuration
    }

    companion object {
        private const val CHANNEL = "dev.liquid_glass_renderer/benchmark"
        private const val EXTRA_SCENARIO = "scenario"
        private const val EXTRA_WARMUP_SECONDS = "warmupSeconds"
        private const val EXTRA_MEASURE_SECONDS = "measureSeconds"
        private const val EXTRA_REPETITION = "repetition"
    }
}
