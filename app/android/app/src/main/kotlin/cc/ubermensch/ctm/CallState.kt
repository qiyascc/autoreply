package cc.ubermensch.ctm

import android.content.Context

/**
 * The ringing/answered flags have to outlive the process: Android delivers PHONE_STATE
 * as separate broadcasts and is free to tear us down in between, so an in-memory field
 * would silently lose the "was it answered?" answer on exactly the calls we care about.
 */
object CallState {
    private const val PREFS = "call_state"
    private const val KEY_LAST_STATE = "last_state"
    private const val KEY_NUMBER = "number"
    private const val KEY_RING_STARTED = "ring_started"
    private const val KEY_ANSWERED = "answered"
    private const val KEY_LAST_HANDLED = "last_handled_at"

    const val IDLE = "IDLE"
    const val RINGING = "RINGING"
    const val OFFHOOK = "OFFHOOK"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun lastState(context: Context): String = prefs(context).getString(KEY_LAST_STATE, IDLE) ?: IDLE

    fun onRinging(context: Context, number: String?) {
        prefs(context).edit()
            .putString(KEY_LAST_STATE, RINGING)
            .putString(KEY_NUMBER, number)
            .putLong(KEY_RING_STARTED, System.currentTimeMillis())
            .putBoolean(KEY_ANSWERED, false)
            .apply()
    }

    fun onOffHook(context: Context) {
        prefs(context).edit()
            .putString(KEY_LAST_STATE, OFFHOOK)
            .putBoolean(KEY_ANSWERED, true)
            .apply()
    }

    /**
     * Settles the call. Returns the missed-call details when the phone rang and was never
     * picked up, or null for answered calls, outgoing calls and duplicate broadcasts.
     */
    fun onIdle(context: Context): Missed? {
        val p = prefs(context)
        val previous = p.getString(KEY_LAST_STATE, IDLE) ?: IDLE
        val number = p.getString(KEY_NUMBER, null)
        val ringStarted = p.getLong(KEY_RING_STARTED, 0L)
        val answered = p.getBoolean(KEY_ANSWERED, false)

        p.edit()
            .putString(KEY_LAST_STATE, IDLE)
            .putString(KEY_NUMBER, null)
            .putBoolean(KEY_ANSWERED, false)
            .apply()

        if (previous != RINGING || answered) return null

        // The framework sometimes replays IDLE; ignore anything within a second of the last.
        val now = System.currentTimeMillis()
        val lastHandled = p.getLong(KEY_LAST_HANDLED, 0L)
        if (now - lastHandled < 1_000L) return null
        p.edit().putLong(KEY_LAST_HANDLED, now).apply()

        return Missed(number = number, ringStartedAt = ringStarted, endedAt = now)
    }

    fun rememberNumber(context: Context, number: String?) {
        if (number.isNullOrBlank()) return
        if (prefs(context).getString(KEY_NUMBER, null).isNullOrBlank()) {
            prefs(context).edit().putString(KEY_NUMBER, number).apply()
        }
    }

    data class Missed(val number: String?, val ringStartedAt: Long, val endedAt: Long) {
        /** How long the phone actually rang, useful for telling a reject from a real miss. */
        val ringDurationMs: Long get() = if (ringStartedAt > 0) endedAt - ringStartedAt else 0
    }
}
