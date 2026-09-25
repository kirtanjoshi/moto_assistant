package com.motovoice.moto_assistant

import android.app.SearchManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterActivity() {
    private val AUDIO_CHANNEL = "com.motovoice.moto_assistant/audio_routing"
    private val MEDIA_CHANNEL = "com.motovoice.moto_assistant/media_control"

    // Levenshtein distance for fuzzy matching speech to local song titles
    private fun similarity(s1: String, s2: String): Double {
        val longer = if (s1.length >= s2.length) s1 else s2
        val shorter = if (s1.length < s2.length) s1 else s2
        if (longer.isEmpty()) return 1.0
        val editDistance = levenshteinDistance(longer, shorter)
        return (longer.length - editDistance).toDouble() / longer.length.toDouble()
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

    private fun findLocalSongUri(query: String): Uri? {
        if (query.isBlank()) return null
        val cleanQuery = query.trim().lowercase()
        println("[MotoVoice Native] Fuzzy searching MediaStore for: '$cleanQuery'")

        try {
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.ARTIST
            )
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Audio.Media.TITLE} ASC"
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)

                var bestMatchId: Long? = null
                var highestSimilarity = 0.0

                while (cursor.moveToNext()) {
                    val title = cursor.getString(titleCol)?.lowercase() ?: ""
                    val name = cursor.getString(nameCol)?.lowercase() ?: ""
                    val artist = cursor.getString(artistCol)?.lowercase() ?: ""
                    val id = cursor.getLong(idCol)

                    // 1. Direct contains or exact match
                    if (title == cleanQuery || name.startsWith(cleanQuery)) {
                        println("[MotoVoice Native] Exact Match: '$title' (ID: $id)")
                        return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                    }

                    if (title.contains(cleanQuery) || cleanQuery.contains(title)) {
                        println("[MotoVoice Native] Substring Match: '$title' (ID: $id)")
                        return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                    }

                    // 2. Fuzzy Levenshtein comparison against title and artist
                    val sim = max(similarity(cleanQuery, title), similarity(cleanQuery, name))
                    if (sim > highestSimilarity && sim >= 0.55) {
                        highestSimilarity = sim
                        bestMatchId = id
                        println("[MotoVoice Native] Candidate: '$title' (similarity: $sim)")
                    }
                }

                if (bestMatchId != null) {
                    println("[MotoVoice Native] Selected Best Fuzzy Match: (ID: $bestMatchId, score: $highestSimilarity)")
                    return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, bestMatchId)
                }
            }
        } catch (e: Exception) {
            println("[MotoVoice Native] MediaStore Query Error: ${e.message}")
        }
        println("[MotoVoice Native] No song found for: '$cleanQuery'")
        return null
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.isBluetoothScoOn = false
        audioManager.mode = AudioManager.MODE_NORMAL

        // Audio Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBluetoothSco" -> {
                    try {
                        if (audioManager.isBluetoothScoAvailableOffCall) {
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            audioManager.startBluetoothSco()
                            audioManager.isBluetoothScoOn = true
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("SCO_ERROR", e.localizedMessage, null)
                    }
                }
                "stopBluetoothSco", "resetToNormal" -> {
                    try {
                        audioManager.stopBluetoothSco()
                        audioManager.isBluetoothScoOn = false
                        audioManager.mode = AudioManager.MODE_NORMAL
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SCO_ERROR", e.localizedMessage, null)
                    }
                }
                "isBluetoothScoOn" -> {
                    result.success(audioManager.isBluetoothScoOn)
                }
                "adjustVolume" -> {
                    val direction = call.argument<String>("direction") ?: "up"
                    when (direction) {
                        "up" -> audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                        "down" -> audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                        "mute" -> audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, AudioManager.FLAG_SHOW_UI)
                        "max" -> {
                            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, max, AudioManager.FLAG_SHOW_UI)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Media Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playMediaFromSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    val targetPackage = call.argument<String>("package")
                    try {
                        var launched = false

                        // 1. Search local phone storage with fuzzy tolerance
                        val localUri = findLocalSongUri(query)
                        if (localUri != null) {
                            try {
                                println("[MotoVoice Native] Playing exact matched song: $localUri on package: $targetPackage")
                                val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(localUri, "audio/*")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    if (!targetPackage.isNullOrEmpty()) {
                                        setPackage(targetPackage)
                                    }
                                }
                                context.startActivity(viewIntent)
                                launched = true
                            } catch (e: Exception) {
                                println("[MotoVoice Native] ACTION_VIEW failed: ${e.message}")
                            }
                        }

                        // 2. If no local song or target is streaming (Spotify, YouTube Music)
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
                                if (searchIntent.resolveActivity(packageManager) != null) {
                                    context.startActivity(searchIntent)
                                    launched = true
                                }
                            } catch (_: Exception) {}

                            // Fallback: Launch app and trigger play
                            if (!launched) {
                                val launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
                                if (launchIntent != null) {
                                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    context.startActivity(launchIntent)
                                    launched = true

                                    Handler(Looper.getMainLooper()).postDelayed({
                                        try {
                                            val down = KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY)
                                            val up = KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY)
                                            audioManager.dispatchMediaKeyEvent(down)
                                            audioManager.dispatchMediaKeyEvent(up)
                                        } catch (_: Exception) {}
                                    }, 800)
                                }
                            }
                        }

                        // 3. Fallback: Generic chooser
                        if (!launched) {
                            val genericIntent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/audio")
                                putExtra(SearchManager.QUERY, query)
                                putExtra(MediaStore.EXTRA_MEDIA_TITLE, query)
                                putExtra("autostart", true)
                            }
                            context.startActivity(genericIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_INTENT_ERROR", e.localizedMessage, null)
                    }
                }
                "sendMediaKeyEvent" -> {
                    val action = call.argument<String>("action") ?: "play_pause"
                    val keyCode = when (action) {
                        "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                        "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                        "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                        "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    }
                    try {
                        val eventDown = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                        val eventUp = KeyEvent(KeyEvent.ACTION_UP, keyCode)
                        audioManager.dispatchMediaKeyEvent(eventDown)
                        audioManager.dispatchMediaKeyEvent(eventUp)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("KEY_EVENT_ERROR", e.localizedMessage, null)
                    }
                }
                "makePhoneCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_CALL).apply {
                            data = Uri.parse("tel:$phoneNumber")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CALL_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
