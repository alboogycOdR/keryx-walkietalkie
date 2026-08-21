package za.co.basileia.keryx

/**
 * Wire names shared by [RadioServicePlugin] and [RadioForegroundService].
 * Must stay byte-identical with Dart `RadioServiceConstants`.
 */
internal object RadioServiceContract {
    const val METHOD_CHANNEL = "za.co.basileia.keryx/radio_service"
    const val EVENT_CHANNEL = "za.co.basileia.keryx/radio_service_events"

    const val METHOD_START = "start"
    const val METHOD_STOP = "stop"
    const val METHOD_SET_PHASE = "setPhase"
    const val METHOD_UPDATE = "updateNotification"

    const val ARG_CHANNEL = "channelLabel"
    const val ARG_SUBTITLE = "subtitle"
    const val ARG_PHASE = "phase"

    const val PHASE_IDLE = "idle"
    const val PHASE_RX = "rx"
    const val PHASE_TX = "tx"

    const val EVENT_TYPE = "type"
    const val EVENT_KILLED = "serviceKilled"
    const val EVENT_PTT = "pttAction"
    const val EVENT_POWER_OFF = "powerOffAction"

    const val RESULT_PTT_ENABLED = "pttActionEnabled"

    const val PREFS = "keryx.radio.service"
    const val KEY_POWERED = "powered_on"
    const val KEY_KILLED = "killed_dirty"
    const val KEY_CHANNEL = "channel_label"
    const val KEY_SUBTITLE = "subtitle"
}
