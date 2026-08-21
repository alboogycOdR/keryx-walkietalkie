package za.co.basileia.keryx

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Process-local glue between [RadioForegroundService] and [RadioServicePlugin].
 * Event-driven; no loops.
 */
internal object RadioServiceBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var sink: EventChannel.EventSink? = null

    @Volatile
    var running: Boolean = false

    @Volatile
    var startListener: ((Boolean, String?) -> Unit)? = null

    fun emit(payload: Map<String, Any?>) {
        main.post { sink?.success(payload) }
    }

    fun notifyStartResult(ok: Boolean, error: String? = null) {
        running = ok
        main.post {
            val listener = startListener
            startListener = null
            listener?.invoke(ok, error)
        }
    }

    fun notifyStopped() {
        running = false
    }
}
