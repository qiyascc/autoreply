package cc.ubermensch.ctm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar

/**
 * WorkManager cannot honour a one-minute delay under Doze — its minimum useful latency is
 * far longer than the window this app cares about. An exact alarm is the only scheduler
 * that reliably fires 60 seconds after a missed call on a dozing phone.
 */
object AlarmScheduler {

    private const val TAG = "AlarmScheduler"
    private const val DAILY_SUMMARY_REQUEST = 10_000_000

    fun canScheduleExact(context: Context): Boolean {
        val am = context.getSystemService(AlarmManager::class.java)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true
    }

    fun scheduleDispatch(context: Context, missedCallId: Long, delayMs: Long) {
        val am = context.getSystemService(AlarmManager::class.java)
        val triggerAt = System.currentTimeMillis() + delayMs
        val pending = dispatchIntent(context, missedCallId)

        try {
            if (canScheduleExact(context)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                // Without the exact-alarm permission we still fire, just with OS-chosen slack.
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                Db.get(context).logHealth("inexact_alarm", "exact alarm permission missing")
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "exact alarm refused, falling back", e)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    fun cancelDispatch(context: Context, missedCallId: Long) {
        context.getSystemService(AlarmManager::class.java)
            .cancel(dispatchIntent(context, missedCallId))
    }

    private fun dispatchIntent(context: Context, missedCallId: Long): PendingIntent {
        val intent = Intent(context, MissedCallAlarmReceiver::class.java).apply {
            action = "cc.ubermensch.ctm.DISPATCH"
            putExtra(MissedCallAlarmReceiver.EXTRA_CALL_ID, missedCallId)
            // The id has to be part of the intent's identity, or several pending calls
            // would collapse into a single alarm.
            data = android.net.Uri.parse("autoreply://dispatch/$missedCallId")
        }
        return PendingIntent.getBroadcast(
            context,
            missedCallId.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ---- daily summary ------------------------------------------------------------

    fun scheduleDailySummary(context: Context) {
        val am = context.getSystemService(AlarmManager::class.java)
        val pending = dailySummaryIntent(context)

        if (!Settings.bool(context, Settings.DAILY_SUMMARY_ENABLED, true)) {
            am.cancel(pending)
            return
        }

        val minuteOfDay = Settings.int(context, Settings.DAILY_SUMMARY_MINUTE, 1260)
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
            set(Calendar.MINUTE, minuteOfDay % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }

        try {
            if (canScheduleExact(context)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pending)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pending)
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pending)
        }
        Log.i(TAG, "daily summary scheduled for ${next.time}")
    }

    private fun dailySummaryIntent(context: Context): PendingIntent {
        val intent = Intent(context, DailySummaryReceiver::class.java)
            .setAction("cc.ubermensch.ctm.DAILY_SUMMARY")
        return PendingIntent.getBroadcast(
            context,
            DAILY_SUMMARY_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Re-arms anything that was lost across a reboot or an app update. */
    fun rescheduleAll(context: Context) {
        scheduleDailySummary(context)

        val db = Db.get(context)
        val now = System.currentTimeMillis()
        val delayMs = Settings.int(context, Settings.DEFAULT_DELAY_SECONDS, 60) * 1000L
        db.readableDatabase.rawQuery(
            "SELECT id, occurred_at FROM missed_calls WHERE state = ?",
            arrayOf(Db.STATE_SCHEDULED),
        ).use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val due = c.getLong(1) + delayMs
                // Anything already overdue fires on a short fuse rather than immediately,
                // so a reboot does not dump a burst of texts at once.
                scheduleDispatch(context, id, if (due > now) due - now else 5_000L)
            }
        }
    }
}
