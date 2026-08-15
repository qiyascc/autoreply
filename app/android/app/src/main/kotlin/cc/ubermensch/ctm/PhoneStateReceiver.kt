package cc.ubermensch.ctm

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Statically registered in the manifest so it keeps firing after the app is swiped away.
 *
 * Missed call = the phone reached RINGING and returned to IDLE without ever going
 * OFFHOOK. Answering, rejecting from the notification shade and outgoing calls all take
 * different paths and are left alone.
 */
class PhoneStateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        @Suppress("DEPRECATION")
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        Log.d(TAG, "phone state=$state hasNumber=${!number.isNullOrBlank()}")

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                CallState.onRinging(context, number)
                Db.get(context).logHealth("ringing")
                // Keep the watchdog alive while a call is in flight, so the IDLE broadcast
                // and the follow-up alarm are not competing with an idle-process kill.
                WatchdogService.ensureRunning(context)
            }

            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                CallState.rememberNumber(context, number)
                CallState.onOffHook(context)
            }

            TelephonyManager.EXTRA_STATE_IDLE -> {
                CallState.rememberNumber(context, number)
                val missed = CallState.onIdle(context) ?: return
                handleMissedCall(context, missed)
            }
        }
    }

    private fun handleMissedCall(context: Context, missed: CallState.Missed) {
        val db = Db.get(context)

        if (!Settings.bool(context, Settings.MASTER_ENABLED, true)) {
            db.logHealth("missed_ignored", "master switch off")
            return
        }

        // The broadcast extra is unreliable on some ROMs; the call log is authoritative.
        val resolved = missed.number
            ?: CallLogReader.latestMissedNumber(context, since = missed.endedAt - 60_000L)

        val e164 = PhoneNumbers.toE164(resolved, Settings.countryCode(context))
        if (e164 == null) {
            db.logHealth("missed_ignored", "withheld or unusable caller id")
            return
        }

        val contactName = Contacts.displayName(context, e164)
        val values = ContentValues().apply {
            put("number", resolved)
            put("e164", e164)
            put("contact_name", contactName)
            put("occurred_at", missed.endedAt)
            put("state", Db.STATE_SCHEDULED)
        }
        val callId = db.writableDatabase.insert("missed_calls", null, values)
        db.logHealth("missed_recorded", e164)

        val delaySeconds = Settings.int(context, Settings.DEFAULT_DELAY_SECONDS, 60)
        AlarmScheduler.scheduleDispatch(context, callId, delaySeconds * 1000L)
        Log.i(TAG, "missed call #$callId recorded, dispatch in ${delaySeconds}s")
    }

    companion object {
        private const val TAG = "PhoneStateReceiver"
    }
}
