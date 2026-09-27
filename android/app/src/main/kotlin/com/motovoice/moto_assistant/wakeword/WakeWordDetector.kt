package com.motovoice.moto_assistant.wakeword

import android.content.Context
import android.util.Log

class WakeWordDetector(
    private val context: Context,
    private val onDetected: (score: Float) -> Unit,
) {
    private var detector: OpenWakeWord? = null
    private var threshold = 0.5f
    var isListening = false
        private set

    fun start() {
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
            onDetected(score)
        }
        isListening = true
    }

    // Keeps the ONNX models loaded so resuming is cheap.
    fun pause() {
        if (!isListening) return
        detector?.stop()
        isListening = false
    }

    // The library bakes the threshold in at build time, so a change needs a rebuild.
    fun setThreshold(value: Float) {
        val wasListening = isListening
        detector?.release()
        detector = null
        isListening = false
        threshold = value
        if (wasListening) start()
    }

    companion object {
        private const val TAG = "WakeWordDetector"
    }
}
