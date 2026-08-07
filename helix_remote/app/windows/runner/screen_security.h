#ifndef RUNNER_SCREEN_SECURITY_H_
#define RUNNER_SCREEN_SECURITY_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// Installs the `com.helix.remote/screen_security` method-channel handler on
// |engine|, applying capture protection to |window|.
//
// This is the Windows half of the FLAG_SECURE work. The Dart side
// (`app/lib/services/screen_security.dart`) reference-counts sensitive screens
// and calls `setSecure` on the same channel name the Android activity serves,
// so the two platforms are one protocol with two implementations.
void RegisterScreenSecurityChannel(flutter::FlutterEngine* engine, HWND window);

#endif  // RUNNER_SCREEN_SECURITY_H_
