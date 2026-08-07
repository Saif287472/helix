package com.helix.remote

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun getInitialRoute(): String? {
        return intent?.dataString ?: super.getInitialRoute()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // FLAG_SECURE. Set while a screen showing message content, backup key
        // material, or a verification QR is in front. It blocks screenshots
        // and screen recording, and - the part that matters most - blanks the
        // entry in the recents/task-switcher, which otherwise keeps the last
        // rendered conversation in plaintext for anyone who picks up the
        // device.
        //
        // Driven per screen rather than set once for the whole app so that
        // ordinary screens (settings, onboarding, diagnostics) stay
        // screenshot-able, which is what support and bug reports need.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.helix.remote/screen_security"
        ).setMethodCallHandler { call, result ->
            if (call.method != "setSecure") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val secure = call.argument<Boolean>("secure") ?: false
            runOnUiThread {
                if (secure) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
            }
            result.success(null)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.helix.remote/calls"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setCallActive" -> {
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
                "shouldUseFullScreenIncomingCall" -> {
                    val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(keyguard.isKeyguardLocked || !power.isInteractive)
                }
                "startForegroundCall" -> {
                    val caller = call.argument<String>("callerDisplayName") ?: "Unknown caller"
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    val intent = CallForegroundService.startIntent(this, caller, isVideo)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopForegroundCall" -> {
                    stopService(CallForegroundService.stopIntent(this))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
