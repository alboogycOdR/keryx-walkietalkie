package za.co.basileia.keryx

import android.app.Activity
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart `MethodChannelScreenBrightness` native half.
 *
 * Channel: `za.co.basileia.keryx/screen_brightness`
 * Methods: `setMaximum` / `restore`.
 *
 * `restore` reapplies the window brightness captured at the first
 * `setMaximum`, including [WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE]
 * (system default). It never substitutes a hardcoded level.
 */
class ScreenBrightnessPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        const val METHOD_CHANNEL = "za.co.basileia.keryx/screen_brightness"
        const val METHOD_SET_MAXIMUM = "setMaximum"
        const val METHOD_RESTORE = "restore"
        private const val TAG = "KeryxBrightness"
    }

    private var methods: MethodChannel? = null
    private var activity: Activity? = null

    /** Prior [android.view.WindowManager.LayoutParams.screenBrightness], or null if none saved. */
    private var savedBrightness: Float? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        methods = null
        savedBrightness = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_SET_MAXIMUM -> mutateWindow(result) { act ->
                val lp = act.window.attributes
                if (savedBrightness == null) {
                    savedBrightness = lp.screenBrightness
                }
                lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
                act.window.attributes = lp
                val now = act.window.attributes.screenBrightness
                Log.i(TAG, "setMaximum saved=$savedBrightness now=$now")
            }
            METHOD_RESTORE -> mutateWindow(result) { act ->
                val previous = savedBrightness
                if (previous != null) {
                    val lp = act.window.attributes
                    lp.screenBrightness = previous
                    act.window.attributes = lp
                    savedBrightness = null
                    val now = act.window.attributes.screenBrightness
                    Log.i(TAG, "restore requested=$previous now=$now")
                } else {
                    Log.i(TAG, "restore with no saved brightness (no-op)")
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun mutateWindow(
        result: MethodChannel.Result,
        body: (Activity) -> Unit,
    ) {
        val act = activity
        if (act == null) {
            result.error("no_activity", "screen brightness has no activity", null)
            return
        }
        act.runOnUiThread {
            try {
                body(act)
                result.success(null)
            } catch (e: Exception) {
                result.error("brightness", e.message, null)
            }
        }
    }
}
