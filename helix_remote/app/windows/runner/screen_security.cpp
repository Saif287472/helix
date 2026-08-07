#include "screen_security.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// Win32 exposes two protection levels and they are not interchangeable.
//
// WDA_EXCLUDEFROMCAPTURE (Windows 10 2004 / build 19041 and later) removes the
// window from the capture stream entirely: a recorder sees whatever is behind
// it, and the window stays normal on the physical screen. WDA_MONITOR is the
// older, blunter control — the window renders as a black rectangle to the
// capturer. Both stop the leak; only the first is invisible to the user.
//
// The SDK headers that ship with older toolchains may not define
// WDA_EXCLUDEFROMCAPTURE, so it is spelled out rather than assumed.
constexpr DWORD kExcludeFromCapture = 0x00000011;
constexpr DWORD kMonitorOnly = 0x00000001;
constexpr DWORD kAffinityNone = 0x00000000;

// Returns true when the window is protected at some level.
//
// The fallback matters: SetWindowDisplayAffinity rejects
// WDA_EXCLUDEFROMCAPTURE outright on pre-2004 Windows 10 rather than
// degrading, so a build that only ever asks for the new value silently leaves
// older machines unprotected — the exact failure mode this work exists to
// close.
bool ApplyAffinity(HWND window, bool secure) {
  if (window == nullptr) {
    return false;
  }
  if (!secure) {
    return SetWindowDisplayAffinity(window, kAffinityNone) != FALSE;
  }
  if (SetWindowDisplayAffinity(window, kExcludeFromCapture) != FALSE) {
    return true;
  }
  return SetWindowDisplayAffinity(window, kMonitorOnly) != FALSE;
}

}  // namespace

void RegisterScreenSecurityChannel(flutter::FlutterEngine* engine,
                                   HWND window) {
  if (engine == nullptr) {
    return;
  }

  // Owned by the lambda below, which the channel keeps alive for the life of
  // the engine. The window handle outlives the engine — FlutterWindow tears
  // the controller down in OnDestroy, before the HWND goes away.
  auto channel = std::make_shared<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(),
      "com.helix.remote/screen_security",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [channel, window](const flutter::MethodCall<EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<EncodableValue>>
                            result) {
        if (call.method_name() != "setSecure") {
          result->NotImplemented();
          return;
        }

        // Default to protecting rather than exposing: a malformed argument
        // should not be the reason a conversation becomes recordable.
        bool secure = true;
        if (const auto* arguments = std::get_if<EncodableMap>(call.arguments())) {
          const auto it = arguments->find(EncodableValue("secure"));
          if (it != arguments->end()) {
            if (const auto* value = std::get_if<bool>(&it->second)) {
              secure = *value;
            }
          }
        }

        if (!ApplyAffinity(window, secure)) {
          result->Error(
              "screen_security_unavailable",
              "SetWindowDisplayAffinity failed with " +
                  std::to_string(GetLastError()));
          return;
        }
        result->Success();
      });
}
