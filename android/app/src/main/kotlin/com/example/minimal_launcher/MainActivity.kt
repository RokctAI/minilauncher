package com.example.minimal_launcher

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // launch_sdk is a package, not a plugin: nothing registers its Kotlin
        // for it, so the default-launcher ask stays silent until the host
        // Activity wires the channel up. Needs an Activity, not the
        // application context - both arms of the ask start system UI.
        DefaultHomeBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
