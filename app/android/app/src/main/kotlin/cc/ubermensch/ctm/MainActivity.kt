package cc.ubermensch.ctm

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pendingRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notifications.ensureChannels(this)
        // Opening the app is a good moment to repair anything the OS killed while away.
        AlarmScheduler.rescheduleAll(this)
        if (Settings.bool(this, Settings.MASTER_ENABLED, true)) {
            WatchdogService.ensureRunning(this)
        }
        pendingRoute = intent?.getStringExtra(EXTRA_ROUTE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra(EXTRA_ROUTE) ?: return
        // The engine is already up if we got here from a notification tap while running.
        channel?.invokeMethod("navigate", route) ?: run { pendingRoute = route }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val api = NativeApi(applicationContext) { this }
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeApi.CHANNEL,
        )
        channel = methodChannel

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Consumed once: the route a notification asked us to open.
                "takeInitialRoute" -> {
                    result.success(pendingRoute)
                    pendingRoute = null
                }
                else -> api.handle(call, result)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        // Let the wizard re-read the checklist rather than trusting the callback's shape.
        channel?.invokeMethod("permissionsChanged", null)
    }

    override fun onResume() {
        super.onResume()
        // Returning from a system settings page: the checklist may look different now.
        channel?.invokeMethod("permissionsChanged", null)
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_ROUTE = "route"
        const val PERMISSION_REQUEST_CODE = 4201
    }
}
