package cc.ubermensch.ctm

import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import android.util.Log

/**
 * The call log is the second opinion. PHONE_STATE tells us a call ended, but only the log
 * can confirm it was really missed, and whether anything has happened since — which is what
 * lets us cancel a reply the moment the user calls the person back.
 */
object CallLogReader {

    private const val TAG = "CallLogReader"

    private fun canRead(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED

    /** Newest missed-call number logged at or after [since], used when the broadcast had none. */
    fun latestMissedNumber(context: Context, since: Long): String? {
        if (!canRead(context)) return null
        return try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.TYPE),
                "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.TYPE} IN (?, ?)",
                arrayOf(
                    since.toString(),
                    CallLog.Calls.MISSED_TYPE.toString(),
                    CallLog.Calls.REJECTED_TYPE.toString(),
                ),
                "${CallLog.Calls.DATE} DESC LIMIT 1",
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            Log.w(TAG, "call log lookup failed", e)
            null
        }
    }

    /**
     * True when the user has since dealt with this caller themselves — either they called
     * back, or a later call from the same number was answered. Sending an "I can't talk"
     * text after the conversation already happened is the worst failure mode this app has,
     * so this check runs immediately before every dispatch.
     */
    fun handledSince(context: Context, e164: String, since: Long): String? {
        if (!canRead(context)) return null
        return try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.TYPE),
                "${CallLog.Calls.DATE} > ?",
                arrayOf(since.toString()),
                "${CallLog.Calls.DATE} DESC LIMIT 40",
            )?.use { c ->
                val countryCode = Settings.countryCode(context)
                while (c.moveToNext()) {
                    val logged = PhoneNumbers.toE164(c.getString(0), countryCode) ?: continue
                    if (!PhoneNumbers.sameNumber(logged, e164)) continue
                    when (c.getInt(2)) {
                        CallLog.Calls.OUTGOING_TYPE -> return@use "you called them back"
                        CallLog.Calls.INCOMING_TYPE -> return@use "you answered a later call"
                    }
                }
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "call log check failed", e)
            null
        }
    }

    /**
     * Timestamp of the most recent two-way conversation with this number — an answered
     * incoming call or an outgoing one. Used by the "reset counter when we talk" mode.
     */
    fun lastConversationAt(context: Context, e164: String): Long? {
        if (!canRead(context)) return null
        return try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.TYPE, CallLog.Calls.DURATION),
                "${CallLog.Calls.TYPE} IN (?, ?)",
                arrayOf(
                    CallLog.Calls.INCOMING_TYPE.toString(),
                    CallLog.Calls.OUTGOING_TYPE.toString(),
                ),
                "${CallLog.Calls.DATE} DESC LIMIT 200",
            )?.use { c ->
                val countryCode = Settings.countryCode(context)
                while (c.moveToNext()) {
                    val logged = PhoneNumbers.toE164(c.getString(0), countryCode) ?: continue
                    if (!PhoneNumbers.sameNumber(logged, e164)) continue
                    // A zero-duration outgoing call never connected; it does not count as talking.
                    if (c.getLong(3) <= 0L && c.getInt(2) == CallLog.Calls.OUTGOING_TYPE) continue
                    return@use c.getLong(1)
                }
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "conversation lookup failed", e)
            null
        }
    }
}
