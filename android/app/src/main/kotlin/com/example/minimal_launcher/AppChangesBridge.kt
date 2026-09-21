package com.example.minimal_launcher

import android.app.Activity
import android.content.Context
import android.content.pm.LauncherApps
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Tells the launcher when the set of installed apps changes, so it does not
 * have to keep asking.
 *
 * Ray, 2026-09-21: "how do other launchers remember when app has installed
 * and put icon in their screen? ours is the only app that first wait to
 * load". A real launcher does not enumerate every installed package when it
 * starts; it keeps its own list and is TOLD when that list changes. The
 * keeping is launch_sdk's LaunchAppCatalogStore and LauncherIconStore; this
 * is the telling.
 *
 * [LauncherApps] is the right source rather than the PACKAGE_ADDED broadcast:
 * it is the platform's own launcher API, it needs no manifest receiver and no
 * permission, it reports across work profiles, and from API 30 it is not
 * subject to the package-visibility filtering that a broadcast is. It is API
 * 21+ and the fleet's minSdkVersion is 24, so no version guard.
 *
 * Android only, by design (Ray, same day: "launcher will only be in android
 * only. no ios. the variation will only be huawei"). A Huawei device is still
 * Android and still serves LauncherApps - HMS replaces Google's SERVICES, not
 * the package manager - so the same bridge covers that variation with nothing
 * added.
 *
 * Transport only: this reports THAT something changed and which package, and
 * launch_sdk decides what to do about it. The events carry no icon and no app
 * list, because the Dart side already knows how to ask for those and doing it
 * here would put a second source of truth on the wire.
 */
object AppChangesBridge {

    const val CHANNEL = "rokct.launch_sdk/app_changes"

    /**
     * Registered against the APPLICATION context, not the activity: app
     * installs happen while the launcher is in the background, and a callback
     * tied to an activity would miss exactly those. The activity is still the
     * parameter the host's reflective registration passes, matching every
     * other optional bridge.
     */
    fun register(messenger: BinaryMessenger, activity: Activity) {
        val context = activity.applicationContext
        EventChannel(messenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var callback: LauncherApps.Callback? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    val launcherApps = context.getSystemService(
                        Context.LAUNCHER_APPS_SERVICE,
                    ) as? LauncherApps
                    if (launcherApps == null) {
                        // Nothing to listen to. Not an error the launcher can
                        // do anything about: it keeps refreshing on resume as
                        // it did before this bridge existed.
                        events.endOfStream()
                        return
                    }
                    val handler = Handler(Looper.getMainLooper())
                    val registered = object : LauncherApps.Callback() {
                        override fun onPackageAdded(packageName: String?, user: UserHandle?) {
                            send(events, "added", packageName)
                        }

                        override fun onPackageRemoved(packageName: String?, user: UserHandle?) {
                            send(events, "removed", packageName)
                        }

                        override fun onPackageChanged(packageName: String?, user: UserHandle?) {
                            // An update, or a component being enabled or
                            // disabled. The label and the icon can both have
                            // changed, so it is worth the same refresh.
                            send(events, "changed", packageName)
                        }

                        override fun onPackagesAvailable(
                            packageNames: Array<out String>?,
                            user: UserHandle?,
                            replacing: Boolean,
                        ) {
                            // External storage came back, so these apps are
                            // launchable again.
                            send(events, "available", packageNames?.firstOrNull())
                        }

                        override fun onPackagesUnavailable(
                            packageNames: Array<out String>?,
                            user: UserHandle?,
                            replacing: Boolean,
                        ) {
                            send(events, "unavailable", packageNames?.firstOrNull())
                        }
                    }
                    launcherApps.registerCallback(registered, handler)
                    callback = registered
                }

                override fun onCancel(arguments: Any?) {
                    val registered = callback ?: return
                    callback = null
                    val launcherApps = context.getSystemService(
                        Context.LAUNCHER_APPS_SERVICE,
                    ) as? LauncherApps
                    launcherApps?.unregisterCallback(registered)
                }

                /**
                 * Every callback arrives on the main looper because that is
                 * the handler above, which is also where the Flutter event
                 * sink must be touched, so no hop is needed.
                 */
                private fun send(
                    events: EventChannel.EventSink,
                    change: String,
                    packageName: String?,
                ) {
                    events.success(
                        mapOf(
                            "change" to change,
                            "package_name" to (packageName ?: ""),
                        ),
                    )
                }
            },
        )
    }
}
