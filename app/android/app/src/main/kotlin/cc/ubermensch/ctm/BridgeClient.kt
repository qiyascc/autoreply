package cc.ubermensch.ctm

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Talks to the Baileys bridge. Deliberately built on HttpURLConnection: this code runs
 * from a broadcast receiver on a phone that may have just woken from Doze, and the fewer
 * moving parts between the alarm and the message, the better.
 *
 * Every call is blocking and must be made off the main thread.
 */
object BridgeClient {

    private const val TAG = "BridgeClient"
    private const val CONNECT_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 30_000

    class BridgeError(message: String, val code: String, val retriable: Boolean) : Exception(message)

    data class Registration(val deviceId: String, val token: String)
    data class SessionHandle(val sessionId: String, val linkUrl: String, val expiresAt: Long)

    private fun baseUrl(context: Context): String =
        Settings.str(context, Settings.BRIDGE_URL, "https://ctm.ubermensch.cc").trimEnd('/')

    private fun token(context: Context): String? =
        Settings.str(context, Settings.BRIDGE_TOKEN, "").takeIf { it.isNotBlank() }

    fun isLinked(context: Context): Boolean =
        token(context) != null &&
            Settings.str(context, Settings.BRIDGE_SESSION_ID, "").isNotBlank()

    // ---- device + session lifecycle -----------------------------------------------

    fun registerDevice(context: Context, inviteCode: String, name: String): Registration {
        val body = JSONObject().put("inviteCode", inviteCode).put("name", name)
        val json = request(context, "POST", "/v1/devices", body, authenticated = false)
        val registration = Registration(json.getString("deviceId"), json.getString("token"))
        Db.get(context).apply {
            setSetting(Settings.BRIDGE_DEVICE_ID, registration.deviceId)
            setSetting(Settings.BRIDGE_TOKEN, registration.token)
        }
        return registration
    }

    fun createSession(context: Context, phone: String): SessionHandle {
        val json = request(context, "POST", "/v1/sessions", JSONObject().put("phone", phone))
        val handle = SessionHandle(
            sessionId = json.getString("sessionId"),
            linkUrl = json.getString("linkUrl"),
            expiresAt = json.optLong("expiresAt", 0L),
        )
        Db.get(context).setSetting(Settings.BRIDGE_SESSION_ID, handle.sessionId)
        return handle
    }

    fun sessionStatus(context: Context, sessionId: String): JSONObject =
        request(context, "GET", "/v1/sessions/$sessionId", null)

    fun requestPairingCode(context: Context, sessionId: String): String? {
        val json = request(context, "POST", "/v1/sessions/$sessionId/pairing-code", null)
        return if (json.isNull("code")) null else json.getString("code")
    }

    fun logout(context: Context) {
        val sessionId = Settings.str(context, Settings.BRIDGE_SESSION_ID, "")
        if (sessionId.isNotBlank()) {
            runCatching { request(context, "POST", "/v1/sessions/$sessionId/logout", null) }
        }
        Db.get(context).setSetting(Settings.BRIDGE_SESSION_ID, "")
    }

    fun stats(context: Context): JSONObject = request(context, "GET", "/v1/stats", null)

    // ---- the one that matters ------------------------------------------------------

    /** Sends a WhatsApp message. Throws [BridgeError] with a reason the UI can show. */
    fun sendWhatsApp(context: Context, toE164: String, text: String): String? {
        val body = JSONObject().put("to", toE164).put("text", text)
        val json = request(context, "POST", "/v1/send", body)
        return if (json.isNull("messageId")) null else json.optString("messageId")
    }

    // ---- transport -----------------------------------------------------------------

    private fun request(
        context: Context,
        method: String,
        path: String,
        body: JSONObject?,
        authenticated: Boolean = true,
    ): JSONObject {
        val url = URL(baseUrl(context) + path)
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            setRequestProperty("Accept", "application/json")
            if (authenticated) {
                val bearer = token(context)
                    ?: throw BridgeError("This phone is not registered with the bridge", "no_token", false)
                setRequestProperty("Authorization", "Bearer $bearer")
            }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
            }
        }

        try {
            body?.let { conn.outputStream.use { out -> out.write(it.toString().toByteArray()) } }

            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader()?.use(BufferedReader::readText).orEmpty()

            if (status in 200..299) {
                return if (text.isBlank()) JSONObject() else JSONObject(text)
            }

            val parsed = runCatching { JSONObject(text) }.getOrNull()
            val code = parsed?.optString("error").orEmpty().ifBlank { "http_$status" }
            val message = parsed?.optString("message").orEmpty().ifBlank { describe(code, status) }
            // 5xx and connection-level problems are worth retrying; a rejected number is not.
            throw BridgeError(message, code, retriable = status >= 500 || status == 429)
        } catch (e: BridgeError) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "bridge request failed: $method $path", e)
            throw BridgeError(
                e.message ?: "could not reach the bridge",
                "unreachable",
                retriable = true,
            )
        } finally {
            conn.disconnect()
        }
    }

    private fun describe(code: String, status: Int): String = when (code) {
        "not_linked" -> "WhatsApp is not linked yet"
        "not_connected" -> "the bridge is not connected to WhatsApp"
        "not_on_whatsapp" -> "that number is not on WhatsApp"
        "timeout" -> "WhatsApp did not respond in time"
        "invalid_token" -> "this phone is no longer authorised"
        else -> "bridge returned HTTP $status"
    }
}
