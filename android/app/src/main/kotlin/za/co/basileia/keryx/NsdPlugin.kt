package za.co.basileia.keryx

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android NSD (mDNS) + MulticastLock platform channel.
 *
 * Service type `_keryx._tcp.` TXT: cs, ch, v, p (signaling port).
 * MulticastLock is held only between start() and stop().
 */
class NsdPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "za.co.basileia.keryx/nsd"
        const val EVENT_CHANNEL = "za.co.basileia.keryx/nsd_events"
        const val SERVICE_TYPE = "_keryx._tcp."
        const val LOCK_TAG = "keryx-nsd"
        const val TXT_CS = "cs"
        const val TXT_CH = "ch"
        const val TXT_V = "v"
        const val TXT_P = "p"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var appContext: Context? = null

    private var nsdManager: NsdManager? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var registeredInfo: NsdServiceInfo? = null
    private var selfName: String? = null
    private var browsing = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopInternal()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        appContext = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    startInternal(call)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("nsd_start", e.message, null)
                }
            }
            "stop" -> {
                stopInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startInternal(call: MethodCall) {
        val ctx = appContext ?: throw IllegalStateException("plugin not attached")
        val peerId = call.argument<String>("peerId")?.trim().orEmpty()
        val callsign = call.argument<String>("callsign")?.trim().orEmpty()
        val ch = call.argument<String>("channelHashPrefix")?.trim().orEmpty()
        val version = call.argument<Int>("protocolVersion") ?: 1
        val port = call.argument<Int>("signalingPort") ?: 0
        if (peerId.isEmpty() || callsign.isEmpty() || ch.isEmpty()) {
            throw IllegalArgumentException("peerId, callsign, channelHashPrefix required")
        }
        if (port !in 1..65535) {
            throw IllegalArgumentException("signalingPort out of range")
        }
        if (ch.contains("|")) {
            throw IllegalArgumentException("channelHashPrefix must not contain raw tuples")
        }

        stopInternal()
        selfName = peerId
        nsdManager = ctx.getSystemService(Context.NSD_SERVICE) as NsdManager
        acquireLock(ctx)

        val info = NsdServiceInfo().apply {
            serviceName = peerId
            serviceType = SERVICE_TYPE
            setPort(port)
            setAttribute(TXT_CS, callsign)
            setAttribute(TXT_CH, ch)
            setAttribute(TXT_V, version.toString())
            setAttribute(TXT_P, port.toString())
        }

        val reg = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                registeredInfo = serviceInfo
                emit(
                    mapOf(
                        "type" to "registered",
                        "serviceName" to serviceInfo.serviceName,
                        "port" to port,
                    ),
                )
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                emit(mapOf("type" to "error", "message" to "registration failed: $errorCode"))
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                registeredInfo = null
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                emit(mapOf("type" to "error", "message" to "unregistration failed: $errorCode"))
            }
        }
        registrationListener = reg
        nsdManager?.registerService(info, NsdManager.PROTOCOL_DNS_SD, reg)
        startBrowse()
    }

    private fun startBrowse() {
        val mgr = nsdManager ?: return
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                browsing = true
                emit(mapOf("type" to "browseStarted"))
            }

            override fun onDiscoveryStopped(serviceType: String) {
                browsing = false
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                browsing = false
                emit(mapOf("type" to "error", "message" to "browse start failed: $errorCode"))
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                emit(mapOf("type" to "error", "message" to "browse stop failed: $errorCode"))
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceName == selfName) return
                if (!serviceInfo.serviceType.contains("keryx")) return
                resolve(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                emit(
                    mapOf(
                        "type" to "peerLost",
                        "serviceName" to serviceInfo.serviceName,
                    ),
                )
            }
        }
        discoveryListener = listener
        mgr.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    @Suppress("DEPRECATION")
    private fun resolve(serviceInfo: NsdServiceInfo) {
        val mgr = nsdManager ?: return
        mgr.resolveService(
            serviceInfo,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    emit(mapOf("type" to "error", "message" to "resolve failed: $errorCode"))
                }

                override fun onServiceResolved(resolved: NsdServiceInfo) {
                    if (resolved.serviceName == selfName) return
                    val attrs = resolved.attributes ?: emptyMap()
                    emit(
                        mapOf(
                            "type" to "peerFound",
                            "peerId" to resolved.serviceName,
                            "callsign" to txt(attrs, TXT_CS).orEmpty(),
                            "channelHashPrefix" to txt(attrs, TXT_CH).orEmpty(),
                            "version" to (txt(attrs, TXT_V)?.toIntOrNull() ?: 0),
                            "host" to (resolved.host?.hostAddress ?: ""),
                            "port" to resolved.port,
                        ),
                    )
                }
            },
        )
    }

    private fun stopInternal() {
        val mgr = nsdManager
        if (browsing) {
            discoveryListener?.let { runCatching { mgr?.stopServiceDiscovery(it) } }
        }
        browsing = false
        discoveryListener = null
        registrationListener?.let { listener ->
            runCatching { mgr?.unregisterService(listener) }
        }
        registrationListener = null
        registeredInfo = null
        selfName = null
        nsdManager = null
        releaseLock()
    }

    private fun acquireLock(ctx: Context) {
        val wifi = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock(LOCK_TAG)
        lock.setReferenceCounted(false)
        lock.acquire()
        multicastLock = lock
        emit(mapOf("type" to "lock", "held" to true))
    }

    private fun releaseLock() {
        val lock = multicastLock
        multicastLock = null
        if (lock != null && lock.isHeld) {
            runCatching { lock.release() }
        }
        emit(mapOf("type" to "lock", "held" to false))
    }

    private fun txt(attrs: Map<String, ByteArray>, key: String): String? {
        val bytes = attrs[key] ?: return null
        return String(bytes, Charsets.UTF_8)
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            sink?.success(payload)
        }
    }
}
