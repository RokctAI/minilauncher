package com.example.minimal_launcher

import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Platform plumbing for the launcher's one question the framework cannot
 * answer: is this app the device's home screen, and if not, ask the user to
 * make it one.
 *
 * Transport only. WHEN the ask happens is launch_sdk's DefaultHomePrompt (at
 * most once per install, never when already the default, never on a platform
 * that cannot be asked); the Dart half of this channel is its
 * DefaultHomeService.
 *
 * Needs an Activity, not the application context: both arms start system UI
 * for a result the user gives.
 *
 * This file lives in the app's own Kotlin package on purpose. launch_sdk
 * installs the canonical copy into the package that this shell's Gradle
 * `namespace` does not use, and the Android build prunes every Kotlin source
 * outside the namespace before it compiles - so the installed copy is thrown
 * away and the channel would answer nothing. Keep it byte-identical to
 * launch_sdk's (launch/dart/templates/android/.../DefaultHomeBridge.kt) apart
 * from the package declaration.
 */
object DefaultHomeBridge {

    const val CHANNEL = "rokct.launch_sdk/default_home"

    /**
     * Arbitrary, local to this bridge: the ask is fire-and-forget, so the
     * code exists only because startActivityForResult requires one. The
     * user's answer is deliberately never read back - a launcher behaves
     * identically either way, and reacting to a "no" is how an app ends up
     * asking twice.
     */
    private const val REQUEST_CODE = 0x484d

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefaultHome" -> result.success(isDefaultHome(activity))
                "requestDefaultHome" -> result.success(requestDefaultHome(activity))
                "defaultDialPackage" -> result.success(defaultDialPackage(activity))
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether this app is the current default home app.
     *
     * Resolves the HOME intent with MATCH_DEFAULT_ONLY and compares the
     * package name. When the user has made no choice the system resolves to
     * its own resolver activity instead, so that case reads as false - which
     * is exactly the case worth asking about. A null resolution (no home app
     * resolvable at all) also reads as false rather than throwing.
     */
    private fun isDefaultHome(activity: Activity): Boolean {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = activity.packageManager.resolveActivity(
            home,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        return resolved?.activityInfo?.packageName == activity.packageName
    }

    /**
     * Ask the user to make this app the default home app, returning whether
     * any system UI was actually started.
     *
     * Android 10 (API 29) and up: the home role request RoleManager builds,
     * which is a single dialog with the user's own yes and no. isRoleAvailable
     * is checked first - a device that does not offer the role would throw on
     * createRequestRoleIntent - and the role already being HELD is treated as
     * nothing to ask, which also makes this safe if it is ever reached without
     * the isDefaultHome check in front of it.
     *
     * Below API 29 there is no role to request: the home settings screen
     * (ACTION_HOME_SETTINGS) is the only ask those releases offer, so that is
     * what opens.
     */
    private fun requestDefaultHome(activity: Activity): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roles = activity.getSystemService(RoleManager::class.java)
                    ?: return false
                if (!roles.isRoleAvailable(RoleManager.ROLE_HOME)) return false
                if (roles.isRoleHeld(RoleManager.ROLE_HOME)) return false
                activity.startActivityForResult(
                    roles.createRequestRoleIntent(RoleManager.ROLE_HOME),
                    REQUEST_CODE,
                )
            } else {
                activity.startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
            }
            true
        } catch (e: Exception) {
            // A device with no home settings screen and no home role is a
            // device that cannot be asked. Nothing was shown; say so.
            false
        }
    }

    /**
     * The package name of the app this device dials with, or null.
     *
     * ASKED, NEVER GUESSED (Ray, 2026-09-19: "two, ask android as giving you
     * package will mean hardcoding and this will be installed n many
     * phones"). A list of well-known dialer package names would be wrong on
     * the first phone whose skin ships its own, so the question goes where
     * the answer actually lives: resolving ACTION_DIAL with
     * MATCH_DEFAULT_ONLY is the same call, on the same PackageManager, that
     * isDefaultHome above makes for the HOME intent.
     *
     * Null rather than a package for every case that is not an app the user
     * dials with: nothing resolvable at all, the system's own resolver
     * activity standing in because no choice has been made ("android"), and
     * this launcher itself. The Dart side reads null as "no phone entry on
     * the nav" and shows none, which is the honest answer on a device with
     * no telephony.
     */
    private fun defaultDialPackage(activity: Activity): String? {
        return try {
            val dial = Intent(Intent.ACTION_DIAL)
            val resolved = activity.packageManager.resolveActivity(
                dial,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            val packageName = resolved?.activityInfo?.packageName
            when (packageName) {
                null, "", "android", activity.packageName -> null
                else -> packageName
            }
        } catch (e: Exception) {
            // A device with no dialler is a device with no answer. Say so
            // rather than throwing across the channel.
            null
        }
    }
}
