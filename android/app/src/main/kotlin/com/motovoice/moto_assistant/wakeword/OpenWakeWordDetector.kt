package com.motovoice.moto_assistant.wakeword

import android.content.Context
import android.util.Log

class OpenWakeWordDetector(
    private val context: Context,
    private val onDetected: (score: Float, keyword: String) -> Unit,
) : WakeDetector {
    private var detector: OpenWakeWord? = null
    private var threshold = 0.025f
    override var isListening = false
        private set

    override fun start() {
        if (isListening) return
        val d = detector ?: OpenWakeWord.Builder(context)
            .setModel(OpenWakeWord.BuiltInModel.HEY_JARVIS)
            .setThreshold(threshold)
            .build()
            .also { detector = it }
        // The library leaves isRunning=true if a previous start failed (e.g. no mic permission); stop() resets it.
        d.stop()
        d.start { score ->
            Log.i(TAG, "Wake word detected, score=$score")
            pause()
            onDetected(score, "HEY_JARVIS")
        }
        isListening = true
    }

    // Keeps the ONNX models loaded so resuming is cheap.
    override fun pause() {
        if (!isListening) return
        detector?.stop()
        isListening = false
    }

    // The library bakes the threshold in at build time, so a change needs a rebuild.
    override fun setThreshold(value: Float) {
        if (value == threshold) return
        val wasListening = isListening
        release()
        threshold = value
        if (wasListening) start()
    }

    override fun release() {
        detector?.release()
        detector = null
        isListening = false
    }

    companion object {
        private const val TAG = "OpenWakeWordDetector"
    }
}
