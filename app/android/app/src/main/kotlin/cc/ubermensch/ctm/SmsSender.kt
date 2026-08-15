package cc.ubermensch.ctm

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log

/**
 * Sends the reply as a plain text message. This path never touches the screen, so it works
 * with the phone locked and in your pocket — which is the whole point of the app.
 */
object SmsSender {

    private const val TAG = "SmsSender"

    class SmsFailure(message: String) : Exception(message)

    fun canSend(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun managerFor(context: Context): SmsManager {
        val subId = Settings.int(context, Settings.SIM_SUBSCRIPTION_ID, -1)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val base = context.getSystemService(SmsManager::class.java)
            if (subId >= 0) base.createForSubscriptionId(subId) else base
        } else {
            if (subId >= 0) SmsManager.getSmsManagerForSubscriptionId(subId) else SmsManager.getDefault()
        }
    }

    /**
     * @throws SmsFailure when the message cannot even be handed to the radio. Delivery
     *         results arrive later through [SmsResultReceiver].
     */
    fun send(context: Context, outboxId: Long, toE164: String, body: String) {
        if (!canSend(context)) throw SmsFailure("SMS permission not granted")

        val destination = "+$toE164"
        val sms = managerFor(context)
        val parts = sms.divideMessage(body)

        val sentIntents = ArrayList<PendingIntent>(parts.size)
        val deliveredIntents = ArrayList<PendingIntent>(parts.size)
        for (i in parts.indices) {
            sentIntents.add(resultIntent(context, outboxId, i, SmsResultReceiver.ACTION_SENT))
            deliveredIntents.add(resultIntent(context, outboxId, i, SmsResultReceiver.ACTION_DELIVERED))
        }

        try {
            if (parts.size == 1) {
                sms.sendTextMessage(destination, null, body, sentIntents[0], deliveredIntents[0])
            } else {
                // Turkish characters push the message into UCS-2, which caps a part at 70
                // characters; multipart keeps long replies intact instead of truncating.
                sms.sendMultipartTextMessage(destination, null, parts, sentIntents, deliveredIntents)
            }
            Log.i(TAG, "sms handed to radio: outbox=$outboxId parts=${parts.size}")
        } catch (e: Exception) {
            throw SmsFailure(e.message ?: "SmsManager rejected the message")
        }
    }

    private fun resultIntent(context: Context, outboxId: Long, part: Int, action: String): PendingIntent {
        val intent = Intent(context, SmsResultReceiver::class.java).apply {
            this.action = action
            putExtra(SmsResultReceiver.EXTRA_OUTBOX_ID, outboxId)
            putExtra(SmsResultReceiver.EXTRA_PART, part)
            data = android.net.Uri.parse("autoreply://sms/$action/$outboxId/$part")
        }
        return PendingIntent.getBroadcast(
            context,
            (outboxId * 100 + part).toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Message parts and encoding, so the editor can warn before a reply costs three texts. */
    fun describe(context: Context, body: String): Triple<Int, Int, Boolean> {
        val parts = try {
            managerFor(context).divideMessage(body).size
        } catch (e: Exception) {
            1
        }
        val unicode = body.any { it.code > 127 }
        return Triple(body.length, parts, unicode)
    }

    /** Active SIMs, for the dual-SIM picker in Settings. */
    fun subscriptions(context: Context): List<Pair<Int, String>> {
        if (context.checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) return emptyList()

        return try {
            val sm = context.getSystemService(SubscriptionManager::class.java)
            sm.activeSubscriptionInfoList?.map { info ->
                val label = info.displayName?.toString()?.takeIf { it.isNotBlank() }
                    ?: info.carrierName?.toString()
                    ?: "SIM ${info.simSlotIndex + 1}"
                info.subscriptionId to label
            } ?: emptyList()
        } catch (e: Exception) {
            Log.w(TAG, "subscription lookup failed", e)
            emptyList()
        }
    }
}
