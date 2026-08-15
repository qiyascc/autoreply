package cc.ubermensch.ctm

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * A permanently running foreground service.
 *
 * Two jobs. First, it keeps the process warm so MIUI is less eager to kill us between a
 * ring and the follow-up alarm. Second, it is where dispatches actually run: it has no
 * ten-second ceiling, so a send can wait on the network and pause between messages.
 */
class WatchdogService : Service() {

    private val workers = Executors.newSingleThreadExecutor()
    private val outstanding = AtomicInteger(0)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(this)
        startForeground(Notifications.ID_WATCHDOG, Notifications.watchdog(this, statusLine()))
        Db.get(this).logHealth("watchdog_started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Re-assert foreground on every command: restarts land here without onCreate.
        startForeground(Notifications.ID_WATCHDOG, Notifications.watchdog(this, statusLine()))

        when (intent?.action) {
            ACTION_DISPATCH -> {
                val callId = intent.getLongExtra(EXTRA_CALL_ID, -1L)
                if (callId >= 0) runDispatch(callId)
            }

            ACTION_RETRY -> {
                val outboxId = intent.getLongExtra(EXTRA_OUTBOX_ID, -1L)
                if (outboxId >= 0) runWithWakeLock("retry") { Dispatcher.retry(this, outboxId) }
            }

            ACTION_REFRESH -> Notifications.updateWatchdog(this, statusLine())
        }

        // START_STICKY so the system brings us back if it reclaims the process.
        return START_STICKY
    }

    private fun runDispatch(callId: Long) {
        outstanding.incrementAndGet()
        runWithWakeLock("dispatch-$callId") {
            try {
                Dispatcher.dispatch(this, callId)
            } finally {
                outstanding.decrementAndGet()
                Notifications.updateWatchdog(this, statusLine())
            }
        }
    }

    private fun runWithWakeLock(tag: String, block: () -> Unit) {
        workers.execute {
            val pm = getSystemService(PowerManager::class.java)
            val lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "autoreply:$tag")
            lock.acquire(2 * 60 * 1000L)
            try {
                block()
            } catch (e: Exception) {
                Log.e(TAG, "work '$tag' failed", e)
                Db.get(this).logHealth("work_failed", "$tag: ${e.message}")
            } finally {
                if (lock.isHeld) lock.release()
            }
        }
    }

    /** The one-liner shown under the ongoing notification. */
    private fun statusLine(): String {
        if (!Settings.bool(this, Settings.MASTER_ENABLED, true)) return "Paused"
        val pending = outstanding.get()
        if (pending > 0) return "Sending $pending ${if (pending == 1) "reply" else "replies"}…"

        val db = Db.get(this)
        val dayStart = Stats.startOfToday()
        val sent = db.readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM outbox WHERE status IN (?, ?) AND scheduled_at >= ?",
            arrayOf(Db.STATUS_SENT, Db.STATUS_DELIVERED, dayStart.toString()),
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

        return if (sent == 0) "No replies sent today" else "$sent sent today"
    }

    override fun onDestroy() {
        Db.get(this).logHealth("watchdog_stopped")
        workers.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "WatchdogService"
        const val ACTION_DISPATCH = "cc.ubermensch.ctm.DISPATCH"
        const val ACTION_RETRY = "cc.ubermensch.ctm.RETRY"
        const val ACTION_REFRESH = "cc.ubermensch.ctm.REFRESH"
        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_OUTBOX_ID = "outbox_id"

        private fun start(context: Context, intent: Intent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ can refuse a background start. Nothing is lost: the row stays
                // scheduled and the next ring or app launch picks it up.
                Log.w(TAG, "could not start watchdog", e)
                Db.get(context).logHealth("watchdog_start_refused", e.message)
            }
        }

        fun ensureRunning(context: Context) {
            if (!Settings.bool(context, Settings.MASTER_ENABLED, true)) return
            start(context, Intent(context, WatchdogService::class.java).setAction(ACTION_REFRESH))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, WatchdogService::class.java))
        }

        fun dispatch(context: Context, callId: Long) {
            start(
                context,
                Intent(context, WatchdogService::class.java)
                    .setAction(ACTION_DISPATCH)
                    .putExtra(EXTRA_CALL_ID, callId),
            )
        }

        fun retry(context: Context, outboxId: Long) {
            start(
                context,
                Intent(context, WatchdogService::class.java)
                    .setAction(ACTION_RETRY)
                    .putExtra(EXTRA_OUTBOX_ID, outboxId),
            )
        }
    }
}
