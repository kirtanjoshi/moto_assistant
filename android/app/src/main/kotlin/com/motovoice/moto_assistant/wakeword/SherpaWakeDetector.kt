package com.motovoice.moto_assistant.wakeword

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig
import java.util.Locale

/**
 * Open-vocabulary keyword spotting with Sherpa-ONNX. [model] is an asset folder under kws/:
 * "giga" (GigaSpeech BPE tokens) or "phone" (ARPAbet phonemes, with V/B accent variants).
 * Jarvis phrases live in kws/<model>/keywords.txt; Moto phrases are added per stream with stricter thresholds.
 */
class SherpaWakeDetector(
    private val context: Context,
    private val model: String,
    private val onDetected: (score: Float, keyword: String) -> Unit,
) : WakeDetector {
    private var spotter: KeywordSpotter? = null
    private var threshold = 0.25f
    private var thread: Thread? = null
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var running = false
    @Volatile override var isListening = false
        private set

    override fun start() {
        if (isListening) return
        isListening = true
        running = true
        thread = Thread({ loop() }, "SherpaKws").apply { start() }
    }

    override fun pause() {
        if (!isListening) return
        running = false
        thread?.join(1000)
        thread = null
        isListening = false
    }

    // The global threshold is part of the spotter config, so a change rebuilds it (models reload in ~0.2 s).
    override fun setThreshold(value: Float) {
        if (value == threshold) return
        val wasListening = isListening
        release()
        threshold = value
        if (wasListening) start()
    }

    override fun release() {
        pause()
        spotter?.release()
        spotter = null
    }

    private fun buildSpotter() = KeywordSpotter(
        context.assets,
        KeywordSpotterConfig(
            featConfig = FeatureConfig(sampleRate = SAMPLE_RATE, featureDim = 80),
            modelConfig = OnlineModelConfig(
                transducer = OnlineTransducerModelConfig(
                    encoder = "kws/$model/encoder.onnx",
                    decoder = "kws/$model/decoder.onnx",
                    joiner = "kws/$model/joiner.onnx",
                ),
                tokens = "kws/$model/tokens.txt",
                modelType = "zipformer2",
                numThreads = 1,
            ),
            keywordsFile = "kws/$model/keywords.txt",
            keywordsThreshold = threshold,
        ),
    )

    // "Moto" is close to "motor"/"motorcycle" and "oi" is an everyday Nepali call, so these trigger less easily.
    private fun motoKeywords(): String {
        val hey = "%.2f".format(Locale.US, (threshold + 0.10f).coerceAtMost(0.95f))
        val oi = "%.2f".format(Locale.US, (threshold + 0.15f).coerceAtMost(0.95f))
        return when (model) {
            "giga" -> "▁HE Y ▁MO T O #$hey @HEY_MOTO/▁O I ▁MO T O #$oi @OI_MOTO/▁O Y ▁MO T O #$oi @OI_MOTO"
            else -> "HH EY1 M OW1 T OW0 #$hey @HEY_MOTO/OY1 M OW1 T OW0 #$oi @OI_MOTO"
        }
    }

    @SuppressLint("MissingPermission") // RECORD_AUDIO is granted before riding mode can start.
    private fun loop() {
        // Continuous inference, not latency-sensitive: background priority biases the scheduler
        // toward little cores instead of the A720 performance core, cutting battery drain.
        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
        val kws = try {
            spotter ?: buildSpotter().also { spotter = it }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model '$model'", e)
            isListening = false
            return
        }
        val stream = kws.createStream(motoKeywords())
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val helmetMic = MicRoute.helmetMic
        // Bluetooth SCO mic is only reachable through the voice-communication path. The phone mic uses the raw
        // UNPROCESSED source: on the Nothing A059 it gave the range needed to trigger from a chair at a table.
        val source = if (helmetMic != null) MediaRecorder.AudioSource.VOICE_COMMUNICATION
            else MediaRecorder.AudioSource.UNPROCESSED
        val rec = AudioRecord(
            source, SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, CHUNK * 4),
        )
        if (helmetMic != null) rec.preferredDevice = helmetMic
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord init failed")
            rec.release()
            stream.release()
            isListening = false
            return
        }
        Log.i(TAG, "Listening with model '$model', threshold=$threshold, audioSource=$source, " +
            "mic=${if (helmetMic != null) "helmet (${helmetMic.productName})" else "phone"}")

        val pcm = ShortArray(CHUNK)
        val samples = FloatArray(CHUNK)
        val micGain = MicGain()
        var chunks = 0
        // Delete the voice recordings older test builds left behind.
        java.io.File(context.cacheDir, "kws_dump.pcm").delete()
        java.io.File(context.filesDir, "audio_source").delete()
        try {
            rec.startRecording()
            while (running) {
                val n = rec.read(pcm, 0, CHUNK)
                if (n != CHUNK) continue
                micGain.apply(pcm)
                for (i in 0 until n) samples[i] = pcm[i] / 32768f
                stream.acceptWaveform(samples, SAMPLE_RATE)
                while (kws.isReady(stream)) kws.decode(stream)

                val keyword = kws.getResult(stream).keyword
                if (keyword.isNotEmpty()) {
                    kws.reset(stream)
                    Log.i(TAG, "Keyword detected: $keyword (level=%.0f gain=%.1fx)".format(micGain.lastLevel, micGain.gain))
                    main.post {
                        if (isListening) {
                            pause()
                            onDetected(1f, keyword)
                        }
                    }
                }
                if (++chunks % STATS_EVERY_CHUNKS == 0) {
                    Log.d(TAG, "level=%.0f gain=%.1fx".format(micGain.lastLevel, micGain.gain))
                }
            }
        } finally {
            try { rec.stop() } catch (_: Exception) {}
            rec.release()
            stream.release()
        }
    }

    companion object {
        private const val TAG = "SherpaWakeDetector"
        private const val SAMPLE_RATE = 16000
        private const val CHUNK = 1600 // 100 ms
        private const val STATS_EVERY_CHUNKS = 20 // ~2 s
    }
}
