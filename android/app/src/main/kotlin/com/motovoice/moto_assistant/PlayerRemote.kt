package com.motovoice.moto_assistant

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.browse.MediaBrowser
import android.media.session.MediaController
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.media.MediaBrowserService
import android.util.Log

// Remote control for the rider's own music app through its public MediaBrowserService, so shuffle runs
// in that app with its library and queue. Needs no permission beyond package visibility (<queries>).
object PlayerRemote {
    private const val TAG = "PlayerRemote"

    // MediaSessionCompat / media3 (used by nearly every player) map these custom actions to setShuffleMode;
    // the platform TransportControls has no shuffle method of its own.
    private const val ACTION_SET_SHUFFLE_MODE = "android.support.v4.media.session.action.SET_SHUFFLE_MODE"
    private const val ARGUMENT_SHUFFLE_MODE = "android.support.v4.media.session.action.ARGUMENT_SHUFFLE_MODE"
    private const val SHUFFLE_MODE_ALL = 1

    // Kept connected: some players stop their service (and the music) when the last client unbinds.
    private var browser: MediaBrowser? = null

    fun shuffle(app: Context, pkg: String, done: (Boolean) -> Unit) {
        val service = app.packageManager
            .queryIntentServices(Intent(MediaBrowserService.SERVICE_INTERFACE).setPackage(pkg), 0)
            .firstOrNull()?.serviceInfo
        if (service == null) {
            Log.i(TAG, "$pkg has no media browser service")
            return done(false)
        }

        var answered = false
        fun answer(ok: Boolean) {
            if (!answered) { answered = true; done(ok) }
        }
        Handler(Looper.getMainLooper()).postDelayed({ answer(false) }, 5000)

        browser?.disconnect()
        browser = MediaBrowser(app, ComponentName(service.packageName, service.name), object : MediaBrowser.ConnectionCallback() {
            override fun onConnected() {
                val controls = MediaController(app, browser!!.sessionToken).transportControls
                controls.sendCustomAction(ACTION_SET_SHUFFLE_MODE, Bundle().apply { putInt(ARGUMENT_SHUFFLE_MODE, SHUFFLE_MODE_ALL) })
                // An empty search means "play something" in the MediaSession contract; players start their library.
                controls.playFromSearch("", Bundle())
                Log.i(TAG, "Asked $pkg to shuffle all and play")
                answer(true)
            }

            override fun onConnectionFailed() {
                Log.w(TAG, "$pkg refused the media browser connection")
                answer(false)
            }
        }, null).also { it.connect() }
    }
}
