package za.co.basileia.keryx

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart ↔ [RadioForegroundService] platform channel.
 *
 * The only delayed callback is a 5 s start watchdog so a failed
 * `startForeground` cannot hang the MethodChannel result. The service
 * itself has no timers.
 */
class RadioServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val START_TIMEOUT_MS = 5000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var appContext: Context? = null
    private var startTimeout: Runnable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, RadioServiceContract.METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, RadioServiceContract.EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cancelStartTimeout()
        RadioForegroundService.onEngineDetached()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        RadioServiceBridge.sink = null
        RadioServiceBridge.startListener = null
        appContext = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        RadioServiceBridge.sink = events
        val ctx = appContext ?: return
        val store = RadioServiceStore(ctx)
        if (store.killedDirty) {
            RadioServiceBridge.emit(
                mapOf(RadioServiceContract.EVENT_TYPE to RadioServiceContract.EVENT_KILLED),
            )
            store.killedDirty = false
        }
    }

    override fun onCancel(arguments: Any?) {
        RadioServiceBridge.sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("detached", "plugin not attached", null)
            return
        }
        when (call.method) {
            RadioServiceContract.METHOD_START -> start(ctx, call, result)
            RadioServiceContract.METHOD_STOP -> {
                RadioForegroundService.stop(ctx, fromNotification = false)
                result.success(null)
            }
            RadioServiceContract.METHOD_SET_PHASE -> {
                val phase = call.argument<String>(RadioServiceContract.ARG_PHASE)?.trim().orEmpty()
                if (phase != RadioServiceContract.PHASE_IDLE &&
                    phase != RadioServiceContract.PHASE_RX &&
                    phase != RadioServiceContract.PHASE_TX
                ) {
                    result.error("bad_args", "phase must be idle|rx|tx", null)
                    return
                }
                if (!RadioForegroundService.isRunning()) {
                    result.error("not_running", "start required", null)
                    return
                }
                RadioForegroundService.setPhase(ctx, phase)
                result.success(null)
            }
            RadioServiceContract.METHOD_UPDATE -> {
                val label = call.argument<String>(RadioServiceContract.ARG_CHANNEL)?.trim().orEmpty()
                if (label.isEmpty()) {
                    result.error("bad_args", "channelLabel required", null)
                    return
                }
                if (!RadioForegroundService.isRunning()) {
                    result.error("not_running", "start required", null)
                    return
                }
                val subtitle = call.argument<String>(RadioServiceContract.ARG_SUBTITLE)
                RadioForegroundService.updateNotification(ctx, label, subtitle)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val label = call.argument<String>(RadioServiceContract.ARG_CHANNEL)?.trim().orEmpty()
        if (label.isEmpty()) {
            result.error("bad_args", "channelLabel required", null)
            return
        }
        val subtitle = call.argument<String>(RadioServiceContract.ARG_SUBTITLE)

        if (RadioForegroundService.isRunning()) {
            RadioForegroundService.updateNotification(ctx, label, subtitle)
            result.success(
                mapOf(RadioServiceContract.RESULT_PTT_ENABLED to RadioForegroundService.pttActionPermitted()),
            )
            return
        }

        var replied = false
        fun replyOnce(ok: Boolean, error: String?) {
            if (replied) return
            replied = true
            cancelStartTimeout()
            if (ok) {
                result.success(
                    mapOf(RadioServiceContract.RESULT_PTT_ENABLED to RadioForegroundService.pttActionPermitted()),
                )
            } else {
                result.error("radio_start", error ?: "service failed to foreground", null)
            }
        }

        val timeout = Runnable { replyOnce(false, "service start timed out") }
        startTimeout = timeout
        RadioServiceBridge.startListener = { ok, error -> replyOnce(ok, error) }
        mainHandler.postDelayed(timeout, START_TIMEOUT_MS)
        try {
            RadioForegroundService.start(ctx, label, subtitle)
        } catch (e: Exception) {
            replyOnce(false, e.message)
        }
    }

    private fun cancelStartTimeout() {
        startTimeout?.let { mainHandler.removeCallbacks(it) }
        startTimeout = null
    }
}
