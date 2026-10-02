import 'package:helix_remote_crypto/v2.dart' show PrekeyPolicy;
import 'package:helix_remote_engine/src/util/backoff.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:meta/meta.dart';

/// Tunables of an [Engine]. Defaults are the product values; tests shorten
/// them.
@immutable
final class EngineConfig {
  const EngineConfig({
    this.deviceName = 'Helix device',
    this.platform = DevicePlatform.other,
    this.outboxBackoff = const Backoff(),
    this.outboxMaxAge = const Duration(days: 3),
    this.outboxLease = const Duration(minutes: 2),
    this.staleListRetries = 3,
    this.resendWindow = const Duration(hours: 24),
    this.resetCooldown = const Duration(minutes: 10),
    this.maintenanceInterval = const Duration(minutes: 5),
    this.prekeyCheckInterval = const Duration(hours: 6),
    this.processedRetention = const Duration(days: 8),
    this.typingExpiry = const Duration(seconds: 7),
    this.typingSendInterval = const Duration(seconds: 4),
    this.inboundRetry = const Backoff(
      initial: Duration(seconds: 1),
      max: Duration(seconds: 30),
    ),
    this.wipeOnRevocation = true,
    this.maxFetchPages = 20,
    this.initialOneTimePrekeys = PrekeyPolicy.initialOneTimePrekeys,
  });

  /// A copy with the given fields replaced.
  EngineConfig copyWith({
    String? deviceName,
    DevicePlatform? platform,
    Backoff? outboxBackoff,
    Duration? outboxMaxAge,
    Duration? outboxLease,
    int? staleListRetries,
    Duration? resendWindow,
    Duration? resetCooldown,
    Duration? maintenanceInterval,
    Duration? prekeyCheckInterval,
    Duration? processedRetention,
    Duration? typingExpiry,
    Duration? typingSendInterval,
    Backoff? inboundRetry,
    bool? wipeOnRevocation,
    int? maxFetchPages,
    int? initialOneTimePrekeys,
  }) => EngineConfig(
    deviceName: deviceName ?? this.deviceName,
    platform: platform ?? this.platform,
    outboxBackoff: outboxBackoff ?? this.outboxBackoff,
    outboxMaxAge: outboxMaxAge ?? this.outboxMaxAge,
    outboxLease: outboxLease ?? this.outboxLease,
    staleListRetries: staleListRetries ?? this.staleListRetries,
    resendWindow: resendWindow ?? this.resendWindow,
    resetCooldown: resetCooldown ?? this.resetCooldown,
    maintenanceInterval: maintenanceInterval ?? this.maintenanceInterval,
    prekeyCheckInterval: prekeyCheckInterval ?? this.prekeyCheckInterval,
    processedRetention: processedRetention ?? this.processedRetention,
    typingExpiry: typingExpiry ?? this.typingExpiry,
    typingSendInterval: typingSendInterval ?? this.typingSendInterval,
    inboundRetry: inboundRetry ?? this.inboundRetry,
    wipeOnRevocation: wipeOnRevocation ?? this.wipeOnRevocation,
    maxFetchPages: maxFetchPages ?? this.maxFetchPages,
    initialOneTimePrekeys: initialOneTimePrekeys ?? this.initialOneTimePrekeys,
  );

  /// Name shown in the device list when this device registers or links.
  final String deviceName;
  final DevicePlatform platform;

  /// Delays between attempts to send an op the server could not take.
  final Backoff outboxBackoff;

  /// An op that has not been sent after this long is given up on (the
  /// message is shown as failed).
  final Duration outboxMaxAge;

  /// How long a claimed op stays claimed if the worker dies.
  final Duration outboxLease;

  /// How many times one send re-plans after `device_list_stale`.
  final int staleListRetries;

  /// A message older than this is not re-sent after a `decryption_error`
  /// (CRYPTO_V2.md §13a).
  final Duration resendWindow;

  /// At most one new session per remote device in this time when answering
  /// decryption failures.
  final Duration resetCooldown;

  final Duration maintenanceInterval;
  final Duration prekeyCheckInterval;

  /// Processed envelope ids are kept this long (past the replay window).
  final Duration processedRetention;

  /// A typing indicator disappears after this long without a refresh.
  final Duration typingExpiry;

  /// Own typing signals are sent at most this often per chat.
  final Duration typingSendInterval;

  /// Retry delays when the inbound pipeline hits a transient failure.
  final Backoff inboundRetry;

  /// Device revocation (close code 4003, `device_revoked`) wipes the local
  /// database (docs/architecture/remote_bounded_contexts.md).
  final bool wipeOnRevocation;

  /// Upper bound of mailbox pages one [Engine.syncOnce] reads.
  final int maxFetchPages;

  /// One-time prekeys a new device publishes (CRYPTO_V2.md §3: 100). Tests
  /// lower it to reach the replenishment threshold quickly.
  final int initialOneTimePrekeys;
}
