package cc.ubermensch.ctm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * All user-facing notifications are posted natively. The alarm that reports a failure can
 * fire with no Flutter engine alive, so routing this through a Dart plugin would mean the
 * one notification you most need — "I couldn't reply" — is the one most likely to go missing.
 */
object Notifications {

    private const val CHANNEL_ONGOING = "ongoing"
    private const val CHANNEL_ALERTS = "alerts"
    private const val CHANNEL_SUMMARY = "summary"

    const val ID_WATCHDOG = 1
    const val ID_SUMMARY = 2
    private const val ID_FAILURE_BASE = 1000

    fun ensureChannels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)

        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ONGOING,
                "Watch status",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "The quiet, permanent notice that call watching is active."
                setShowBadge(false)
            }
        )

        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                "Delivery problems",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Tells you when a reply could not be delivered."
            }
        )

        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_SUMMARY,
                "Daily summary",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "One notification at the end of the day with the day's activity."
            }
        )
    }

    private fun canPost(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun openApp(context: Context, route: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            route?.let { putExtra(MainActivity.EXTRA_ROUTE, it) }
        }
        return PendingIntent.getActivity(
            context,
            route?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** The foreground-service notification. Kept at minimum importance so it sits silently. */
    fun watchdog(context: Context, summary: String): Notification =
        Notification.Builder(context, CHANNEL_ONGOING)
            .setSmallIcon(R.drawable.ic_stat_autoreply)
            .setContentTitle("Autoreply is watching for calls")
            .setContentText(summary)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(openApp(context, null))
            .build()

    fun updateWatchdog(context: Context, summary: String) {
        if (!canPost(context)) return
        context.getSystemService(NotificationManager::class.java)
            .notify(ID_WATCHDOG, watchdog(context, summary))
    }

    fun replyFailed(context: Context, outboxId: Long, message: String) {
        if (!canPost(context)) return
        val notification = Notification.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_autoreply)
            .setContentTitle("Auto-reply not sent")
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setAutoCancel(true)
            .setContentIntent(openApp(context, "/log/outbox/$outboxId"))
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(ID_FAILURE_BASE + outboxId.toInt(), notification)
    }

    fun dailySummary(context: Context, title: String, body: String, dayStart: Long) {
        if (!canPost(context)) return
        val notification = Notification.Builder(context, CHANNEL_SUMMARY)
            .setSmallIcon(R.drawable.ic_stat_autoreply)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp(context, "/log?day=$dayStart"))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(ID_SUMMARY, notification)
    }
}
