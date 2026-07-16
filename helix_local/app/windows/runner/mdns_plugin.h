// windows/runner/mdns_plugin.h
//
// WinRT DNS-SD plugin for Helix.
// Registers a _helix._tcp service and browses for peers on Windows 10+
// (SDK 14393+) using Windows.Networking.ServiceDiscovery.Dnssd.
//
// Exposed via:
//   MethodChannel  "com.helix.app/mdns"
//   EventChannel   "com.helix.app/mdns/events"
#pragma once

#include <flutter/binary_messenger.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

class HelixMdnsPlugin final {
public:
    static std::unique_ptr<HelixMdnsPlugin> Create(
        flutter::BinaryMessenger* messenger);

    HelixMdnsPlugin(
        flutter::BinaryMessenger* messenger,
        std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel);

    ~HelixMdnsPlugin();

    // Non-copyable
    HelixMdnsPlugin(const HelixMdnsPlugin&) = delete;
    HelixMdnsPlugin& operator=(const HelixMdnsPlugin&) = delete;

private:
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    void Start(const flutter::EncodableMap& args);
    void Stop();
    void UpdateDiscoverability(const flutter::EncodableMap& args);

    flutter::BinaryMessenger* messenger_;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>  event_channel_;

    // Owned event sink — set when Dart calls EventChannel.receiveBroadcastStream().
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

    // WinRT handles stored as void* to avoid pulling WinRT headers into this
    // header (keeping compile units that don't need WinRT fast).
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
