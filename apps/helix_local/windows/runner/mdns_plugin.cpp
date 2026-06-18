// windows/runner/mdns_plugin.cpp
//
// WinRT DNS-SD implementation for Helix mDNS discovery.
//
// Uses Windows.Networking.ServiceDiscovery.Dnssd (Win10 RS1 / SDK 14393+).
// Falls back gracefully if the namespace is unavailable (older SDK / Wine).
#include "mdns_plugin.h"

// Suppress min/max macros from windows.h so they don't collide with <algorithm>
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

// C++/WinRT headers — require /std:c++17 and the Windows SDK ≥ 14393.
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Networking.h>
#include <winrt/Windows.Networking.ServiceDiscovery.Dnssd.h>

#include <flutter/encodable_value.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <mutex>
#include <string>
#include <vector>

namespace wf  = winrt::Windows::Foundation;
namespace wfc = winrt::Windows::Foundation::Collections;
namespace wnd = winrt::Windows::Networking;
namespace dsd = winrt::Windows::Networking::ServiceDiscovery::Dnssd;

// ── Helpers ──────────────────────────────────────────────────────────────────

static std::string GetMapString(const flutter::EncodableMap& m, const std::string& key) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return {};
    if (auto* s = std::get_if<std::string>(&it->second)) return *s;
    return {};
}

static bool GetMapBool(const flutter::EncodableMap& m, const std::string& key) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return false;
    if (auto* b = std::get_if<bool>(&it->second)) return *b;
    return false;
}

// ── Impl (WinRT state) ───────────────────────────────────────────────────────

struct HelixMdnsPlugin::Impl {
    dsd::DnssdServiceInstance           registration{ nullptr };
    dsd::DnssdServiceWatcher            watcher{ nullptr };
    winrt::event_token                  addedToken{};
    winrt::event_token                  removedToken{};
    winrt::event_token                  completedToken{};

    std::string localSessionId;
    std::mutex  sinkMutex;
    flutter::EventSink<flutter::EncodableValue>* sink = nullptr;  // raw — owned by plugin

    void SendDiscoveredEvent(flutter::EncodableMap event) {
        std::lock_guard<std::mutex> lock(sinkMutex);
        if (sink) sink->Success(flutter::EncodableValue(std::move(event)));
    }
};

// ── Plugin registration ──────────────────────────────────────────────────────

// static
std::unique_ptr<HelixMdnsPlugin> HelixMdnsPlugin::Create(
    flutter::BinaryMessenger* messenger) {
    auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        "com.helix.app/mdns",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<HelixMdnsPlugin>(
        messenger, std::move(method_channel));

    // Set up the event channel.
    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger,
        "com.helix.app/mdns/events",
        &flutter::StandardMethodCodec::GetInstance());

    auto* plugin_ptr = plugin.get();
    auto handler = std::make_unique<
        flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [plugin_ptr](const flutter::EncodableValue* /*args*/,
                     std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(plugin_ptr->impl_->sinkMutex);
            plugin_ptr->event_sink_ = std::move(sink);
            plugin_ptr->impl_->sink = plugin_ptr->event_sink_.get();
            return nullptr;
        },
        [plugin_ptr](const flutter::EncodableValue* /*args*/)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(plugin_ptr->impl_->sinkMutex);
            plugin_ptr->impl_->sink = nullptr;
            plugin_ptr->event_sink_.reset();
            return nullptr;
        });

    event_channel->SetStreamHandler(std::move(handler));
    plugin->event_channel_ = std::move(event_channel);

    return plugin;
}

// ── Constructor / Destructor ─────────────────────────────────────────────────

HelixMdnsPlugin::HelixMdnsPlugin(
    flutter::BinaryMessenger* messenger,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel)
    : messenger_(messenger),
      method_channel_(std::move(method_channel)),
      impl_(std::make_unique<Impl>()) {

    method_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
            HandleMethodCall(call, std::move(result));
        });
}

HelixMdnsPlugin::~HelixMdnsPlugin() {
    Stop();
}

// ── Method dispatch ──────────────────────────────────────────────────────────

void HelixMdnsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const auto* args_map = std::get_if<flutter::EncodableMap>(call.arguments());
    flutter::EncodableMap empty_map;
    const auto& args = args_map ? *args_map : empty_map;

    if (call.method_name() == "start") {
        Start(args);
        result->Success();
    } else if (call.method_name() == "stop") {
        Stop();
        result->Success();
    } else if (call.method_name() == "updateDiscoverability") {
        UpdateDiscoverability(args);
        result->Success();
    } else {
        result->NotImplemented();
    }
}

// ── Start ────────────────────────────────────────────────────────────────────

void HelixMdnsPlugin::Start(const flutter::EncodableMap& args) {
    impl_->localSessionId = GetMapString(args, "sessionId");
    // DNS-SD advertisement skipped on Windows: RegisterStreamSocketListenerAsync
    // requires a non-null StreamSocketListener or it raises an SEH exception that
    // bypasses C++ catch(...) and kills the process.  Peer discovery uses UDP
    // broadcast exclusively on Windows, so no WinRT mDNS registration is needed.
}

// ── Stop ─────────────────────────────────────────────────────────────────────

void HelixMdnsPlugin::Stop() {
    try {
        if (impl_->watcher) {
            impl_->watcher.Added(impl_->addedToken);
            impl_->watcher.Stop();
            impl_->watcher = nullptr;
        }
        impl_->registration = nullptr;
    } catch (...) {}
}

// ── UpdateDiscoverability ────────────────────────────────────────────────────

void HelixMdnsPlugin::UpdateDiscoverability(const flutter::EncodableMap& args) {
    const bool discoverable = GetMapBool(args, "discoverable");
    if (!discoverable) {
        // Unregister — keep browsing
        impl_->registration = nullptr;
    }
    // Re-registering on toggle-on requires re-calling Start; callers should
    // stop+start if they need to re-advertise with updated params.
}
