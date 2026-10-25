package com.example.minimal_launcher

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Hosts another app's home-screen widget on the launcher home - the Bible
 * app's verse-of-the-day widget. When the Bible app is installed the home
 * shows this widget and nothing else; the launcher draws no verse of its own.
 *
 * Android lets a launcher host any widget through its AppWidgetHost. The
 * widget is discovered by PACKAGE (its installed providers), never by a
 * class name written here. The bind is tried silently first
 * (bindAppWidgetIdIfAllowed); only when Android refuses does it open the
 * system's own bind screen, once. After that the launcher keeps the widget
 * id and shows it on every start.
 *
 * Channel [CHANNEL]:
 *  - status({package}) -> {state: "bound" | "needs_consent" | "unavailable",
 *    appWidgetId?, height?}
 *  - requestConsent({package}) -> bool: binds silently when Android allows
 *    it, otherwise opens the system bind screen. The launcher re-reads
 *    status when it resumes, so no activity result has to come back here.
 *
 * View type [VIEW_TYPE]: a PlatformView that renders the bound widget. The
 * creation params carry {appWidgetId}.
 */
object LauncherVerseWidgetBridge {
    const val CHANNEL = "rokct.launch_sdk/verse_widget"
    const val VIEW_TYPE = "rokct.launch_sdk/verse_widget_view"

    private const val TAG = "LauncherVerseWidget"

    /** The host id this launcher uses for its AppWidgetHost. */
    private const val HOST_ID = 0x524F4B54
    private const val PREFS = "launch_sdk_verse_widget"

    private var host: AppWidgetHost? = null

    fun register(engine: FlutterEngine, activity: Activity) {
        val widgetHost = AppWidgetHost(activity.applicationContext, HOST_ID)
        widgetHost.startListening()
        host = widgetHost
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(status(activity, call.argument<String>("package")))
                    "requestConsent" -> result.success(
                        requestConsent(activity, call.argument<String>("package")),
                    )
                    else -> result.notImplemented()
                }
            }
        engine.platformViewsController.registry
            .registerViewFactory(VIEW_TYPE, WidgetViewFactory(widgetHost))
    }

    /** The first provider the package installs, or null when it has none. */
    private fun providerOf(activity: Activity, pkg: String?): android.appwidget.AppWidgetProviderInfo? {
        if (pkg.isNullOrEmpty()) return null
        return AppWidgetManager.getInstance(activity)
            .getInstalledProvidersForPackage(pkg, null)
            .firstOrNull { it.provider != null }
    }

    private fun savedKey(pkg: String) = "widget_id_$pkg"

    private fun status(activity: Activity, pkg: String?): Map<String, Any?> {
        val provider = providerOf(activity, pkg)
        if (provider == null) {
            // The only way the home shows nothing for an installed Bible app.
            Log.w(TAG, "no widget provider found for package '$pkg'")
            return mapOf("state" to "unavailable")
        }
        val manager = AppWidgetManager.getInstance(activity)
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val saved = prefs.getInt(savedKey(pkg!!), -1)
        if (saved != -1 && manager.getAppWidgetInfo(saved) != null) {
            return mapOf(
                "state" to "bound",
                "appWidgetId" to saved,
                "height" to provider.minHeight,
            )
        }
        return mapOf("state" to "needs_consent")
    }

    private fun requestConsent(activity: Activity, pkg: String?): Boolean {
        val provider = providerOf(activity, pkg) ?: return false
        val widgetHost = host ?: return false
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // An earlier, never-accepted allocation is released before a new one.
        val previous = prefs.getInt(savedKey(pkg!!), -1)
        if (previous != -1) widgetHost.deleteAppWidgetId(previous)
        val id = widgetHost.allocateAppWidgetId()
        prefs.edit().putInt(savedKey(pkg), id).apply()
        // Silent bind first: succeeds with no screen when Android allows this
        // launcher to bind (e.g. it is the home app with the permission).
        if (AppWidgetManager.getInstance(activity).bindAppWidgetIdIfAllowed(id, provider.provider)) {
            return true
        }
        val bind = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, provider.provider)
        return try {
            activity.startActivity(bind)
            true
        } catch (e: Exception) {
            Log.w(TAG, "could not open the bind screen for '$pkg': $e")
            widgetHost.deleteAppWidgetId(id)
            prefs.edit().remove(savedKey(pkg)).apply()
            false
        }
    }

    private class WidgetViewFactory(private val host: AppWidgetHost) :
        PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val id = (args as? Map<*, *>)?.get("appWidgetId") as? Int ?: -1
            return WidgetPlatformView(context, host, id)
        }
    }

    private class WidgetPlatformView(
        private val context: Context,
        host: AppWidgetHost,
        appWidgetId: Int,
    ) : PlatformView {
        private val view: View = run {
            val info = if (appWidgetId == -1) null
            else AppWidgetManager.getInstance(context).getAppWidgetInfo(appWidgetId)
            if (info == null) View(context)
            else host.createView(context, appWidgetId, info) as AppWidgetHostView
        }

        override fun getView(): View = view

        override fun dispose() {}
    }
}
