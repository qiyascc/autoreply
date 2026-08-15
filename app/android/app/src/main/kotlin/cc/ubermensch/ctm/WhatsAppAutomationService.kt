package cc.ubermensch.ctm

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings as AndroidSettings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Optional on-device delivery: opens the WhatsApp chat with the reply pre-filled and taps
 * Send. Off by default and deliberately so — it puts WhatsApp on screen and needs the phone
 * unlocked, which is exactly what the server bridge exists to avoid. It is here for the case
 * where the bridge is not wanted at all.
 */
class WhatsAppAutomationService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
        Log.i(TAG, "accessibility service connected")
    }

    override fun onDestroy() {
        connected = false
        super.onDestroy()
    }

    override fun onInterrupt() = Unit

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val request = pending.get() ?: return
        if (event?.packageName?.toString() !in WHATSAPP_PACKAGES) return

        val root = rootInActiveWindow ?: return
        val sendButton = findSendButton(root) ?: return

        if (sendButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            Log.i(TAG, "tapped send")
            pending.set(null)
            request.success = true
            request.latch.countDown()
            // Get out of WhatsApp so the user is not left staring at a chat they did not open.
            postDelayed { performGlobalAction(GLOBAL_ACTION_BACK) }
        }
    }

    /** WhatsApp's send button keeps a stable view id across locales; the text label does not. */
    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        for (id in SEND_VIEW_IDS) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            val clickable = nodes?.firstOrNull { it.isClickable && it.isVisibleToUser }
            if (clickable != null) return clickable
        }
        return null
    }

    private fun postDelayed(block: () -> Unit) {
        android.os.Handler(mainLooper).postDelayed(block, 700)
    }

    companion object {
        private const val TAG = "WhatsAppAutomation"
        private const val SEND_TIMEOUT_SECONDS = 20L

        private val WHATSAPP_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b")
        private val SEND_VIEW_IDS = listOf(
            "com.whatsapp:id/send",
            "com.whatsapp.w4b:id/send",
        )

        @Volatile
        private var connected = false

        private val pending = AtomicReference<Request?>(null)

        private class Request {
            val latch = CountDownLatch(1)
            @Volatile var success = false
        }

        fun isEnabled(context: Context): Boolean {
            val expected = "${context.packageName}/${WhatsAppAutomationService::class.java.name}"
            val enabled = AndroidSettings.Secure.getString(
                context.contentResolver,
                AndroidSettings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ).orEmpty()
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }

        fun isWhatsAppInstalled(context: Context): Boolean = WHATSAPP_PACKAGES.any { pkg ->
            runCatching { context.packageManager.getPackageInfo(pkg, 0) }.isSuccess
        }

        /** Blocking; throws with a readable reason so the failure notification can quote it. */
        fun send(context: Context, toE164: String, body: String) {
            if (!isWhatsAppInstalled(context)) {
                throw IllegalStateException("WhatsApp is not installed on this phone")
            }
            if (!isEnabled(context)) {
                throw IllegalStateException("on-device WhatsApp delivery needs the accessibility service enabled")
            }

            val request = Request()
            pending.set(request)

            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(
                    "https://api.whatsapp.com/send?phone=$toE164&text=${Uri.encode(body)}"
                )
                setPackage("com.whatsapp")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            try {
                context.startActivity(intent)
            } catch (e: Exception) {
                pending.set(null)
                throw IllegalStateException("could not open WhatsApp: ${e.message}")
            }

            val completed = request.latch.await(SEND_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            pending.set(null)

            if (!completed || !request.success) {
                throw IllegalStateException(
                    "WhatsApp did not accept the message — the screen may have been locked"
                )
            }
        }

        /** Deep link to the system page where the service is switched on. */
        fun settingsIntent(): Intent =
            Intent(AndroidSettings.ACTION_ACCESSIBILITY_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
