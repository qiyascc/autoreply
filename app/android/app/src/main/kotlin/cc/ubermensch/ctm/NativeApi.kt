package cc.ubermensch.ctm

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * The whole surface Flutter can touch.
 *
 * Native code owns the database and every background path, so the UI is a thin client:
 * it asks questions and issues commands over this channel and renders whatever comes
 * back. Results are JSON strings — one encoding rule, no platform-map gymnastics.
 */
class NativeApi(private val context: Context, private val activity: () -> Activity?) {

    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // ---- state ------------------------------------------------------------
            "getStatus" -> reply(result) { status() }
            "getSettings" -> reply(result) { Db.get(context).allSettings() }
            "setSetting" -> reply(result) {
                val key = call.argument<String>("key")!!
                val value = call.argument<String>("value")!!
                applySetting(key, value)
                Db.get(context).allSettings()
            }

            // ---- rules ------------------------------------------------------------
            "getRules" -> reply(result) { JSONObject().put("rules", rules()) }
            "saveRule" -> reply(result) {
                val id = saveRule(JSONObject(call.argument<String>("rule")!!))
                JSONObject().put("id", id).put("rules", rules())
            }
            "deleteRule" -> reply(result) {
                Db.get(context).writableDatabase.delete(
                    "rules", "id = ?", arrayOf(call.argument<Int>("id")!!.toString())
                )
                JSONObject().put("rules", rules())
            }
            "reorderRules" -> reply(result) {
                val ids = call.argument<List<Int>>("ids")!!
                val db = Db.get(context).writableDatabase
                db.beginTransaction()
                try {
                    ids.forEachIndexed { position, id ->
                        db.execSQL("UPDATE rules SET position = ? WHERE id = ?", arrayOf(position, id))
                    }
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
                JSONObject().put("rules", rules())
            }

            // ---- history ----------------------------------------------------------
            "getLog" -> reply(result) {
                JSONObject().put(
                    "entries",
                    logEntries(
                        limit = call.argument<Int>("limit") ?: 100,
                        offset = call.argument<Int>("offset") ?: 0,
                        dayStart = call.argument<Long>("dayStart"),
                        statusFilter = call.argument<String>("status"),
                        channelFilter = call.argument<String>("channel"),
                    )
                )
            }
            "getLogEntry" -> reply(result) { logEntry(call.argument<Int>("id")!!.toLong()) }
            "findEntryForOutbox" -> reply(result) {
                val outboxId = call.argument<Int>("outboxId")!!.toLong()
                val callId = Db.get(context).readableDatabase.rawQuery(
                    "SELECT missed_call_id FROM outbox WHERE id = ?",
                    arrayOf(outboxId.toString()),
                ).use { c -> if (c.moveToFirst()) c.getLong(0) else -1L }
                if (callId < 0) JSONObject() else logEntry(callId)
            }
            "retryOutbox" -> reply(result) {
                Dispatcher.retry(context, call.argument<Int>("outboxId")!!.toLong())
                JSONObject().put("ok", true)
            }
            "clearHistory" -> reply(result) {
                Db.get(context).writableDatabase.apply {
                    execSQL("DELETE FROM outbox")
                    execSQL("DELETE FROM missed_calls")
                }
                JSONObject().put("ok", true)
            }

            // ---- number list ------------------------------------------------------
            "getNumberList" -> reply(result) { JSONObject().put("numbers", numberList()) }
            "addNumber" -> reply(result) {
                val e164 = PhoneNumbers.toE164(
                    call.argument<String>("number"), Settings.countryCode(context)
                ) ?: throw IllegalArgumentException("That does not look like a phone number")
                Db.get(context).writableDatabase.insertWithOnConflict(
                    "number_list", null,
                    ContentValues().apply {
                        put("e164", e164)
                        put("note", call.argument<String>("note"))
                    },
                    android.database.sqlite.SQLiteDatabase.CONFLICT_IGNORE,
                )
                JSONObject().put("numbers", numberList())
            }
            "removeNumber" -> reply(result) {
                Db.get(context).writableDatabase.delete(
                    "number_list", "id = ?", arrayOf(call.argument<Int>("id")!!.toString())
                )
                JSONObject().put("numbers", numberList())
            }

            // ---- device setup -----------------------------------------------------
            "getSetupStatus" -> reply(result) {
                DeviceSetup.status(context).put("vendorSteps", DeviceSetup.vendorSteps(context))
            }
            "requestPermissions" -> {
                val activity = activity()
                if (activity == null) {
                    result.error("no_activity", "The app window is not available", null)
                } else {
                    activity.requestPermissions(
                        DeviceSetup.RUNTIME_PERMISSIONS.filterNot {
                            DeviceSetup.isGranted(context, it)
                        }.toTypedArray(),
                        MainActivity.PERMISSION_REQUEST_CODE,
                    )
                    result.success(JSONObject().put("requested", true).toString())
                }
            }
            "openSystemPage" -> reply(result) {
                openSystemPage(call.argument<String>("key")!!)
                JSONObject().put("ok", true)
            }
            "completeSetup" -> reply(result) {
                Db.get(context).setSetting(Settings.SETUP_COMPLETE, "1")
                WatchdogService.ensureRunning(context)
                AlarmScheduler.scheduleDailySummary(context)
                status()
            }

            // ---- SIM / message helpers -------------------------------------------
            "getSims" -> reply(result) {
                val sims = JSONArray()
                SmsSender.subscriptions(context).forEach { (id, label) ->
                    sims.put(JSONObject().put("id", id).put("label", label))
                }
                JSONObject().put("sims", sims)
            }
            "describeMessage" -> reply(result) {
                val (chars, parts, unicode) = SmsSender.describe(
                    context, call.argument<String>("body") ?: ""
                )
                JSONObject().put("chars", chars).put("parts", parts).put("unicode", unicode)
            }

            // ---- bridge -----------------------------------------------------------
            "bridgeRegister" -> replyAsync(result) {
                BridgeClient.registerDevice(
                    context,
                    call.argument<String>("inviteCode")!!.trim(),
                    call.argument<String>("name") ?: android.os.Build.MODEL,
                )
                status()
            }
            "bridgeCreateSession" -> replyAsync(result) {
                val handle = BridgeClient.createSession(context, call.argument<String>("phone")!!)
                JSONObject()
                    .put("sessionId", handle.sessionId)
                    .put("linkUrl", handle.linkUrl)
                    .put("expiresAt", handle.expiresAt)
            }
            "bridgeSessionStatus" -> replyAsync(result) {
                val sessionId = Settings.str(context, Settings.BRIDGE_SESSION_ID, "")
                if (sessionId.isBlank()) JSONObject().put("status", "none")
                else BridgeClient.sessionStatus(context, sessionId)
            }
            "bridgePairingCode" -> replyAsync(result) {
                val sessionId = Settings.str(context, Settings.BRIDGE_SESSION_ID, "")
                if (sessionId.isBlank()) throw IllegalStateException("Start linking first")
                val code = BridgeClient.requestPairingCode(context, sessionId)
                JSONObject().put("code", code ?: JSONObject.NULL).put("pending", code == null)
            }
            "bridgeStats" -> replyAsync(result) { BridgeClient.stats(context) }
            "bridgeLogout" -> replyAsync(result) {
                BridgeClient.logout(context)
                status()
            }

            "testSend" -> replyAsync(result) {
                val channel = call.argument<String>("channel")!!
                val to = PhoneNumbers.toE164(
                    call.argument<String>("to"), Settings.countryCode(context)
                ) ?: throw IllegalArgumentException("That does not look like a phone number")
                val text = call.argument<String>("text") ?: "Test from Autoreply."
                testSend(channel, to, text)
                JSONObject().put("ok", true)
            }

            else -> result.notImplemented()
        }
    }

    // ---- implementations ---------------------------------------------------------

    private fun status(): JSONObject {
        val today = Stats.today(context)
        return JSONObject()
            .put("settings", Db.get(context).allSettings())
            .put("today", Stats.asJson(today))
            .put("health", Stats.health(context))
            .put("bridgeLinked", BridgeClient.isLinked(context))
            .put("whatsappInstalled", WhatsAppAutomationService.isWhatsAppInstalled(context))
            .put("accessibilityEnabled", WhatsAppAutomationService.isEnabled(context))
            .put("setupComplete", Settings.bool(context, Settings.SETUP_COMPLETE))
            .put("recent", logEntries(limit = 5, offset = 0, dayStart = null, statusFilter = null, channelFilter = null))
    }

    /** Settings that need something to happen beyond writing the row. */
    private fun applySetting(key: String, value: String) {
        Db.get(context).setSetting(key, value)
        when (key) {
            Settings.MASTER_ENABLED ->
                if (value == "1") WatchdogService.ensureRunning(context) else WatchdogService.stop(context)

            Settings.DAILY_SUMMARY_ENABLED, Settings.DAILY_SUMMARY_MINUTE ->
                AlarmScheduler.scheduleDailySummary(context)
        }
    }

    private fun rules(): JSONArray {
        val db = Db.get(context).readableDatabase
        val out = JSONArray()
        db.rawQuery("SELECT * FROM rules ORDER BY position ASC, id ASC", null).use { c ->
            while (c.moveToNext()) {
                val id = c.long("id")
                val messages = JSONArray()
                RuleEngine.messagesFor(context, id).forEach { messages.put(it) }
                out.put(
                    JSONObject()
                        .put("id", id)
                        .put("position", c.int("position"))
                        .put("enabled", c.bool("enabled"))
                        .put("name", c.str("name"))
                        .putOrNull("attemptMin", c.intOrNull("attempt_min"))
                        .putOrNull("attemptMax", c.intOrNull("attempt_max"))
                        .putOrNull("timeStart", c.intOrNull("time_start"))
                        .putOrNull("timeEnd", c.intOrNull("time_end"))
                        .put("contactFilter", c.str("contact_filter", "any"))
                        .put("channel", c.str("channel"))
                        .putOrNull("delaySeconds", c.intOrNull("delay_seconds"))
                        .put("messages", messages)
                )
            }
        }
        return out
    }

    private fun saveRule(json: JSONObject): Long {
        val db = Db.get(context).writableDatabase
        val values = ContentValues().apply {
            put("name", json.optString("name", "Rule"))
            put("enabled", if (json.optBoolean("enabled", true)) 1 else 0)
            put("contact_filter", json.optString("contactFilter", "any"))
            put("channel", json.optString("channel", Db.CHANNEL_SMS))
            fun optInt(key: String, column: String) {
                if (json.isNull(key)) putNull(column) else put(column, json.getInt(key))
            }
            optInt("attemptMin", "attempt_min")
            optInt("attemptMax", "attempt_max")
            optInt("timeStart", "time_start")
            optInt("timeEnd", "time_end")
            optInt("delaySeconds", "delay_seconds")
        }

        val id: Long
        db.beginTransaction()
        try {
            if (json.isNull("id") || json.optLong("id", -1L) <= 0L) {
                val nextPosition = db.rawQuery("SELECT COALESCE(MAX(position), -1) + 1 FROM rules", null)
                    .use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }
                values.put("position", nextPosition)
                id = db.insert("rules", null, values)
            } else {
                id = json.getLong("id")
                db.update("rules", values, "id = ?", arrayOf(id.toString()))
                db.delete("rule_messages", "rule_id = ?", arrayOf(id.toString()))
            }

            val messages = json.optJSONArray("messages") ?: JSONArray()
            for (i in 0 until messages.length()) {
                val body = messages.getString(i).trim()
                if (body.isEmpty()) continue
                db.insert("rule_messages", null, ContentValues().apply {
                    put("rule_id", id)
                    put("position", i)
                    put("body", body)
                })
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return id
    }

    private fun logEntries(
        limit: Int,
        offset: Int,
        dayStart: Long?,
        statusFilter: String?,
        channelFilter: String?,
    ): JSONArray {
        val where = StringBuilder("1 = 1")
        val args = mutableListOf<String>()

        if (dayStart != null) {
            where.append(" AND mc.occurred_at >= ? AND mc.occurred_at < ?")
            args.add(dayStart.toString())
            args.add((dayStart + 24 * 60 * 60 * 1000L).toString())
        }
        if (!statusFilter.isNullOrBlank() && statusFilter != "all") {
            where.append(
                " AND EXISTS (SELECT 1 FROM outbox o WHERE o.missed_call_id = mc.id AND o.status = ?)"
            )
            args.add(statusFilter)
        }
        if (!channelFilter.isNullOrBlank() && channelFilter != "all") {
            where.append(
                " AND EXISTS (SELECT 1 FROM outbox o WHERE o.missed_call_id = mc.id AND o.channel = ?)"
            )
            args.add(channelFilter)
        }

        val out = JSONArray()
        Db.get(context).readableDatabase.rawQuery(
            """
            SELECT mc.*,
                   (SELECT COUNT(*) FROM outbox o WHERE o.missed_call_id = mc.id) AS message_count,
                   (SELECT COUNT(*) FROM outbox o WHERE o.missed_call_id = mc.id AND o.status = '${Db.STATUS_FAILED}') AS failed_count,
                   (SELECT GROUP_CONCAT(DISTINCT o.channel) FROM outbox o WHERE o.missed_call_id = mc.id) AS channels
            FROM missed_calls mc
            WHERE $where
            ORDER BY mc.occurred_at DESC
            LIMIT ? OFFSET ?
            """.trimIndent(),
            (args + listOf(limit.toString(), offset.toString())).toTypedArray(),
        ).use { c ->
            while (c.moveToNext()) {
                out.put(
                    JSONObject()
                        .put("id", c.long("id"))
                        .putOrNull("e164", c.strOrNull("e164"))
                        .put("display", c.strOrNull("contact_name")
                            ?: PhoneNumbers.pretty(c.strOrNull("e164")))
                        .putOrNull("contactName", c.strOrNull("contact_name"))
                        .put("occurredAt", c.long("occurred_at"))
                        .putOrNull("attemptIndex", c.intOrNull("attempt_index"))
                        .put("state", c.str("state"))
                        .putOrNull("cancelReason", c.strOrNull("cancel_reason"))
                        .putOrNull("ruleName", c.strOrNull("rule_name"))
                        .put("messageCount", c.int("message_count"))
                        .put("failedCount", c.int("failed_count"))
                        .putOrNull("channels", c.strOrNull("channels"))
                )
            }
        }
        return out
    }

    private fun logEntry(callId: Long): JSONObject {
        val db = Db.get(context).readableDatabase
        val entry = db.rawQuery("SELECT * FROM missed_calls WHERE id = ?", arrayOf(callId.toString()))
            .use { c ->
                if (!c.moveToFirst()) return JSONObject()
                JSONObject()
                    .put("id", c.long("id"))
                    .putOrNull("e164", c.strOrNull("e164"))
                    .putOrNull("rawNumber", c.strOrNull("number"))
                    .put("display", c.strOrNull("contact_name")
                        ?: PhoneNumbers.pretty(c.strOrNull("e164")))
                    .putOrNull("contactName", c.strOrNull("contact_name"))
                    .put("prettyNumber", PhoneNumbers.pretty(c.strOrNull("e164")))
                    .put("occurredAt", c.long("occurred_at"))
                    .putOrNull("attemptIndex", c.intOrNull("attempt_index"))
                    .put("state", c.str("state"))
                    .putOrNull("cancelReason", c.strOrNull("cancel_reason"))
                    .putOrNull("ruleName", c.strOrNull("rule_name"))
                    .putOrNull("ruleId", c.intOrNull("rule_id"))
                    .putOrNull("dispatchedAt", c.longOrNull("dispatched_at"))
            }

        val messages = JSONArray()
        db.rawQuery(
            "SELECT * FROM outbox WHERE missed_call_id = ? ORDER BY message_index ASC, id ASC",
            arrayOf(callId.toString()),
        ).use { c ->
            while (c.moveToNext()) {
                messages.put(
                    JSONObject()
                        .put("id", c.long("id"))
                        .put("channel", c.str("channel"))
                        .put("body", c.str("body"))
                        .put("status", c.str("status"))
                        .putOrNull("error", c.strOrNull("error"))
                        .put("scheduledAt", c.long("scheduled_at"))
                        .putOrNull("sentAt", c.longOrNull("sent_at"))
                        .putOrNull("deliveredAt", c.longOrNull("delivered_at"))
                )
            }
        }
        return entry.put("messages", messages)
    }

    private fun numberList(): JSONArray {
        val out = JSONArray()
        Db.get(context).readableDatabase
            .rawQuery("SELECT * FROM number_list ORDER BY id DESC", null)
            .use { c ->
                while (c.moveToNext()) {
                    out.put(
                        JSONObject()
                            .put("id", c.long("id"))
                            .put("e164", c.str("e164"))
                            .put("pretty", PhoneNumbers.pretty(c.str("e164")))
                            .putOrNull("note", c.strOrNull("note"))
                    )
                }
            }
        return out
    }

    private fun testSend(channel: String, toE164: String, text: String) {
        when (channel) {
            Db.CHANNEL_SMS -> {
                val outboxId = Db.get(context).writableDatabase.insert("outbox", null,
                    ContentValues().apply {
                        put("channel", Db.CHANNEL_SMS)
                        put("to_e164", toE164)
                        put("body", text)
                        put("status", Db.STATUS_PENDING)
                        put("scheduled_at", System.currentTimeMillis())
                    })
                SmsSender.send(context, outboxId, toE164, text)
            }
            else -> {
                val mode = Settings.str(context, Settings.WHATSAPP_MODE, Settings.WA_MODE_BRIDGE)
                if (mode == Settings.WA_MODE_DEVICE) {
                    WhatsAppAutomationService.send(context, toE164, text)
                } else {
                    BridgeClient.sendWhatsApp(context, toE164, text)
                }
            }
        }
    }

    private fun openSystemPage(key: String) {
        val intent = when (key) {
            "battery" -> DeviceSetup.batteryOptimizationIntent(context)
            "exact_alarms" -> DeviceSetup.exactAlarmIntent(context)
                ?: DeviceSetup.appSettingsIntent(context)
            "autostart" -> DeviceSetup.autostartIntent(context)
            "battery_saver" -> DeviceSetup.batterySaverIntent(context)
            "accessibility" -> WhatsAppAutomationService.settingsIntent()
            else -> DeviceSetup.appSettingsIntent(context)
        }
        (activity() ?: context).startActivity(intent)
    }

    // ---- plumbing -----------------------------------------------------------------

    /** Runs on the calling (main) thread; for cheap database work. */
    private fun reply(result: MethodChannel.Result, block: () -> JSONObject) {
        try {
            result.success(block().toString())
        } catch (e: Exception) {
            Log.w(TAG, "channel call failed", e)
            result.error(errorCode(e), e.message ?: e.javaClass.simpleName, null)
        }
    }

    /** Runs off the main thread; for anything that touches the network. */
    private fun replyAsync(result: MethodChannel.Result, block: () -> JSONObject) {
        io.execute {
            try {
                val value = block().toString()
                main.post { result.success(value) }
            } catch (e: Exception) {
                Log.w(TAG, "async channel call failed", e)
                main.post { result.error(errorCode(e), e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun errorCode(e: Exception): String = when (e) {
        is BridgeClient.BridgeError -> e.code
        is SmsSender.SmsFailure -> "sms_failed"
        is IllegalArgumentException -> "invalid_input"
        is IllegalStateException -> "invalid_state"
        else -> "native_error"
    }

    companion object {
        private const val TAG = "NativeApi"
        const val CHANNEL = "cc.ubermensch.ctm/native"
    }
}
