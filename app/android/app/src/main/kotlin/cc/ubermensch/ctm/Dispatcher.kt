package cc.ubermensch.ctm

import android.content.ContentValues
import android.content.Context
import android.util.Log
import java.util.Calendar

/**
 * Everything that happens one minute after a missed call.
 *
 * The order matters: every reason *not* to send is checked before anything is sent, and
 * the cheapest, most important check — "did the user already deal with this person?" —
 * is re-run against the live call log at the last possible moment.
 */
object Dispatcher {

    private const val TAG = "Dispatcher"
    private const val GAP_BETWEEN_MESSAGES_MS = 3_000L

    fun dispatch(context: Context, callId: Long) {
        val db = Db.get(context)

        val call = loadCall(context, callId) ?: run {
            Log.w(TAG, "dispatch for unknown call $callId")
            return
        }
        if (call.state != Db.STATE_SCHEDULED) {
            Log.i(TAG, "call $callId already ${call.state}, nothing to do")
            return
        }
        val e164 = call.e164 ?: return cancel(context, callId, "caller id was withheld")

        if (!Settings.bool(context, Settings.MASTER_ENABLED, true)) {
            return cancel(context, callId, "auto-reply is switched off")
        }

        val now = System.currentTimeMillis()
        val minuteOfDay = Calendar.getInstance().apply { timeInMillis = now }.let {
            it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE)
        }
        if (Settings.inQuietHours(context, minuteOfDay)) {
            return cancel(context, callId, "quiet hours")
        }

        RuleEngine.listVeto(context, e164)?.let { return cancel(context, callId, it) }

        // The decisive check. If they have been called back, or a later call was answered,
        // an apology text is worse than silence.
        CallLogReader.handledSince(context, e164, call.occurredAt)?.let {
            return cancel(context, callId, it)
        }

        RuleEngine.dedupeVeto(context, e164, now)?.let { return cancel(context, callId, it) }

        val attempt = RuleEngine.attemptIndex(context, e164, call.occurredAt)
        val rule = RuleEngine.match(context, e164, attempt, now)
            ?: return skip(context, callId, attempt, "no rule matches call #$attempt")

        if (rule.messages.isEmpty()) {
            return skip(context, callId, attempt, "rule '${rule.name}' has no messages")
        }

        db.writableDatabase.update(
            "missed_calls",
            ContentValues().apply {
                put("attempt_index", attempt)
                put("rule_id", rule.id)
                put("rule_name", rule.name)
                put("state", Db.STATE_DISPATCHED)
                put("dispatched_at", now)
            },
            "id = ?",
            arrayOf(callId.toString()),
        )

        val channels = when (rule.channel) {
            Db.CHANNEL_BOTH -> listOf(Db.CHANNEL_SMS, Db.CHANNEL_WHATSAPP)
            else -> listOf(rule.channel)
        }

        Log.i(TAG, "dispatching call $callId attempt=$attempt rule='${rule.name}' channels=$channels")

        var isFirst = true
        for ((index, body) in rule.messages.withIndex()) {
            for (channel in channels) {
                // A small gap keeps carriers and WhatsApp from treating a burst as spam.
                if (!isFirst) Thread.sleep(GAP_BETWEEN_MESSAGES_MS)
                isFirst = false
                sendOne(context, callId, rule, index, channel, e164, body, call.contactName)
            }
        }
    }

    private fun sendOne(
        context: Context,
        callId: Long,
        rule: MatchedRule,
        messageIndex: Int,
        channel: String,
        toE164: String,
        body: String,
        contactName: String?,
    ) {
        val db = Db.get(context)
        val outboxId = db.writableDatabase.insert("outbox", null, ContentValues().apply {
            put("missed_call_id", callId)
            put("rule_id", rule.id)
            put("message_index", messageIndex)
            put("channel", channel)
            put("to_e164", toE164)
            put("body", body)
            put("status", Db.STATUS_PENDING)
            put("scheduled_at", System.currentTimeMillis())
        })

        try {
            when (channel) {
                Db.CHANNEL_SMS -> {
                    SmsSender.send(context, outboxId, toE164, body)
                    // The radio confirms asynchronously; SmsResultReceiver settles the status.
                }

                Db.CHANNEL_WHATSAPP -> {
                    val mode = Settings.str(context, Settings.WHATSAPP_MODE, Settings.WA_MODE_BRIDGE)
                    if (mode == Settings.WA_MODE_DEVICE) {
                        WhatsAppAutomationService.send(context, toE164, body)
                    } else {
                        BridgeClient.sendWhatsApp(context, toE164, body)
                    }
                    markSent(context, outboxId)
                }
            }
        } catch (e: Exception) {
            val reason = e.message ?: e.javaClass.simpleName
            db.writableDatabase.update(
                "outbox",
                ContentValues().apply {
                    put("status", Db.STATUS_FAILED)
                    put("error", reason)
                },
                "id = ?",
                arrayOf(outboxId.toString()),
            )
            Log.w(TAG, "send failed on $channel for outbox=$outboxId: $reason")
            // Configured behaviour is give-up-and-tell-me rather than a silent retry queue.
            Notifications.replyFailed(
                context,
                outboxId,
                buildString {
                    append("Couldn't reply to ")
                    append(contactName ?: PhoneNumbers.pretty(toE164))
                    append(" — ")
                    append(reason)
                },
            )
        }
    }

    private fun markSent(context: Context, outboxId: Long) {
        Db.get(context).writableDatabase.update(
            "outbox",
            ContentValues().apply {
                put("status", Db.STATUS_SENT)
                put("sent_at", System.currentTimeMillis())
                putNull("error")
            },
            "id = ?",
            arrayOf(outboxId.toString()),
        )
    }

    /** Re-sends a single outbox row on demand from the Detail screen. */
    fun retry(context: Context, outboxId: Long) {
        val db = Db.get(context)
        val row = db.readableDatabase.rawQuery(
            "SELECT * FROM outbox WHERE id = ?",
            arrayOf(outboxId.toString()),
        ).use { c ->
            if (!c.moveToFirst()) return
            Triple(c.str("channel"), c.str("to_e164"), c.str("body"))
        }
        val (channel, toE164, body) = row

        db.writableDatabase.update(
            "outbox",
            ContentValues().apply {
                put("status", Db.STATUS_PENDING)
                putNull("error")
            },
            "id = ?",
            arrayOf(outboxId.toString()),
        )

        try {
            when (channel) {
                Db.CHANNEL_SMS -> SmsSender.send(context, outboxId, toE164, body)
                else -> {
                    val mode = Settings.str(context, Settings.WHATSAPP_MODE, Settings.WA_MODE_BRIDGE)
                    if (mode == Settings.WA_MODE_DEVICE) {
                        WhatsAppAutomationService.send(context, toE164, body)
                    } else {
                        BridgeClient.sendWhatsApp(context, toE164, body)
                    }
                    markSent(context, outboxId)
                }
            }
        } catch (e: Exception) {
            db.writableDatabase.update(
                "outbox",
                ContentValues().apply {
                    put("status", Db.STATUS_FAILED)
                    put("error", e.message ?: "retry failed")
                },
                "id = ?",
                arrayOf(outboxId.toString()),
            )
            throw e
        }
    }

    // ---- outcomes that are not sends -------------------------------------------------

    private fun cancel(context: Context, callId: Long, reason: String) {
        Log.i(TAG, "call $callId cancelled: $reason")
        Db.get(context).writableDatabase.update(
            "missed_calls",
            ContentValues().apply {
                put("state", Db.STATE_CANCELLED)
                put("cancel_reason", reason)
            },
            "id = ?",
            arrayOf(callId.toString()),
        )
    }

    private fun skip(context: Context, callId: Long, attempt: Int, reason: String) {
        Log.i(TAG, "call $callId skipped: $reason")
        Db.get(context).writableDatabase.update(
            "missed_calls",
            ContentValues().apply {
                put("state", Db.STATE_SKIPPED)
                put("attempt_index", attempt)
                put("cancel_reason", reason)
            },
            "id = ?",
            arrayOf(callId.toString()),
        )
    }

    private data class Call(
        val id: Long,
        val e164: String?,
        val contactName: String?,
        val occurredAt: Long,
        val state: String,
    )

    private fun loadCall(context: Context, callId: Long): Call? =
        Db.get(context).readableDatabase.rawQuery(
            "SELECT * FROM missed_calls WHERE id = ?",
            arrayOf(callId.toString()),
        ).use { c ->
            if (!c.moveToFirst()) null
            else Call(
                id = c.long("id"),
                e164 = c.strOrNull("e164"),
                contactName = c.strOrNull("contact_name"),
                occurredAt = c.long("occurred_at"),
                state = c.str("state"),
            )
        }
}
