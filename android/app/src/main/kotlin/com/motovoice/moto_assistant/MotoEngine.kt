package com.motovoice.moto_assistant

import android.app.SearchManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.MediaStore
import android.speech.SpeechRecognizer
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.util.Log
import android.view.KeyEvent
import androidx.core.content.ContextCompat
import com.motovoice.moto_assistant.wakeword.MicRoute
import com.motovoice.moto_assistant.wakeword.OpenWakeWordDetector
import com.motovoice.moto_assistant.wakeword.SherpaWakeDetector
import com.motovoice.moto_assistant.wakeword.WakeDetector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.min

// One Flutter engine for the whole process, so Dart keeps running (and handles "Hey Jarvis")
// after the activity is closed while WakeWordService holds the process alive.
object MotoEngine {
    private const val AUDIO_CHANNEL = "com.motovoice.moto_assistant/audio_routing"
    private const val MEDIA_CHANNEL = "com.motovoice.moto_assistant/media_control"
    private const val WAKEWORD_CHANNEL = "com.motovoice.moto_assistant/wakeword"

    private var engine: FlutterEngine? = null
    private var wakeChannel: MethodChannel? = null
    private var focusRequest: AudioFocusRequest? = null
    private val tone by lazy { ToneGenerator(AudioManager.STREAM_MUSIC, 90) }

    var detector: WakeDetector? = null
        private set
    private var detectorEngine = DEFAULT_ENGINE

    // Must match SettingsService.defaultWakeEngine on the Dart side.
    private const val DEFAULT_ENGINE = "sherpa_giga"

    fun get(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val e = FlutterEngine(app)
        detector = createDetector(app, DEFAULT_ENGINE)
        registerWakeChannel(app, e)
        registerAudioChannel(app, e)
        registerMediaChannel(app, e)
        engine = e
        return e
    }

    private fun createDetector(app: Context, engineName: String): WakeDetector {
        val onDetected = { score: Float, keyword: String ->
            wakeChannel?.invokeMethod("onWakeWordDetected", mapOf("score" to score, "keyword" to keyword))
            Unit
        }
        return when (engineName) {
            "sherpa_phone" -> SherpaWakeDetector(app, "phone", onDetected)
            "sherpa_giga" -> SherpaWakeDetector(app, "giga", onDetected)
            else -> OpenWakeWordDetector(app, onDetected)
        }
    }

    fun notifyRidingMode(enabled: Boolean) {
        wakeChannel?.invokeMethod("onRidingModeChanged", enabled)
    }

    private fun registerWakeChannel(app: Context, e: FlutterEngine) {
        wakeChannel = MethodChannel(e.dartExecutor.binaryMessenger, WAKEWORD_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRidingMode" -> {
                        try {
                            if (call.argument<Boolean>("enabled") == true) WakeWordService.start(app)
                            else WakeWordService.stop(app)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.success(false)
                        }
                    }
                    "isRidingMode" -> result.success(WakeWordService.isRunning)
                    // Resume/pause between commands; the service decides whether listening is allowed at all.
                    "startWakeWord" -> {
                        if (WakeWordService.isRunning) detector?.start()
                        result.success(true)
                    }
                    "stopWakeWord" -> {
                        detector?.pause()
                        result.success(true)
                    }
                    "setThreshold" -> {
                        detector?.setThreshold(call.argument<Double>("threshold")?.toFloat() ?: 0.25f)
                        result.success(true)
                    }
                    // Dart sends setEngine then setThreshold, so the new detector gets that engine's threshold.
                    // Dart calls this on every app open; only swap (and reload models) when the engine changed.
                    "setEngine" -> {
                        val name = call.argument<String>("engine") ?: DEFAULT_ENGINE
                        if (name != detectorEngine) {
                            val wasListening = detector?.isListening == true
                            detector?.release()
                            detector = createDetector(app, name)
                            detectorEngine = name
                            if (wasListening) detector?.start()
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun registerAudioChannel(app: Context, e: FlutterEngine) {
        val audioManager = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.clearCommunicationDevice()
        audioManager.mode = AudioManager.MODE_NORMAL

        // The SCO link comes up asynchronously after setCommunicationDevice, so the wake-word mic is switched
        // here, when Android reports the change (also covers the helmet disconnecting on its own).
        audioManager.addOnCommunicationDeviceChangedListener(ContextCompat.getMainExecutor(app)) { device ->
            MicRoute.helmetMic = if (device?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
                audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            } else null
            Log.i("MotoEngine", "Communication device -> ${device?.productName}; helmet mic=${MicRoute.helmetMic != null}")
            detector?.let {
                if (it.isListening) {
                    it.pause()
                    it.start()
                }
            }
        }

        MethodChannel(e.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Intercom mode: route voice (wake word + commands) through the helmet's Bluetooth mic.
                "startBluetoothSco" -> {
                    try {
                        val sco = audioManager.availableCommunicationDevices
                            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                        if (sco == null) {
                            result.success(false)
                        } else {
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            result.success(audioManager.setCommunicationDevice(sco))
                        }
                    } catch (ex: Exception) {
                        result.error("SCO_ERROR", ex.localizedMessage, null)
                    }
                }
                "stopBluetoothSco", "resetToNormal" -> {
                    try {
                        audioManager.clearCommunicationDevice()
                        audioManager.mode = AudioManager.MODE_NORMAL
                        result.success(true)
                    } catch (ex: Exception) {
                        result.error("SCO_ERROR", ex.localizedMessage, null)
                    }
                }
                "isBluetoothScoOn" -> result.success(
                    audioManager.communicationDevice?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                )
                "adjustVolume" -> {
                    val direction = call.argument<String>("direction") ?: "up"
                    val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    when (direction) {
                        "up" -> audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                        "down" -> audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                        "mute" -> audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, AudioManager.FLAG_SHOW_UI)
                        "unmute" -> audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol / 2, AudioManager.FLAG_SHOW_UI)
                        "max" -> audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, AudioManager.FLAG_SHOW_UI)
                    }
                    result.success(true)
                }
                "setVolumePercent" -> {
                    val percent = (call.argument<Int>("percent") ?: 50).coerceIn(0, 100)
                    val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val level = ((percent / 100.0) * maxVol).toInt().coerceIn(0, maxVol)
                    audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, level, AudioManager.FLAG_SHOW_UI)
                    result.success(true)
                }
                // Transient + may-duck: the music app lowers its volume while the command is heard,
                // then returns to normal on abandon. A "pause" command still sticks.
                "requestAudioFocus" -> {
                    val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                        )
                        .build()
                    focusRequest = req
                    result.success(audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
                }
                "abandonAudioFocus" -> {
                    focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
                    focusRequest = null
                    result.success(true)
                }
                // Media stream so the cue reaches a Bluetooth helmet headset along with the music.
                "beep" -> {
                    tone.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
                    result.success(true)
                }
                "isOnDeviceSpeechAvailable" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(app)
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun registerMediaChannel(app: Context, e: FlutterEngine) {
        val audioManager = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(e.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playMediaFromSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    val targetPackage = call.argument<String>("package")
                    try {
                        var launched = false

                        val localUri = findLocalSongUri(app, query)
                        if (localUri != null) {
                            try {
                                val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(localUri, "audio/*")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    if (!targetPackage.isNullOrEmpty()) setPackage(targetPackage)
                                }
                                app.startActivity(viewIntent)
                                launched = true
                            } catch (ex: Exception) {
                                println("[MotoVoice Native] ACTION_VIEW failed: ${ex.message}")
                            }
                        }

                        if (!launched && !targetPackage.isNullOrEmpty()) {
                            try {
                                val searchIntent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                    putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/audio")
                                    putExtra(SearchManager.QUERY, query)
                                    putExtra(MediaStore.EXTRA_MEDIA_TITLE, query)
                                    putExtra(MediaStore.EXTRA_MEDIA_ARTIST, query)
                                    putExtra("android.intent.extra.title", query)
                                    putExtra("autostart", true)
                                    setPackage(targetPackage)
                                }
                                if (searchIntent.resolveActivity(app.packageManager) != null) {
                                    app.startActivity(searchIntent)
                                    launched = true
                                }
                            } catch (_: Exception) {}

                            if (!launched) {
                                val launchIntent = app.packageManager.getLaunchIntentForPackage(targetPackage)
                                if (launchIntent != null) {
                                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    app.startActivity(launchIntent)
                                    launched = true
                                    Handler(Looper.getMainLooper()).postDelayed({
                                        try {
                                            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY))
                                            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY))
                                        } catch (_: Exception) {}
                                    }, 800)
                                }
                            }
                        }

                        if (!launched) {
                            val genericIntent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/audio")
                                putExtra(SearchManager.QUERY, query)
                                putExtra(MediaStore.EXTRA_MEDIA_TITLE, query)
                                putExtra("autostart", true)
                            }
                            app.startActivity(genericIntent)
                        }
                        result.success(true)
                    } catch (ex: Exception) {
                        result.error("MEDIA_INTENT_ERROR", ex.localizedMessage, null)
                    }
                }
                "sendMediaKeyEvent" -> {
                    val keyCode = when (call.argument<String>("action") ?: "play_pause") {
                        "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                        "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                        "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                        "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    }
                    try {
                        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
                        result.success(true)
                    } catch (ex: Exception) {
                        result.error("KEY_EVENT_ERROR", ex.localizedMessage, null)
                    }
                }
                "openApp" -> {
                    val pm = app.packageManager
                    val name = call.argument<String>("name") ?: ""
                    val pkg = call.argument<String>("package")
                        ?: pm.queryIntentActivities(
                            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0
                        ).map { it.activityInfo.packageName to it.loadLabel(pm).toString().lowercase() }
                            .let { apps ->
                                apps.firstOrNull { it.second == name }
                                    ?: apps.firstOrNull { it.second.contains(name) || name.contains(it.second) }
                                    ?: apps.filter { similarity(name, it.second) >= 0.6 }
                                        .maxByOrNull { similarity(name, it.second) }
                            }?.first
                    val launch = pkg?.let { pm.getLaunchIntentForPackage(it) }
                    if (launch == null) {
                        result.success(false)
                    } else {
                        try {
                            app.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } catch (ex: Exception) {
                            result.success(false)
                        }
                    }
                }
                "shuffleInPlayer" -> PlayerRemote.shuffle(app, call.argument<String>("package") ?: "") { result.success(it) }
                "findContacts" -> {
                    try {
                        result.success(findContacts(app, call.argument<String>("name") ?: ""))
                    } catch (ex: SecurityException) {
                        result.error("NO_CONTACTS_PERMISSION", ex.localizedMessage, null)
                    }
                }
                // TelecomManager.placeCall works with the screen off; startActivity(ACTION_CALL) is blocked from the background.
                "listSims" -> result.success(simAccounts(app).map { it.second })
                "makePhoneCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val sim = call.argument<String>("sim")
                    try {
                        val telecom = app.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                        // Naming the SIM skips Android's "Choose SIM for this call" pop-up on dual-SIM phones.
                        val extras = Bundle()
                        simAccounts(app).firstOrNull { it.second == sim }
                            ?.let { extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it.first) }
                        telecom.placeCall(Uri.parse("tel:$phoneNumber"), extras)
                        result.success(true)
                    } catch (ex: Exception) {
                        result.error("CALL_ERROR", ex.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Call-capable SIMs in slot order with their carrier name (e.g. "Namaste", "Ncell"). The name comes from
    // the SIM subscription: the telecom PhoneAccount label is not the carrier name on every phone (Nothing A059).
    // A SIM's PhoneAccountHandle id is its subscription id. Empty without READ_PHONE_STATE.
    private fun simAccounts(app: Context): List<Pair<PhoneAccountHandle, String>> = try {
        val telecom = app.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val subs = app.getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList.orEmpty()
        telecom.callCapablePhoneAccounts
            .mapNotNull { handle ->
                val sub = subs.firstOrNull { it.subscriptionId.toString() == handle.id } ?: return@mapNotNull null
                Triple(handle, sub.displayName?.toString() ?: "SIM ${sub.simSlotIndex + 1}", sub.simSlotIndex)
            }
            .sortedBy { it.third }
            .map { it.first to it.second }
            .also { Log.i("MotoEngine", "SIMs for calls: ${it.map { sim -> sim.second }}") }
    } catch (ex: SecurityException) {
        emptyList()
    }

    // Best contacts for a spoken name, highest score first. Scores the whole name and each word of it,
    // so "call John" finds "John Smith" and speech-to-text slips like "Jon" still match.
    private fun findContacts(app: Context, spoken: String): List<Map<String, Any>> {
        val query = spoken.trim().lowercase()
        if (query.isEmpty()) return emptyList()
        val best = mutableMapOf<String, Pair<String, Double>>() // display name -> (number, score)
        app.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(0) ?: continue
                val number = c.getString(1) ?: continue
                val lower = name.lowercase()
                val score = if (lower == query) 1.0
                    else maxOf(similarity(query, lower), lower.split(' ').maxOf { similarity(query, it) } - 0.05)
                if (score >= 0.6 && score > (best[name]?.second ?: 0.0)) best[name] = number to score
            }
        }
        // An exact name ("Daddy") beats contacts that merely contain it ("sudi ko daddy", "T V DADDY EXT").
        val exact = best.filterValues { it.second == 1.0 }
        return (exact.ifEmpty { best }).entries.sortedByDescending { it.value.second }.take(3)
            .map { mapOf("name" to it.key, "number" to it.value.first, "score" to it.value.second) }
    }

    private fun similarity(s1: String, s2: String): Double {
        val longer = if (s1.length >= s2.length) s1 else s2
        val shorter = if (s1.length < s2.length) s1 else s2
        if (longer.isEmpty()) return 1.0
        return (longer.length - levenshteinDistance(longer, shorter)).toDouble() / longer.length.toDouble()
    }

    private fun levenshteinDistance(s1: String, s2: String): Int {
        val costs = IntArray(s2.length + 1)
        for (j in costs.indices) costs[j] = j
        for (i in 1..s1.length) {
            costs[0] = i
            var nw = i - 1
            for (j in 1..s2.length) {
                val cj = min(1 + min(costs[j], costs[j - 1]), if (s1[i - 1] == s2[j - 1]) nw else nw + 1)
                nw = costs[j]
                costs[j] = cj
            }
        }
        return costs[s2.length]
    }

    private fun findLocalSongUri(app: Context, query: String): Uri? {
        if (query.isBlank()) return null
        val cleanQuery = query.trim().lowercase()
        try {
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.ARTIST
            )
            app.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, null, null,
                "${MediaStore.Audio.Media.TITLE} ASC"
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)

                var bestMatchId: Long? = null
                var highestSimilarity = 0.0

                while (cursor.moveToNext()) {
                    val title = cursor.getString(titleCol)?.lowercase() ?: ""
                    val name = cursor.getString(nameCol)?.lowercase() ?: ""
                    val id = cursor.getLong(idCol)

                    if (title == cleanQuery || name.startsWith(cleanQuery) ||
                        title.contains(cleanQuery) || cleanQuery.contains(title)
                    ) {
                        return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                    }

                    val sim = max(similarity(cleanQuery, title), similarity(cleanQuery, name))
                    if (sim > highestSimilarity && sim >= 0.55) {
                        highestSimilarity = sim
                        bestMatchId = id
                    }
                }

                if (bestMatchId != null) {
                    return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, bestMatchId)
                }
            }
        } catch (ex: Exception) {
            println("[MotoVoice Native] MediaStore Query Error: ${ex.message}")
        }
        return null
    }
}
