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
 * Dart `MethodChannelScreenshotGuard` native half.
 *
 * Channel: `za.co.basileia.keryx/screenshot_guard`
 * Method: `setSecure` with `{secure: bool}` → [WindowManager.LayoutParams.FLAG_SECURE].
 */
class ScreenshotGuardPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        const val METHOD_CHANNEL = "za.co.basileia.keryx/screenshot_guard"
        const val METHOD_SET_SECURE = "setSecure"
        const val ARG_SECURE = "secure"
        private const val TAG = "KeryxScreenshotGuard"
    }

    private var methods: MethodChannel? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        methods = null
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
            METHOD_SET_SECURE -> setSecure(call, result)
            else -> result.notImplemented()
        }
    }

    private fun setSecure(call: MethodCall, result: MethodChannel.Result) {
        val secure = call.argument<Boolean>(ARG_SECURE)
        if (secure == null) {
            result.error("bad_args", "setSecure requires boolean '$ARG_SECURE'", null)
            return
        }
        val act = activity
        if (act == null) {
            result.error("no_activity", "screenshot guard has no activity", null)
            return
        }
        act.runOnUiThread {
            try {
                if (secure) {
                    act.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    act.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                val flags = act.window.attributes.flags
                val applied = flags and WindowManager.LayoutParams.FLAG_SECURE != 0
                Log.i(TAG, "setSecure=$secure applied=$applied flags=0x${Integer.toHexString(flags)}")
                result.success(null)
            } catch (e: Exception) {
                result.error("set_secure", e.message, null)
            }
        }
    }
}
