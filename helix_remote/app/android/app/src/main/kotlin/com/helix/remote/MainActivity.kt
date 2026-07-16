package com.helix.remote

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.helix.remote/calls"
        ).setMethodCallHandler { call, result ->
            if (call.method != "setCallActive") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val active = call.argument<Boolean>("active") ?: false
            val keepScreenOn = call.argument<Boolean>("keepScreenOn") ?: false
            runOnUiThread {
                if (active) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                    window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
                    if (keepScreenOn) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                    window.clearFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
            result.success(null)
        }
    }
}
