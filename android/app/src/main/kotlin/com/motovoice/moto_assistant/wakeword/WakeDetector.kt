package com.motovoice.moto_assistant.wakeword

import android.media.AudioDeviceInfo
import kotlin.math.sqrt

// Non-null while intercom mode routes voice through the helmet's Bluetooth mic. Detectors read it when they
// (re)open the mic; MotoEngine restarts them whenever it changes.
object MicRoute {
    @Volatile var helmetMic: AudioDeviceInfo? = null
}

// Common shape for the wake engines under A/B test (openWakeWord vs Sherpa-ONNX); keep only the winner.
interface WakeDetector {
    val isListening: Boolean
    fun start()
    fun pause()
    fun setThreshold(value: Float)
    fun release()
}

// Speech at arm's length on the Nothing A059 arrived too quiet for the models; normalise toward TARGET_RMS.
// ponytail: fixed target + cap; tune from the "level" logs if range or false wakes change.
class MicGain {
    private var level = 0f
    var gain = 1f
        private set
    var lastLevel = 0f
        private set

    fun apply(frame: ShortArray, n: Int = frame.size) {
        var sumSq = 0.0
        for (i in 0 until n) sumSq += frame[i] * frame[i].toDouble()
        val rms = sqrt(sumSq / n).toFloat()
        // Fast attack, slow release, so gain follows the rider's voice rather than each syllable.
        level = maxOf(rms, level * LEVEL_DECAY)
        lastLevel = level
        gain = (TARGET_RMS / maxOf(level, 1f)).coerceIn(1f, MAX_GAIN)
        if (gain > 1f) {
            for (i in 0 until n) frame[i] = (frame[i] * gain).coerceIn(-32768f, 32767f).toInt().toShort()
        }
    }

    private companion object {
        const val TARGET_RMS = 3000f
        const val MAX_GAIN = 8f
        const val LEVEL_DECAY = 0.98f // per ~80-100 ms frame: ~2.7 s release
    }
}
