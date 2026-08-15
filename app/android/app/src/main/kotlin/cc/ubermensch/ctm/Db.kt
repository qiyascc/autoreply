package cc.ubermensch.ctm

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

/**
 * The single store for rules, call history and the outbox.
 *
 * Native code owns this database outright. The alarm that sends a reply can fire when
 * no Flutter engine is alive, so the decision logic has to live here; the UI is a thin
 * client that reads and writes through [NativeApi] rather than opening its own handle.
 */
class Db private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, NAME, null, VERSION) {

    companion object {
        private const val NAME = "autoreply.db"
        private const val VERSION = 1

        @Volatile
        private var instance: Db? = null

        fun get(context: Context): Db =
            instance ?: synchronized(this) {
                instance ?: Db(context).also { instance = it }
            }

        const val STATE_SCHEDULED = "scheduled"
        const val STATE_CANCELLED = "cancelled"
        const val STATE_DISPATCHED = "dispatched"
        const val STATE_SKIPPED = "skipped"

        const val STATUS_PENDING = "pending"
        const val STATUS_SENT = "sent"
        const val STATUS_DELIVERED = "delivered"
        const val STATUS_FAILED = "failed"

        const val CHANNEL_SMS = "sms"
        const val CHANNEL_WHATSAPP = "whatsapp"
        const val CHANNEL_BOTH = "both"
    }

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE rules (
              id             INTEGER PRIMARY KEY AUTOINCREMENT,
              position       INTEGER NOT NULL,
              enabled        INTEGER NOT NULL DEFAULT 1,
              name           TEXT NOT NULL,
              attempt_min    INTEGER,
              attempt_max    INTEGER,
              time_start     INTEGER,
              time_end       INTEGER,
              contact_filter TEXT NOT NULL DEFAULT 'any',
              channel        TEXT NOT NULL,
              delay_seconds  INTEGER
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE rule_messages (
              id       INTEGER PRIMARY KEY AUTOINCREMENT,
              rule_id  INTEGER NOT NULL REFERENCES rules(id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              body     TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_rule_messages ON rule_messages(rule_id, position)")

        db.execSQL(
            """
            CREATE TABLE missed_calls (
              id             INTEGER PRIMARY KEY AUTOINCREMENT,
              number         TEXT,
              e164           TEXT,
              contact_name   TEXT,
              occurred_at    INTEGER NOT NULL,
              attempt_index  INTEGER,
              state          TEXT NOT NULL,
              cancel_reason  TEXT,
              rule_id        INTEGER,
              rule_name      TEXT,
              dispatched_at  INTEGER
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_missed_time ON missed_calls(occurred_at DESC)")
        db.execSQL("CREATE INDEX idx_missed_number ON missed_calls(e164, occurred_at DESC)")

        db.execSQL(
            """
            CREATE TABLE outbox (
              id             INTEGER PRIMARY KEY AUTOINCREMENT,
              missed_call_id INTEGER REFERENCES missed_calls(id) ON DELETE CASCADE,
              rule_id        INTEGER,
              message_index  INTEGER NOT NULL DEFAULT 0,
              channel        TEXT NOT NULL,
              to_e164        TEXT NOT NULL,
              body           TEXT NOT NULL,
              status         TEXT NOT NULL,
              error          TEXT,
              scheduled_at   INTEGER NOT NULL,
              sent_at        INTEGER,
              delivered_at   INTEGER
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_outbox_call ON outbox(missed_call_id)")
        db.execSQL("CREATE INDEX idx_outbox_time ON outbox(scheduled_at DESC)")

        db.execSQL("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)")

        db.execSQL(
            """
            CREATE TABLE number_list (
              id   INTEGER PRIMARY KEY AUTOINCREMENT,
              e164 TEXT NOT NULL UNIQUE,
              note TEXT
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE health_events (
              id         INTEGER PRIMARY KEY AUTOINCREMENT,
              kind       TEXT NOT NULL,
              detail     TEXT,
              created_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_health_time ON health_events(created_at DESC)")

        seedDefaults(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 1 is the first release; nothing to migrate yet.
    }

    /** A working configuration out of the box, so the app does something useful on day one. */
    private fun seedDefaults(db: SQLiteDatabase) {
        fun rule(
            position: Int,
            name: String,
            min: Int?,
            max: Int?,
            channel: String,
            messages: List<String>,
        ) {
            val values = ContentValues().apply {
                put("position", position)
                put("enabled", 1)
                put("name", name)
                if (min != null) put("attempt_min", min) else putNull("attempt_min")
                if (max != null) put("attempt_max", max) else putNull("attempt_max")
                put("contact_filter", "any")
                put("channel", channel)
            }
            val id = db.insert("rules", null, values)
            messages.forEachIndexed { index, body ->
                db.insert("rule_messages", null, ContentValues().apply {
                    put("rule_id", id)
                    put("position", index)
                    put("body", body)
                })
            }
        }

        rule(0, "First call", 1, 1, CHANNEL_SMS,
            listOf("Sorry, I can't take calls right now. I'll get back to you shortly."))
        rule(1, "Second call", 2, 2, CHANNEL_SMS,
            listOf("Still tied up — is it urgent? Text me here and I'll read it."))
        rule(2, "Third call onwards", 3, null, CHANNEL_SMS,
            listOf("Looks urgent. I'll call you back within 15 minutes."))

        val defaults = mapOf(
            Settings.MASTER_ENABLED to "1",
            Settings.DEFAULT_DELAY_SECONDS to "60",
            Settings.COUNTER_RESET_MODE to Settings.RESET_ON_ANSWERED,
            Settings.QUIET_ENABLED to "0",
            Settings.QUIET_START to "1380",
            Settings.QUIET_END to "480",
            Settings.DAILY_SUMMARY_ENABLED to "1",
            Settings.DAILY_SUMMARY_MINUTE to "1260",
            Settings.THEME to Settings.THEME_SYSTEM,
            Settings.WHATSAPP_MODE to Settings.WA_MODE_BRIDGE,
            Settings.BRIDGE_URL to "https://ctm.ubermensch.cc",
            Settings.DEFAULT_COUNTRY_CODE to "90",
            Settings.DEDUPE_MINUTES to "10",
            Settings.LIST_MODE to Settings.LIST_OFF,
            Settings.SIM_SUBSCRIPTION_ID to "-1",
            Settings.SETUP_COMPLETE to "0",
        )
        defaults.forEach { (key, value) ->
            db.insert("settings", null, ContentValues().apply {
                put("key", key)
                put("value", value)
            })
        }
    }

    // ---- small helpers used across the native layer -------------------------------

    fun setSetting(key: String, value: String) {
        writableDatabase.insertWithOnConflict(
            "settings", null,
            ContentValues().apply {
                put("key", key)
                put("value", value)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun getSetting(key: String, fallback: String): String {
        readableDatabase.rawQuery("SELECT value FROM settings WHERE key = ?", arrayOf(key))
            .use { c -> if (c.moveToFirst()) return c.getString(0) ?: fallback }
        return fallback
    }

    fun allSettings(): JSONObject {
        val out = JSONObject()
        readableDatabase.rawQuery("SELECT key, value FROM settings", null).use { c ->
            while (c.moveToNext()) out.put(c.getString(0), c.getString(1))
        }
        return out
    }

    fun logHealth(kind: String, detail: String? = null) {
        writableDatabase.insert("health_events", null, ContentValues().apply {
            put("kind", kind)
            put("detail", detail)
            put("created_at", System.currentTimeMillis())
        })
        // Keep the health log bounded; it is diagnostics, not history.
        writableDatabase.execSQL(
            "DELETE FROM health_events WHERE id NOT IN (SELECT id FROM health_events ORDER BY created_at DESC LIMIT 500)"
        )
    }
}

// ---- Cursor conveniences ---------------------------------------------------------

fun Cursor.strOrNull(column: String): String? {
    val idx = getColumnIndex(column)
    return if (idx < 0 || isNull(idx)) null else getString(idx)
}

fun Cursor.str(column: String, fallback: String = ""): String = strOrNull(column) ?: fallback

fun Cursor.intOrNull(column: String): Int? {
    val idx = getColumnIndex(column)
    return if (idx < 0 || isNull(idx)) null else getInt(idx)
}

fun Cursor.int(column: String, fallback: Int = 0): Int = intOrNull(column) ?: fallback

fun Cursor.longOrNull(column: String): Long? {
    val idx = getColumnIndex(column)
    return if (idx < 0 || isNull(idx)) null else getLong(idx)
}

fun Cursor.long(column: String, fallback: Long = 0L): Long = longOrNull(column) ?: fallback

fun Cursor.bool(column: String): Boolean = int(column, 0) != 0

fun JSONObject.putOrNull(key: String, value: Any?): JSONObject =
    if (value == null) put(key, JSONObject.NULL) else put(key, value)

fun <T> List<T>.toJsonArray(transform: (T) -> Any): JSONArray {
    val arr = JSONArray()
    forEach { arr.put(transform(it)) }
    return arr
}
