import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_engine/src/account/device_service.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Encrypts one content message for every device of its audience and posts
/// it (`POST /v1/messages`), the part of the outbound pipeline (plan §6.3)
/// that runs at send time:
///
/// 1. **Plan.** For each account of the audience: its devices from the cache
///    (this account: its other devices; a peer never seen: a full key
///    fetch).
/// 2. **Sessions.** Bundles are fetched only for devices without a session
///    that can send, and a session is started for each.
/// 3. **Encrypt and commit.** One ciphertext per device; the new ratchet
///    states are committed before anything is sent.
/// 4. **Send.** With the request id as idempotency key. On
///    `device_list_stale` the lists are rebuilt (devices added, gone ones
///    dropped) and the whole thing is planned again.
final class MessageSender {
  MessageSender(this._ctx, this._peers, this._crypto, this._devices);

  final EngineContext _ctx;
  final PeerDirectory _peers;
  final PairwiseCrypto _crypto;
  final DeviceService _devices;

  /// Sends [content] (already encoded) to every device of every account in
  /// [accounts]; this account's own other devices are included when it is
  /// listed. Throws what the API throws (the caller classifies), plus
  /// [UntrustedPeerException] when a recipient's keys do not verify or it
  /// has no devices.
  Future<SendMessageResponse> send({
    required String requestId,
    required Uint8List content,
    required Iterable<String> accounts,
    bool ephemeral = false,
    bool urgent = true,
  }) async {
    final response = await sendSealed<SendMessageResponse>(
      content: content,
      accounts: accounts,
      post: (recipients) => _ctx.api.messaging.send(
        SendMessageRequest(
          id: requestId,
          urgent: urgent,
          ephemeral: ephemeral,
          recipients: recipients,
        ),
      ),
    );
    // Nobody to send to (an account with no other devices).
    return response ?? SendMessageResponse(acceptedAt: _ctx.now());
  }

  /// The plan, encrypt-and-commit and stale-list loop behind [send], for any
  /// route that takes per-device sealed payloads (call signals use it too).
  /// [post] receives the recipients and makes the request; its result is
  /// returned, or null when there was nobody to send to. With [onlyDevices]
  /// each listed account's audience shrinks to those of its devices (a call
  /// answer goes to the one device that offered); an account's devices not
  /// yet known are fetched first.
  Future<T?> sendSealed<T>({
    required Uint8List content,
    required Iterable<String> accounts,
    required Future<T> Function(List<Recipient> recipients) post,
    Set<String>? onlyDevices,
  }) async {
    final audience = accounts.toSet().toList()..sort();
    var attempts = _ctx.config.staleListRetries + 1;
    // Fetching a bundle takes a one-time prekey from the recipient, so a
    // bundle fetched while planning is kept for starting the session.
    final fetched = <DeviceAddress, VerifiedPrekeyBundle>{};
    while (true) {
      final plan = await _plan(audience, fetched, only: onlyDevices);
      if (plan.isEmpty) return null;
      final devices = [for (final list in plan.values) ...list];
      final bundles = await _bundlesFor(
        await _crypto.withoutSession(devices),
        fetched,
      );
      final unavailable = [
        for (final d in await _crypto.withoutSession(devices))
          if (!bundles.containsKey(d)) d,
      ];
      if (unavailable.isNotEmpty) {
        // The server no longer knows these devices: forget them and plan
        // again.
        for (final d in unavailable) {
          await _peers.dropDevice(d.account, d.device);
        }
        if (--attempts <= 0) {
          throw const UntrustedPeerException('recipient devices are gone');
        }
        continue;
      }
      final payloads = await _crypto.encryptFor(
        devices,
        content,
        bundles: bundles,
      );
      final recipients = [
        for (final entry in plan.entries)
          Recipient(
            account: entry.key,
            devices: [
              for (final d in entry.value)
                DevicePayload(device: d.device, payload: payloads[d]!),
            ],
          ),
      ];
      try {
        return await post(recipients);
      } on ApiException catch (e) {
        final stale = e.staleDevices;
        if (stale == null || --attempts <= 0) rethrow;
        await _applyStale(stale, fetched);
      }
    }
  }

  /// True if every known device of [account] has a session this device can
  /// send on, so an ephemeral signal (typing) needs no key fetch.
  Future<bool> readyWithoutSetup(String account) async {
    final plan = await _knownPlan(account);
    if (plan == null || plan.isEmpty) return false;
    return (await _crypto.withoutSession(plan)).isEmpty;
  }

  Future<List<DeviceAddress>?> _knownPlan(String account) async {
    final self = _ctx.identity;
    final rows = await _peers.devicesOf(account);
    final devices = [
      for (final row in rows)
        if (!(account == self.accountId && row.deviceId == self.deviceId))
          DeviceAddress(account, row.deviceId),
    ];
    return rows.isEmpty ? null : devices;
  }

  Future<Map<String, List<DeviceAddress>>> _plan(
    List<String> accounts,
    Map<DeviceAddress, VerifiedPrekeyBundle> fetched, {
    Set<String>? only,
  }) async {
    final self = _ctx.identity;
    final plan = <String, List<DeviceAddress>>{};
    for (final account in accounts) {
      if (account == self.accountId) {
        final others = await _devices.otherDeviceIds();
        final known = {
          for (final row in await _peers.devicesOf(account)) row.deviceId,
        };
        final missing = others.difference(known);
        if (missing.isNotEmpty) {
          _keep(fetched, await _peers.fetch(account, devices: missing));
        }
        for (final extra in known.difference(others)) {
          if (extra != self.deviceId) await _peers.dropDevice(account, extra);
        }
        if (others.isNotEmpty) {
          plan[account] = [for (final id in others) DeviceAddress(account, id)];
        }
        continue;
      }
      var rows = await _peers.devicesOf(account);
      if (only != null) {
        final missing = only.difference({for (final r in rows) r.deviceId});
        if (missing.isNotEmpty) {
          _keep(fetched, await _peers.fetch(account, devices: missing));
          rows = await _peers.devicesOf(account);
        }
        rows = [
          for (final r in rows)
            if (only.contains(r.deviceId)) r,
        ];
      } else if (rows.isEmpty) {
        _keep(fetched, await _peers.fetch(account));
        rows = await _peers.devicesOf(account);
      }
      if (rows.isEmpty) {
        throw const UntrustedPeerException('the recipient has no devices');
      }
      plan[account] = [
        for (final row in rows) DeviceAddress(account, row.deviceId),
      ];
    }
    return plan;
  }

  void _keep(Map<DeviceAddress, VerifiedPrekeyBundle> cache, FetchedKeys keys) {
    for (final bundle in keys.bundles) {
      cache[bundle.identity.address] = bundle;
    }
  }

  /// The bundles needed to start sessions with [devices]: from [fetched]
  /// where this send already has them, else fetched now.
  Future<Map<DeviceAddress, VerifiedPrekeyBundle>> _bundlesFor(
    List<DeviceAddress> devices,
    Map<DeviceAddress, VerifiedPrekeyBundle> fetched,
  ) async {
    final out = <DeviceAddress, VerifiedPrekeyBundle>{};
    final byAccount = <String, List<String>>{};
    for (final d in devices) {
      final have = fetched[d];
      if (have != null) {
        out[d] = have;
      } else {
        (byAccount[d.account] ??= []).add(d.device);
      }
    }
    for (final entry in byAccount.entries) {
      final keys = await _peers.fetch(entry.key, devices: entry.value);
      _keep(fetched, keys);
      for (final bundle in keys.bundles) {
        out[bundle.identity.address] = bundle;
      }
    }
    return out;
  }

  /// Rebuilds the device lists the server called stale: gone devices are
  /// forgotten, new ones fetched (their sessions start on the next plan).
  Future<void> _applyStale(
    StaleDevices stale,
    Map<DeviceAddress, VerifiedPrekeyBundle> fetched,
  ) async {
    final self = _ctx.identity;
    for (final account in stale.accounts) {
      for (final extra in account.extra) {
        await _peers.dropDevice(account.account, extra);
      }
      if (account.account == self.accountId) {
        await _devices.refresh();
      } else if (account.missing.isNotEmpty) {
        _keep(
          fetched,
          await _peers.fetch(account.account, devices: account.missing),
        );
      }
    }
  }
}
