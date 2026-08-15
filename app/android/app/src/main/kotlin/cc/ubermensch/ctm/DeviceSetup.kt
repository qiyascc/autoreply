package cc.ubermensch.ctm

import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings as AndroidSettings
import org.json.JSONArray
import org.json.JSONObject

/**
 * Runtime permissions plus the vendor settings that decide whether any of this actually
 * runs. On Xiaomi's MIUI/HyperOS — the target phone here is a Poco M4 Pro 5G — granting
 * permissions is not enough: without Autostart and an unrestricted battery policy the OS
 * kills the process between the ring and the alarm, and the app looks broken while
 * reporting itself perfectly healthy.
 */
object DeviceSetup {

    val RUNTIME_PERMISSIONS = listOf(
        android.Manifest.permission.READ_PHONE_STATE,
        android.Manifest.permission.READ_CALL_LOG,
        android.Manifest.permission.READ_CONTACTS,
        android.Manifest.permission.SEND_SMS,
        android.Manifest.permission.POST_NOTIFICATIONS,
    )

    private val LABELS = mapOf(
        android.Manifest.permission.READ_PHONE_STATE to "Phone state",
        android.Manifest.permission.READ_CALL_LOG to "Call log",
        android.Manifest.permission.READ_CONTACTS to "Contacts",
        android.Manifest.permission.SEND_SMS to "Send SMS",
        android.Manifest.permission.POST_NOTIFICATIONS to "Notifications",
    )

    private val WHY = mapOf(
        android.Manifest.permission.READ_PHONE_STATE to
            "Detects when a call starts ringing and when it ends.",
        android.Manifest.permission.READ_CALL_LOG to
            "Confirms a call was really missed, reads the caller's number, and cancels the reply if you call back.",
        android.Manifest.permission.READ_CONTACTS to
            "Shows names instead of numbers, and powers the known/unknown caller rules.",
        android.Manifest.permission.SEND_SMS to
            "Sends the text reply silently, without opening the messaging app.",
        android.Manifest.permission.POST_NOTIFICATIONS to
            "Shows the daily summary and warns you when a reply could not be sent.",
    )

    fun isGranted(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun isXiaomi(): Boolean {
        val vendor = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        return listOf("xiaomi", "redmi", "poco").any { vendor.contains(it) }
    }

    fun ignoringBatteryOptimizations(context: Context): Boolean =
        context.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(context.packageName)

    fun canScheduleExactAlarms(context: Context): Boolean {
        val am = context.getSystemService(AlarmManager::class.java)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true
    }

    /** The full checklist the setup wizard walks through, as JSON for the Flutter UI. */
    fun status(context: Context): JSONObject {
        val permissions = JSONArray()
        RUNTIME_PERMISSIONS.forEach { permission ->
            permissions.put(
                JSONObject()
                    .put("permission", permission)
                    .put("label", LABELS[permission] ?: permission)
                    .put("why", WHY[permission] ?: "")
                    .put("granted", isGranted(context, permission))
            )
        }

        return JSONObject()
            .put("permissions", permissions)
            .put("batteryUnrestricted", ignoringBatteryOptimizations(context))
            .put("exactAlarms", canScheduleExactAlarms(context))
            .put("isXiaomi", isXiaomi())
            .put("manufacturer", Build.MANUFACTURER)
            .put("model", Build.MODEL)
            .put("androidVersion", Build.VERSION.RELEASE)
            .put("sdkInt", Build.VERSION.SDK_INT)
            .put("whatsappInstalled", WhatsAppAutomationService.isWhatsAppInstalled(context))
            .put("accessibilityEnabled", WhatsAppAutomationService.isEnabled(context))
            .put("setupComplete", Settings.bool(context, Settings.SETUP_COMPLETE))
    }

    fun batteryOptimizationIntent(context: Context): Intent =
        Intent(AndroidSettings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun exactAlarmIntent(context: Context): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent(AndroidSettings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        } else null

    fun appSettingsIntent(context: Context): Intent =
        Intent(AndroidSettings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * MIUI's autostart screen. The component names have moved between MIUI versions, so
     * every known one is tried before falling back to the generic app-info page.
     */
    fun autostartIntent(context: Context): Intent {
        val candidates = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartDetailManagementActivity",
            ),
        )
        for (component in candidates) {
            val intent = Intent().setComponent(component).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(context.packageManager) != null) return intent
        }
        return appSettingsIntent(context)
    }

    /** MIUI's per-app battery policy ("No restrictions"), which is separate from Doze. */
    fun batterySaverIntent(context: Context): Intent {
        val miui = Intent().setComponent(
            ComponentName(
                "com.miui.powerkeeper",
                "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            )
        ).putExtra("package_name", context.packageName)
            .putExtra("package_label", "Autoreply")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        return if (miui.resolveActivity(context.packageManager) != null) miui
        else batteryOptimizationIntent(context)
    }

    /** Vendor-specific steps the wizard shows, with the intent key that opens each one. */
    fun vendorSteps(context: Context): JSONArray {
        val steps = JSONArray()
        if (!isXiaomi()) return steps

        steps.put(
            JSONObject()
                .put("key", "autostart")
                .put("title", "Turn on Autostart")
                .put(
                    "detail",
                    "MIUI blocks apps from starting themselves after a reboot. Without this, " +
                        "Autoreply stops working the next time you restart your phone."
                )
        )
        steps.put(
            JSONObject()
                .put("key", "battery_saver")
                .put("title", "Set battery saver to No restrictions")
                .put(
                    "detail",
                    "MIUI's own battery policy kills background apps even when Android's is " +
                        "already unrestricted. Choose \"No restrictions\" for Autoreply."
                )
        )
        steps.put(
            JSONObject()
                .put("key", "lock_recents")
                .put("title", "Lock the app in Recents")
                .put(
                    "detail",
                    "Open Recents, swipe down on the Autoreply card and tap the padlock. " +
                        "This stops \"clear all\" from killing the call watcher."
                )
                .put("manualOnly", true)
        )
        return steps
    }
}
