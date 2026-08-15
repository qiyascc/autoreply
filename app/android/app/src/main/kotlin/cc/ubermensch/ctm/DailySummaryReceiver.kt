package cc.ubermensch.ctm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The one notification a day the user asked for. Posts the day's tally and re-arms itself
 * for tomorrow; tapping it opens the Log filtered to that day.
 */
class DailySummaryReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // Re-arm first, so a crash in the summary text does not silently end the series.
        AlarmScheduler.scheduleDailySummary(context)

        if (!Settings.bool(context, Settings.DAILY_SUMMARY_ENABLED, true)) return

        val dayStart = Stats.startOfToday()
        val counts = Stats.today(context)

        // Nothing happened: staying quiet is better than a daily "0 of everything".
        if (counts.missed == 0 && counts.sent == 0 && counts.failed == 0) return

        val title = "Today: ${plural(counts.missed, "missed call")}"
        val body = buildString {
            append(plural(counts.sent, "auto-reply", "auto-replies"))
            append(" sent")
            if (counts.failed > 0) append(" · ${counts.failed} failed")
            if (counts.cancelled > 0) append(" · ${counts.cancelled} cancelled")
            if (counts.skipped > 0) append(" · ${counts.skipped} skipped")
        }

        Notifications.dailySummary(context, title, body, dayStart)
    }

    private fun plural(n: Int, singular: String, plural: String = "${singular}s"): String =
        if (n == 1) "1 $singular" else "$n $plural"
}
