// android/app/src/main/kotlin/com/helix/local/HelixMdnsService.kt
package com.helix.local

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * Wraps Android NsdManager to advertise and browse _helix._tcp services.
 *
 * Driven by the "com.helix.local/mdns" MethodChannel (registered in
 * MainActivity) and sends peer events through the "com.helix.local/mdns/events"
 * EventChannel.
 */
class HelixMdnsService(private val context: Context) {

    private val tag = "HelixMdns"
    private val serviceType = "_helix._tcp."

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    // NsdManager can only have one active resolve at a time; queue extras.
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Local session info used to filter out our own advertisement.
    private var localSessionId = ""

    // Retained so updateDiscoverability(true) can re-register without a full restart.
    private var lastDisplayName = ""
    private var lastDeviceSuffix = ""
    private var lastPort = 0

    // ── EventSink ────────────────────────────────────────────────────────────

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    // ── Start ────────────────────────────────────────────────────────────────

    fun start(args: Map<*, *>) {
        val sessionId   = args["sessionId"]   as? String  ?: return
        val displayName = args["displayName"] as? String  ?: ""
        val deviceSuffix = args["deviceSuffix"] as? String ?: ""
        val port        = args["port"]        as? Int     ?: return
        val discoverable = args["discoverable"] as? Boolean ?: true

        localSessionId  = sessionId
        lastDisplayName = displayName
        lastDeviceSuffix = deviceSuffix
        lastPort        = port
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return

        if (discoverable) registerService(displayName, deviceSuffix, sessionId, port)
        startDiscovery()
    }

    // ── Stop ─────────────────────────────────────────────────────────────────

    fun stop() {
        unregisterService()
        stopDiscovery()
        nsdManager = null
        resolveQueue.clear()
        resolving = false
    }

    // ── Update discoverability ───────────────────────────────────────────────

    fun updateDiscoverability(args: Map<*, *>) {
        val discoverable = args["discoverable"] as? Boolean ?: return
        if (discoverable) {
            // Re-register using the params retained from the last start() call.
            if (localSessionId.isNotEmpty() && lastPort > 0) {
                registerService(lastDisplayName, lastDeviceSuffix, localSessionId, lastPort)
            } else {
                Log.w(tag, "updateDiscoverability(true): no retained params — call start() first")
            }
        } else {
            unregisterService()
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private fun registerService(
        displayName: String,
        deviceSuffix: String,
        sessionId: String,
        port: Int,
    ) {
        val info = NsdServiceInfo().apply {
            serviceName = displayName
            serviceType = this@HelixMdnsService.serviceType
            this.port   = port
            setAttribute("pmaj", "2")
            setAttribute("pmin", "0")
            setAttribute("sid",  sessionId)
            setAttribute("sfx",  deviceSuffix)
            setAttribute("disc", "1")
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo) {
                Log.d(tag, "mDNS registered: ${i.serviceName}")
            }
            override fun onRegistrationFailed(i: NsdServiceInfo, err: Int) {
                Log.w(tag, "mDNS registration failed: $err")
            }
            override fun onServiceUnregistered(i: NsdServiceInfo) {
                Log.d(tag, "mDNS unregistered: ${i.serviceName}")
            }
            override fun onUnregistrationFailed(i: NsdServiceInfo, err: Int) {
                Log.w(tag, "mDNS unregistration failed: $err")
            }
        }
        try {
            nsdManager?.registerService(info, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        } catch (e: Exception) {
            Log.w(tag, "registerService exception: $e")
        }
    }

    private fun unregisterService() {
        val listener = registrationListener ?: return
        registrationListener = null
        try {
            nsdManager?.unregisterService(listener)
        } catch (e: Exception) {
            Log.w(tag, "unregisterService exception: $e")
        }
    }

    private fun startDiscovery() {
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(t: String, err: Int) {
                Log.w(tag, "Discovery start failed: $err")
            }
            override fun onStopDiscoveryFailed(t: String, err: Int) {
                Log.w(tag, "Discovery stop failed: $err")
            }
            override fun onDiscoveryStarted(t: String) {
                Log.d(tag, "mDNS browsing started")
            }
            override fun onDiscoveryStopped(t: String) {
                Log.d(tag, "mDNS browsing stopped")
            }
            override fun onServiceFound(info: NsdServiceInfo) {
                enqueueResolve(info)
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                // PeerRegistry's stale-eviction timer handles cleanup; no action needed.
                Log.d(tag, "mDNS service lost: ${info.serviceName}")
            }
        }
        try {
            nsdManager?.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) {
            Log.w(tag, "discoverServices exception: $e")
        }
    }

    private fun stopDiscovery() {
        val listener = discoveryListener ?: return
        discoveryListener = null
        try {
            nsdManager?.stopServiceDiscovery(listener)
        } catch (e: Exception) {
            Log.w(tag, "stopServiceDiscovery exception: $e")
        }
    }

    private val maxPendingResolves = 32

    private fun enqueueResolve(info: NsdServiceInfo) {
        synchronized(resolveQueue) {
            val name = info.serviceName
            if (name != null) {
                val alreadyQueued = resolveQueue.any { it.serviceName == name }
                if (alreadyQueued) return
            }
            if (resolveQueue.size >= maxPendingResolves) return

            resolveQueue.addLast(info)
            if (!resolving) resolveNext()
        }
    }

    private fun resolveNext() {
        synchronized(resolveQueue) {
            val next = resolveQueue.removeFirstOrNull()
            if (next == null) { resolving = false; return }
            resolving = true
            try {
                nsdManager?.resolveService(next, makeResolveListener())
            } catch (e: Exception) {
                Log.w(tag, "resolveService exception: $e")
                resolveNext()
            }
        }
    }

    private fun makeResolveListener() = object : NsdManager.ResolveListener {
        override fun onResolveFailed(info: NsdServiceInfo, err: Int) {
            Log.w(tag, "Resolve failed for ${info.serviceName}: $err")
            resolveNext()
        }

        override fun onServiceResolved(info: NsdServiceInfo) {
            val attrs = try {
                @Suppress("UNCHECKED_CAST")
                info.attributes as? Map<String, ByteArray> ?: emptyMap()
            } catch (_: Exception) { emptyMap<String, ByteArray>() }

            fun txt(k: String) = attrs[k]?.toString(Charsets.UTF_8) ?: ""

            val peerSid  = txt("sid")
            val peerSfx  = txt("sfx")
            val disc     = txt("disc")
            val pmaj     = txt("pmaj").toIntOrNull() ?: 2
            val pmin     = txt("pmin").toIntOrNull() ?: 0
            val host     = info.host?.hostAddress

            // Skip non-discoverable peers and our own advertisement.
            if (disc == "0" || peerSid == localSessionId || host == null) {
                resolveNext()
                return
            }

            val event = mapOf(
                "type"         to "discovered",
                "sessionId"    to peerSid,
                "displayName"  to (info.serviceName ?: ""),
                "deviceSuffix" to peerSfx,
                "host"         to host,
                "port"         to info.port,
                "pmaj"         to pmaj,
                "pmin"         to pmin,
            )
            emitEvent(event)
            Log.d(tag, "mDNS resolved: ${info.serviceName} @ $host:${info.port}")
            resolveNext()
        }
    }

    private fun emitEvent(event: Map<String, Any>) {
        mainHandler.post {
            try {
                eventSink?.success(event)
            } catch (e: Exception) {
                Log.w(tag, "eventSink success failed: $e")
            }
        }
    }
}
