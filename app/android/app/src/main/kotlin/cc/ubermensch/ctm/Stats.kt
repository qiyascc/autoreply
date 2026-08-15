package cc.ubermensch.ctm

import android.content.Context
import org.json.JSONObject
import java.util.Calendar

/** Counters for the Home screen, the ongoing notification and the daily summary. */
object Stats {

    fun startOfToday(): Long = startOfDay(System.currentTimeMillis())

    fun startOfDay(at: Long): Long = Calendar.getInstance().apply {
        timeInMillis = at
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    data class DayCounts(
        val missed: Int,
        val sent: Int,
        val failed: Int,
        val cancelled: Int,
        val skipped: Int,
    ) {
        val handled: Int get() = sent
    }

    fun counts(context: Context, from: Long, to: Long): DayCounts {
        val db = Db.get(context).readableDatabase

        fun callCount(vararg states: String): Int {
            val placeholders = states.joinToString(",") { "?" }
            val args = arrayOf(from.toString(), to.toString(), *states)
            return db.rawQuery(
                "SELECT COUNT(*) FROM missed_calls WHERE occurred_at >= ? AND occurred_at < ? AND state IN ($placeholders)",
                args,
            ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }
        }

        val missed = db.rawQuery(
            "SELECT COUNT(*) FROM missed_calls WHERE occurred_at >= ? AND occurred_at < ?",
            arrayOf(from.toString(), to.toString()),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

        fun outboxCount(vararg statuses: String): Int {
            val placeholders = statuses.joinToString(",") { "?" }
            val args = arrayOf(from.toString(), to.toString(), *statuses)
            return db.rawQuery(
                "SELECT COUNT(*) FROM outbox WHERE scheduled_at >= ? AND scheduled_at < ? AND status IN ($placeholders)",
                args,
            ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }
        }

        return DayCounts(
            missed = missed,
            sent = outboxCount(Db.STATUS_SENT, Db.STATUS_DELIVERED),
            failed = outboxCount(Db.STATUS_FAILED),
            cancelled = callCount(Db.STATE_CANCELLED),
            skipped = callCount(Db.STATE_SKIPPED),
        )
    }

    fun today(context: Context): DayCounts {
        val start = startOfToday()
        return counts(context, start, start + 24 * 60 * 60 * 1000L)
    }

    fun asJson(counts: DayCounts): JSONObject = JSONObject()
        .put("missed", counts.missed)
        .put("sent", counts.sent)
        .put("failed", counts.failed)
        .put("cancelled", counts.cancelled)
        .put("skipped", counts.skipped)

    /**
     * How healthy the background machinery looks — the honest answer to "is this thing
     * actually running?", which matters more than usual on aggressive ROMs.
     */
    fun health(context: Context): JSONObject {
        val db = Db.get(context).readableDatabase
        val since = System.currentTimeMillis() - 24 * 60 * 60 * 1000L

        fun countKind(kind: String): Int = db.rawQuery(
            "SELECT COUNT(*) FROM health_events WHERE kind = ? AND created_at >= ?",
            arrayOf(kind, since.toString()),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

        val lastEvent = db.rawQuery(
            "SELECT kind, created_at FROM health_events ORDER BY created_at DESC LIMIT 1",
            null,
        ).use { c -> if (c.moveToFirst()) c.getString(0) to c.getLong(1) else null }

        return JSONObject()
            .put("ringsSeen24h", countKind("ringing"))
            .put("alarmsFired24h", countKind("alarm_fired"))
            .put("watchdogRestarts24h", countKind("watchdog_started"))
            .put("startRefusals24h", countKind("watchdog_start_refused"))
            .put("lastEventKind", lastEvent?.first ?: JSONObject.NULL)
            .put("lastEventAt", lastEvent?.second ?: JSONObject.NULL)
    }
}
