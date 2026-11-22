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
        // Same reason, and the reason the launcher does not have to enumerate
        // every installed package to notice an install: this one reports app
        // changes as they happen. It keeps its own callback on the
        // application context, so a background install is not missed.
        AppChangesBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
        // Hosts the Bible app's verse-of-the-day widget on the launcher home
        // (launch_sdk 1.28.0). The platform view factory has to be registered
        // on the engine itself, so this takes the engine, not the messenger.
        LauncherVerseWidgetBridge.register(flutterEngine, this)
        // The launcher's own phone (launch_sdk 1.29.23): dialer role, call
        // log, contacts and the live call. Without this line Allow, Recents,
        // Contacts and calling all did nothing (Ray, 2026-11-22).
        LauncherPhoneBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
