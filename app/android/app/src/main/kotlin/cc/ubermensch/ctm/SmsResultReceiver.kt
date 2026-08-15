package cc.ubermensch.ctm

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.telephony.SmsManager
import android.util.Log

/**
 * Turns the radio's asynchronous verdict into an outbox status, so the Log screen can say
 * "delivered" rather than the optimistic "sent" every SMS app defaults to.
 */
class SmsResultReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val outboxId = intent.getLongExtra(EXTRA_OUTBOX_ID, -1L)
        if (outboxId < 0) return
        val db = Db.get(context)

        when (intent.action) {
            ACTION_SENT -> {
                if (resultCode == Activity.RESULT_OK) {
                    // Only promote to "sent"; a later delivery report may upgrade it again.
                    db.writableDatabase.execSQL(
                        "UPDATE outbox SET status = ?, sent_at = COALESCE(sent_at, ?), error = NULL WHERE id = ? AND status != ?",
                        arrayOf<Any>(Db.STATUS_SENT, System.currentTimeMillis(), outboxId, Db.STATUS_DELIVERED),
                    )
                } else {
                    val reason = describeFailure(resultCode)
                    db.writableDatabase.update(
                        "outbox",
                        ContentValues().apply {
                            put("status", Db.STATUS_FAILED)
                            put("error", reason)
                        },
                        "id = ?",
                        arrayOf(outboxId.toString()),
                    )
                    Log.w(TAG, "sms failed for outbox=$outboxId: $reason")
                    Notifications.replyFailed(context, outboxId, reason)
                }
            }

            ACTION_DELIVERED -> {
                db.writableDatabase.execSQL(
                    "UPDATE outbox SET status = ?, delivered_at = ? WHERE id = ? AND status != ?",
                    arrayOf<Any>(Db.STATUS_DELIVERED, System.currentTimeMillis(), outboxId, Db.STATUS_FAILED),
                )
            }
        }
    }

    private fun describeFailure(code: Int): String = when (code) {
        SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "generic radio failure"
        SmsManager.RESULT_ERROR_NO_SERVICE -> "no network service"
        SmsManager.RESULT_ERROR_NULL_PDU -> "null PDU"
        SmsManager.RESULT_ERROR_RADIO_OFF -> "radio is off (flight mode?)"
        else -> "SMS failed with code $code"
    }

    companion object {
        private const val TAG = "SmsResultReceiver"
        const val ACTION_SENT = "cc.ubermensch.ctm.SMS_SENT"
        const val ACTION_DELIVERED = "cc.ubermensch.ctm.SMS_DELIVERED"
        const val EXTRA_OUTBOX_ID = "outbox_id"
        const val EXTRA_PART = "part"
    }
}
