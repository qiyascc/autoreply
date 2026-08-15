package cc.ubermensch.ctm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restores the background machinery after a reboot or an app update. Without this the app
 * would look fine but quietly do nothing until the user next opened it.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.i(TAG, "boot signal: ${intent.action}")
        Db.get(context).logHealth("boot", intent.action)

        Notifications.ensureChannels(context)
        AlarmScheduler.rescheduleAll(context)
        WatchdogService.ensureRunning(context)
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
