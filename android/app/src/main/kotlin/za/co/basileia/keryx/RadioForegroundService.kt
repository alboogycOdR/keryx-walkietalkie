package za.co.basileia.keryx

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Radio foreground service (FR-103 / TS §8.8 / KRX-080).
 *
 * Types `mediaPlayback|microphone`. Partial wake lock during RX/TX only.
 * Audio focus: transient-may-duck on RX; abandon on idle and on power-off.
 * No polling loops.
 */
class RadioForegroundService : Service() {
    companion object {
        private const val TAG = "keryx.radio_service"
        private const val NOTIFICATION_ID = 80
        private const val CHANNEL_ID = "keryx.radio"
        private const val WAKE_TAG = "keryx:radio"

        const val ACTION_START = "za.co.basileia.keryx.radio.START"
        const val ACTION_STOP = "za.co.basileia.keryx.radio.STOP"
        const val ACTION_PTT = "za.co.basileia.keryx.radio.PTT"
        const val ACTION_SET_PHASE = "za.co.basileia.keryx.radio.SET_PHASE"
        const val ACTION_UPDATE = "za.co.basileia.keryx.radio.UPDATE"
        const val EXTRA_FROM_NOTIFICATION = "fromNotification"

        fun pttActionPermitted(): Boolean = Build.VERSION.SDK_INT >= 34

        fun isRunning(): Boolean = RadioServiceBridge.running

        @Volatile
        private var instance: RadioForegroundService? = null

        fun onEngineDetached() {
            instance?.applyPhase(RadioServiceContract.PHASE_IDLE)
        }

        fun start(context: Context, channelLabel: String, subtitle: String?) {
            val intent = Intent(context, RadioForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(RadioServiceContract.ARG_CHANNEL, channelLabel)
                putExtra(RadioServiceContract.ARG_SUBTITLE, subtitle)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context, fromNotification: Boolean = false) {
            val intent = Intent(context, RadioForegroundService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_FROM_NOTIFICATION, fromNotification)
            }
            context.startService(intent)
        }

        fun setPhase(context: Context, phase: String) {
            val intent = Intent(context, RadioForegroundService::class.java).apply {
                action = ACTION_SET_PHASE
                putExtra(RadioServiceContract.ARG_PHASE, phase)
            }
            context.startService(intent)
        }

        fun updateNotification(context: Context, channelLabel: String, subtitle: String?) {
            val intent = Intent(context, RadioForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(RadioServiceContract.ARG_CHANNEL, channelLabel)
                putExtra(RadioServiceContract.ARG_SUBTITLE, subtitle)
            }
            context.startService(intent)
        }
    }

    private lateinit var store: RadioServiceStore
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false
    private var userRequestedStop = false
    private var phase: String = RadioServiceContract.PHASE_IDLE
    private var channelLabel: String = "CH --"
    private var subtitle: String? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        store = RadioServiceStore(this)
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_TAG).apply {
            setReferenceCounted(false)
        }
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        ensureNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            // START_STICKY restart after an OEM kill.
            channelLabel = store.channelLabel.ifEmpty { channelLabel }
            subtitle = store.subtitle
            store.killedDirty = true
            emitKilled()
            renderNotification()
            RadioServiceBridge.notifyStartResult(true)
            return START_STICKY
        }

        when (intent.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop(fromNotification = intent.getBooleanExtra(EXTRA_FROM_NOTIFICATION, false))
            ACTION_PTT -> RadioServiceBridge.emit(
                mapOf(RadioServiceContract.EVENT_TYPE to RadioServiceContract.EVENT_PTT),
            )
            ACTION_SET_PHASE -> {
                val next = intent.getStringExtra(RadioServiceContract.ARG_PHASE)
                    ?: RadioServiceContract.PHASE_IDLE
                applyPhase(next)
            }
            ACTION_UPDATE -> {
                readLabel(intent)
                store.channelLabel = channelLabel
                store.subtitle = subtitle
                renderNotification()
            }
            else -> {
                if (store.poweredOn) {
                    renderNotification()
                }
            }
        }
        return if (userRequestedStop) START_NOT_STICKY else START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Radio stays on. Power-off is an explicit action, not recents-swipe.
    }

    override fun onDestroy() {
        teardownLocks()
        RadioServiceBridge.notifyStopped()
        if (!userRequestedStop && store.poweredOn) {
            store.killedDirty = true
            emitKilled()
        }
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun handleStart(intent: Intent) {
        userRequestedStop = false
        readLabel(intent)
        store.markPoweredOn(channelLabel, subtitle)
        if (store.killedDirty) {
            emitKilled()
            store.killedDirty = false
        }
        try {
            renderNotification()
            RadioServiceBridge.notifyStartResult(true)
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed", e)
            RadioServiceBridge.notifyStartResult(false, e.message)
            stopSelf()
        }
    }

    private fun handleStop(fromNotification: Boolean) {
        userRequestedStop = true
        store.markUserPowerOff()
        if (fromNotification) {
            RadioServiceBridge.emit(
                mapOf(RadioServiceContract.EVENT_TYPE to RadioServiceContract.EVENT_POWER_OFF),
            )
        }
        teardownLocks()
        stopForeground(STOP_FOREGROUND_REMOVE)
        RadioServiceBridge.notifyStopped()
        stopSelf()
    }

    private fun readLabel(intent: Intent) {
        val label = intent.getStringExtra(RadioServiceContract.ARG_CHANNEL)?.trim().orEmpty()
        if (label.isNotEmpty()) channelLabel = label
        if (intent.hasExtra(RadioServiceContract.ARG_SUBTITLE)) {
            subtitle = intent.getStringExtra(RadioServiceContract.ARG_SUBTITLE)
        }
    }

    private fun applyPhase(next: String) {
        phase = when (next) {
            RadioServiceContract.PHASE_RX, RadioServiceContract.PHASE_TX,
            RadioServiceContract.PHASE_IDLE,
            -> next
            else -> RadioServiceContract.PHASE_IDLE
        }
        when (phase) {
            RadioServiceContract.PHASE_RX, RadioServiceContract.PHASE_TX -> acquireWakeLock()
            else -> releaseWakeLock()
        }
        when (phase) {
            RadioServiceContract.PHASE_RX -> requestRxFocus()
            RadioServiceContract.PHASE_IDLE -> abandonFocus()
            RadioServiceContract.PHASE_TX -> Unit
        }
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        val lock = wakeLock ?: return
        if (!lock.isHeld) {
            lock.acquire()
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        if (lock.isHeld) {
            runCatching { lock.release() }
        }
    }

    private fun requestRxFocus() {
        if (focusHeld) return
        val am = audioManager ?: return
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { }
            .build()
        val granted = am.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (granted) {
            focusRequest = req
            focusHeld = true
        }
    }

    private fun abandonFocus() {
        val req = focusRequest
        focusRequest = null
        focusHeld = false
        if (req != null) {
            runCatching { audioManager?.abandonAudioFocusRequest(req) }
        }
    }

    private fun teardownLocks() {
        phase = RadioServiceContract.PHASE_IDLE
        releaseWakeLock()
        abandonFocus()
    }

    private fun emitKilled() {
        RadioServiceBridge.emit(
            mapOf(RadioServiceContract.EVENT_TYPE to RadioServiceContract.EVENT_KILLED),
        )
    }

    private fun ensureNotificationChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.keryx_radio_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.keryx_radio_channel_desc)
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun renderNotification() {
        promoteForeground(buildNotification())
    }

    private fun buildNotification(): Notification {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            piFlags,
        )
        val powerOff = PendingIntent.getService(
            this,
            1,
            Intent(this, RadioForegroundService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_FROM_NOTIFICATION, true)
            },
            piFlags,
        )
        val text = subtitle?.takeIf { it.isNotBlank() }
            ?: getString(R.string.keryx_radio_monitor)
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_radio)
            .setContentTitle(channelLabel)
            .setContentText(text)
            .setContentIntent(launch)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setColor(getColor(R.color.keryx_olive))
            .setColorized(true)
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_stat_power),
                    getString(R.string.keryx_action_power_off),
                    powerOff,
                ).build(),
            )
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        if (pttActionPermitted()) {
            val ptt = PendingIntent.getService(
                this,
                2,
                Intent(this, RadioForegroundService::class.java).apply {
                    action = ACTION_PTT
                },
                piFlags,
            )
            builder.addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_stat_ptt),
                    getString(R.string.keryx_action_ptt),
                    ptt,
                ).build(),
            )
        }
        return builder.build()
    }

    private fun promoteForeground(notification: Notification) {
        try {
            startWithTypes(notification, withMicrophone = hasRecordAudio())
        } catch (e: SecurityException) {
            Log.w(TAG, "microphone FGS type refused, falling back to mediaPlayback", e)
            startWithTypes(notification, withMicrophone = false)
        }
    }

    private fun startWithTypes(notification: Notification, withMicrophone: Boolean) {
        if (Build.VERSION.SDK_INT >= 29) {
            var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            if (withMicrophone && Build.VERSION.SDK_INT >= 30) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(NOTIFICATION_ID, notification, types)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun hasRecordAudio(): Boolean {
        return checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }
}
