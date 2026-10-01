package com.example.liquid_glass_renderer_example

import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import java.io.File
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
            when (call.method) {
                "configuration" -> result.success(configurationFromIntent())
                "startMemorySampling" -> {
                    startMemorySampling()
                    result.success(null)
                }
                "stopMemorySampling" -> result.success(stopMemorySampling())
                else -> result.notImplemented()
            }
        }
    }

    @Volatile private var sampling = false
    private var sampler: Thread? = null
    private val samples = mutableListOf<Map<String, Long>>()

    // PSS from smaps_rollup every 50 ms, reported under the macOS runner's
    // sample keys. GPU memory isn't in PSS; the Android analyzer adds it
    // from the Perfetto gpu_mem_total counter.
    private fun startMemorySampling() {
        stopMemorySampling()
        synchronized(samples) { samples.clear() }
        sampling = true
        sampler = Thread {
            while (sampling) {
                readRollup()?.let { synchronized(samples) { samples.add(it) } }
                SystemClock.sleep(SAMPLE_PERIOD_MS)
            }
        }.also { it.start() }
    }

    private fun stopMemorySampling(): List<Map<String, Long>> {
        sampling = false
        sampler?.join(SAMPLE_PERIOD_MS * 4)
        sampler = null
        return synchronized(samples) { samples.toList() }
    }

    private fun readRollup(): Map<String, Long>? {
        var pssKb = -1L
        var rssKb = -1L
        try {
            File("/proc/self/smaps_rollup").forEachLine { line ->
                when {
                    line.startsWith("Pss:") -> pssKb = line.split(Regex("\\s+"))[1].toLong()
                    line.startsWith("Rss:") -> rssKb = line.split(Regex("\\s+"))[1].toLong()
                }
            }
        } catch (e: Exception) {
            return null
        }
        if (pssKb < 0) return null
        return mapOf(
            "timestampMicros" to System.currentTimeMillis() * 1000,
            "physicalFootprintBytes" to pssKb * 1024,
            "residentBytes" to rssKb * 1024,
        )
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
        private const val SAMPLE_PERIOD_MS = 50L
    }
}
