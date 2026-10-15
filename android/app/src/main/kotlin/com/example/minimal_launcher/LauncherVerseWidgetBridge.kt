package com.example.minimal_launcher

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Hosts another app's home-screen widget on the launcher home - the Bible
 * app's verse-of-the-day widget, in the place the launcher's verse card
 * draws its own verse when the widget is not available.
 *
 * Android lets a launcher host any widget the user places through its
 * AppWidgetHost. The widget is discovered by PACKAGE (its installed
 * providers), never by a class name written here. The user approves the
 * binding once through the system's bind screen; after that the launcher
 * keeps the widget id and shows it on every start.
 *
 * Channel [CHANNEL]:
 *  - status({package}) -> {state: "bound" | "needs_consent" | "unavailable",
 *    appWidgetId?, height?}
 *  - requestConsent({package}) -> bool: opens the system bind screen. The
 *    widget is bound when the user accepts; the launcher re-reads status
 *    when it resumes, so no activity result has to come back here.
 *
 * View type [VIEW_TYPE]: a PlatformView that renders the bound widget. The
 * creation params carry {appWidgetId}.
 */
object LauncherVerseWidgetBridge {
    const val CHANNEL = "rokct.launch_sdk/verse_widget"
    const val VIEW_TYPE = "rokct.launch_sdk/verse_widget_view"

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
        val provider = providerOf(activity, pkg) ?: return mapOf("state" to "unavailable")
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
        val bind = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, provider.provider)
        return try {
            activity.startActivity(bind)
            true
        } catch (e: Exception) {
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
