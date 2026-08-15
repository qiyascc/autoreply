package cc.ubermensch.ctm

import android.content.Context

/** Typed access to the settings table, plus the vocabulary the UI and engine share. */
object Settings {
    const val MASTER_ENABLED = "master_enabled"
    const val DEFAULT_DELAY_SECONDS = "default_delay_seconds"
    const val COUNTER_RESET_MODE = "counter_reset_mode"
    const val QUIET_ENABLED = "quiet_enabled"
    const val QUIET_START = "quiet_start"
    const val QUIET_END = "quiet_end"
    const val DAILY_SUMMARY_ENABLED = "daily_summary_enabled"
    const val DAILY_SUMMARY_MINUTE = "daily_summary_minute"
    const val THEME = "theme"
    const val WHATSAPP_MODE = "whatsapp_mode"
    const val BRIDGE_URL = "bridge_url"
    const val BRIDGE_TOKEN = "bridge_token"
    const val BRIDGE_DEVICE_ID = "bridge_device_id"
    const val BRIDGE_SESSION_ID = "bridge_session_id"
    const val DEFAULT_COUNTRY_CODE = "default_country_code"
    const val DEDUPE_MINUTES = "dedupe_minutes"
    const val LIST_MODE = "list_mode"
    const val SIM_SUBSCRIPTION_ID = "sim_subscription_id"
    const val SETUP_COMPLETE = "setup_complete"

    /** Counter reset modes — how far back "how many times has this person called" looks. */
    const val RESET_ON_ANSWERED = "answered"
    const val RESET_6H = "6h"
    const val RESET_12H = "12h"
    const val RESET_24H = "24h"
    const val RESET_7D = "7d"
    const val RESET_NEVER = "never"

    const val THEME_SYSTEM = "system"
    const val THEME_LIGHT = "light"
    const val THEME_DARK = "dark"

    const val WA_MODE_BRIDGE = "bridge"
    const val WA_MODE_DEVICE = "device"

    const val LIST_OFF = "off"
    const val LIST_BLOCK = "blocklist"
    const val LIST_ALLOW = "allowlist"

    fun bool(context: Context, key: String, fallback: Boolean = false): Boolean =
        Db.get(context).getSetting(key, if (fallback) "1" else "0") == "1"

    fun int(context: Context, key: String, fallback: Int): Int =
        Db.get(context).getSetting(key, fallback.toString()).toIntOrNull() ?: fallback

    fun str(context: Context, key: String, fallback: String): String =
        Db.get(context).getSetting(key, fallback)

    fun countryCode(context: Context): String = str(context, DEFAULT_COUNTRY_CODE, "90")

    /**
     * The window over which repeat calls are counted, in milliseconds, or null when the
     * mode is not a fixed window (answered / never).
     */
    fun counterWindowMs(mode: String): Long? = when (mode) {
        RESET_6H -> 6 * 60 * 60 * 1000L
        RESET_12H -> 12 * 60 * 60 * 1000L
        RESET_24H -> 24 * 60 * 60 * 1000L
        RESET_7D -> 7 * 24 * 60 * 60 * 1000L
        else -> null
    }

    /** True when `minuteOfDay` falls inside the configured quiet window (which may wrap midnight). */
    fun inQuietHours(context: Context, minuteOfDay: Int): Boolean {
        if (!bool(context, QUIET_ENABLED)) return false
        val start = int(context, QUIET_START, 1380)
        val end = int(context, QUIET_END, 480)
        return if (start <= end) {
            minuteOfDay in start until end
        } else {
            minuteOfDay >= start || minuteOfDay < end
        }
    }
}
