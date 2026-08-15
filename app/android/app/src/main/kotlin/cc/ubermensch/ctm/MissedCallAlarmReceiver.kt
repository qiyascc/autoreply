package cc.ubermensch.ctm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Fires one minute (or whatever the user set) after a missed call. It does no work itself:
 * a broadcast receiver gets roughly ten seconds before the system considers it hung, and a
 * dispatch can involve two network round trips and a deliberate pause between messages.
 * The actual sending happens in [WatchdogService], which has the runtime to finish.
 */
class MissedCallAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getLongExtra(EXTRA_CALL_ID, -1L)
        if (callId < 0) return
        Log.i(TAG, "alarm fired for missed call $callId")
        Db.get(context).logHealth("alarm_fired", callId.toString())
        WatchdogService.dispatch(context, callId)
    }

    companion object {
        private const val TAG = "MissedCallAlarm"
        const val EXTRA_CALL_ID = "call_id"
    }
}
