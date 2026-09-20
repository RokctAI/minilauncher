package com.example.minimal_launcher

import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telecom.TelecomManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Platform plumbing for the launcher's questions the framework cannot
 * answer: is this app the device's home screen, if not ask the user to make
 * it one, and which app actually handles dialling a number.
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
     * the first phone whose skin ships its own, so every branch below is a
     * QUESTION put to the platform and not one of them names a dialler.
     *
     * TWO SOURCES, IN THIS ORDER. The first is where the answer actually
     * lives; the second is the resolve this bridge used to ask ALONE, which
     * is why it could not find a default (Ray: "cant auto find default"):
     *
     *  1. TelecomManager.getDefaultDialerPackage() - the DEFAULT-APP answer.
     *     The dialler is a ROLE the user grants under Default apps
     *     (RoleManager.ROLE_DIALER on API 29+, the same registry below it),
     *     and granting a role does NOT set an intent default. So the role
     *     holder has to be read from the role registry, which is what this
     *     call does: no permission, and no API 30 package-visibility
     *     filtering to fall foul of, because it answers with a package name
     *     rather than with a ResolveInfo.
     *  2. Resolving ACTION_DIAL, for a device that answers nothing at (1) -
     *     no telecom service at all, which is a device with no telephony.
     *     MATCH_DEFAULT_ONLY answers with the system's own RESOLVER activity
     *     ("android") whenever several activities match and no intent
     *     default has been set, and on a phone whose dialler was chosen as a
     *     role that is the ordinary case - so the resolve alone reported "no
     *     phone app" on a phone that plainly has one. A resolver answer now
     *     falls through to queryIntentActivities, and is taken ONLY when
     *     every match agrees on one package: several candidates with no
     *     default is a question this bridge cannot answer, and it says null
     *     rather than pick one.
     *
     * The intent carries the bare "tel:" scheme and no number - a scheme,
     * not a phone number, and not a package name. A dialler declares its
     * ACTION_DIAL filter with that data scheme, so the bare action on its
     * own matched fewer activities than the intent a launcher actually
     * fires.
     *
     * Null rather than a package for every case that is not an app the user
     * dials with. The Dart side reads null as "no phone entry on the nav"
     * beyond whatever the user has already chosen, which is the honest
     * answer on a device with no telephony.
     */
    private fun defaultDialPackage(activity: Activity): String? {
        return roleDialPackage(activity) ?: resolvedDialPackage(activity)
    }

    /**
     * Source 1 - the default-app registry, read through telecom.
     */
    private fun roleDialPackage(activity: Activity): String? {
        return try {
            val telecom = activity.getSystemService(TelecomManager::class.java)
            dialPackageOrNull(activity, telecom?.defaultDialerPackage)
        } catch (e: Exception) {
            // A device with no telecom service is a device with no answer
            // here. Say so rather than throwing across the channel.
            null
        }
    }

    /**
     * Source 2 - the ACTION_DIAL resolve, for a device the role registry
     * cannot answer for.
     */
    private fun resolvedDialPackage(activity: Activity): String? {
        return try {
            val dial = Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", "", null))
            val packageManager = activity.packageManager
            // An intent default the user HAS set resolves straight to it.
            val resolved = dialPackageOrNull(
                activity,
                packageManager.resolveActivity(
                    dial,
                    PackageManager.MATCH_DEFAULT_ONLY,
                )?.activityInfo?.packageName,
            )
            resolved ?: packageManager
                .queryIntentActivities(dial, PackageManager.MATCH_DEFAULT_ONLY)
                .mapNotNull { dialPackageOrNull(activity, it.activityInfo?.packageName) }
                .toSet()
                .singleOrNull()
        } catch (e: Exception) {
            // A device with no dialler is a device with no answer. Say so
            // rather than throwing across the channel.
            null
        }
    }

    /**
     * [packageName] when it names an app this device dials with, else null.
     *
     * The three rejections are all cases that are not a dialler the user
     * chose: nothing at all, the system's own resolver activity standing in
     * because no choice has been made ("android" is the platform's own
     * package, not an app), and this launcher itself.
     */
    private fun dialPackageOrNull(activity: Activity, packageName: String?): String? {
        return when (packageName) {
            null, "", "android", activity.packageName -> null
            else -> packageName
        }
    }
}
