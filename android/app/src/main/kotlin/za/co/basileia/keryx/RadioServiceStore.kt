package za.co.basileia.keryx

import android.content.Context

/** Persisted powered-on / OEM-kill flags. Not a polling source. */
internal class RadioServiceStore(context: Context) {
    private val prefs =
        context.applicationContext.getSharedPreferences(
            RadioServiceContract.PREFS,
            Context.MODE_PRIVATE,
        )

    var poweredOn: Boolean
        get() = prefs.getBoolean(RadioServiceContract.KEY_POWERED, false)
        set(value) {
            prefs.edit().putBoolean(RadioServiceContract.KEY_POWERED, value).apply()
        }

    var killedDirty: Boolean
        get() = prefs.getBoolean(RadioServiceContract.KEY_KILLED, false)
        set(value) {
            prefs.edit().putBoolean(RadioServiceContract.KEY_KILLED, value).apply()
        }

    var channelLabel: String
        get() = prefs.getString(RadioServiceContract.KEY_CHANNEL, "") ?: ""
        set(value) {
            prefs.edit().putString(RadioServiceContract.KEY_CHANNEL, value).apply()
        }

    var subtitle: String?
        get() = prefs.getString(RadioServiceContract.KEY_SUBTITLE, null)
        set(value) {
            prefs.edit().putString(RadioServiceContract.KEY_SUBTITLE, value).apply()
        }

    fun markUserPowerOff() {
        prefs.edit()
            .putBoolean(RadioServiceContract.KEY_POWERED, false)
            .putBoolean(RadioServiceContract.KEY_KILLED, false)
            .apply()
    }

    fun markPoweredOn(channelLabel: String, subtitle: String?) {
        prefs.edit()
            .putBoolean(RadioServiceContract.KEY_POWERED, true)
            .putString(RadioServiceContract.KEY_CHANNEL, channelLabel)
            .putString(RadioServiceContract.KEY_SUBTITLE, subtitle)
            .apply()
    }
}
