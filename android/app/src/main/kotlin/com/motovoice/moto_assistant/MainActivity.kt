package com.motovoice.moto_assistant

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // A host-provided engine is not destroyed with the activity, so Dart survives the screen closing.
    override fun provideFlutterEngine(context: Context): FlutterEngine = MotoEngine.get(context)
}
