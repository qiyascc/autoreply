package cc.ubermensch.ctm

import android.content.Context
import java.util.Calendar

data class MatchedRule(
    val id: Long,
    val name: String,
    val channel: String,
    val messages: List<String>,
    val delaySeconds: Int?,
)

/**
 * Decides *whether* to reply and *what* to say. Kept free of Android plumbing so the
 * behaviour is easy to reason about: inputs are the caller, the attempt count and the
 * clock; the output is a rule or nothing.
 */
object RuleEngine {

    /**
     * How many times this person has called without reaching you, counting the call that
     * just came in. The window depends on the configured reset mode — the default treats
     * an actual conversation as wiping the slate clean, so a caller you spoke to this
     * morning starts again at "first call" tonight.
     */
    fun attemptIndex(context: Context, e164: String, occurredAt: Long): Int {
        val mode = Settings.str(context, Settings.COUNTER_RESET_MODE, Settings.RESET_ON_ANSWERED)

        val boundary: Long = when (mode) {
            Settings.RESET_NEVER -> 0L
            Settings.RESET_ON_ANSWERED ->
                CallLogReader.lastConversationAt(context, e164)?.plus(1) ?: 0L
            else -> occurredAt - (Settings.counterWindowMs(mode) ?: 0L)
        }

        val db = Db.get(context)
        // Compare on the last 9 digits so a number stored with a different country-code
        // guess still lands in the same tally.
        val tail = e164.takeLast(9)
        db.readableDatabase.rawQuery(
            """
            SELECT COUNT(*) FROM missed_calls
            WHERE substr(e164, -9) = ? AND occurred_at >= ? AND occurred_at <= ?
            """.trimIndent(),
            arrayOf(tail, boundary.toString(), occurredAt.toString()),
        ).use { c ->
            return if (c.moveToFirst()) maxOf(1, c.getInt(0)) else 1
        }
    }

    /** The first enabled rule whose conditions all hold, or null when none apply. */
    fun match(context: Context, e164: String, attemptIndex: Int, at: Long): MatchedRule? {
        val known = Contacts.isKnown(context, e164)
        val minuteOfDay = Calendar.getInstance().apply { timeInMillis = at }.let {
            it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE)
        }

        val db = Db.get(context)
        db.readableDatabase.rawQuery(
            "SELECT * FROM rules WHERE enabled = 1 ORDER BY position ASC, id ASC",
            null,
        ).use { c ->
            while (c.moveToNext()) {
                val min = c.intOrNull("attempt_min")
                val max = c.intOrNull("attempt_max")
                if (min != null && attemptIndex < min) continue
                if (max != null && attemptIndex > max) continue

                val start = c.intOrNull("time_start")
                val end = c.intOrNull("time_end")
                if (start != null && end != null && !inWindow(minuteOfDay, start, end)) continue

                when (c.str("contact_filter", "any")) {
                    "known" -> if (!known) continue
                    "unknown" -> if (known) continue
                }

                val id = c.long("id")
                return MatchedRule(
                    id = id,
                    name = c.str("name", "Rule $id"),
                    channel = c.str("channel", Db.CHANNEL_SMS),
                    messages = messagesFor(context, id),
                    delaySeconds = c.intOrNull("delay_seconds"),
                )
            }
        }
        return null
    }

    fun messagesFor(context: Context, ruleId: Long): List<String> {
        val out = mutableListOf<String>()
        Db.get(context).readableDatabase.rawQuery(
            "SELECT body FROM rule_messages WHERE rule_id = ? ORDER BY position ASC, id ASC",
            arrayOf(ruleId.toString()),
        ).use { c -> while (c.moveToNext()) out.add(c.getString(0)) }
        return out
    }

    /** Minute-of-day window that may wrap past midnight. */
    private fun inWindow(minute: Int, start: Int, end: Int): Boolean =
        if (start <= end) minute in start until end else minute >= start || minute < end

    /**
     * Applies the block/allow list. Returns a human-readable reason to skip, or null to proceed.
     */
    fun listVeto(context: Context, e164: String): String? {
        val mode = Settings.str(context, Settings.LIST_MODE, Settings.LIST_OFF)
        if (mode == Settings.LIST_OFF) return null

        val tail = e164.takeLast(9)
        val listed = Db.get(context).readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM number_list WHERE substr(e164, -9) = ?",
            arrayOf(tail),
        ).use { c -> c.moveToFirst() && c.getInt(0) > 0 }

        return when (mode) {
            Settings.LIST_BLOCK -> if (listed) "number is on the block list" else null
            Settings.LIST_ALLOW -> if (!listed) "number is not on the allow list" else null
            else -> null
        }
    }

    /**
     * Guards against replying twice to someone who called repeatedly in quick succession.
     * Returns a reason to skip, or null.
     */
    fun dedupeVeto(context: Context, e164: String, before: Long): String? {
        val minutes = Settings.int(context, Settings.DEDUPE_MINUTES, 10)
        if (minutes <= 0) return null
        val since = before - minutes * 60_000L
        val tail = e164.takeLast(9)

        val recent = Db.get(context).readableDatabase.rawQuery(
            """
            SELECT COUNT(*) FROM outbox
            WHERE substr(to_e164, -9) = ? AND status IN (?, ?) AND sent_at >= ?
            """.trimIndent(),
            arrayOf(tail, Db.STATUS_SENT, Db.STATUS_DELIVERED, since.toString()),
        ).use { c -> c.moveToFirst() && c.getInt(0) > 0 }

        return if (recent) "already replied within the last $minutes minutes" else null
    }
}
