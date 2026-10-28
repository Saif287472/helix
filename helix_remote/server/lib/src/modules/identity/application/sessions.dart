import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/data/credential_store.dart';
import 'package:helix_remote_server/src/modules/identity/data/identity_store.dart';
import 'package:helix_remote_server/src/modules/identity/domain/jwt.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:shelf/shelf.dart';

/// The only place sessions are minted (AGENTS.md security invariant;
/// ADR-026). Every sign-in path ends in [issue].
final class SessionIssuer {
  SessionIssuer({
    required this.jwt,
    required this.credentials,
    required this.clock,
    required this.bus,
    this.authEvents,
  });

  final JwtCodec jwt;
  final CredentialStore credentials;
  final Clock clock;
  final EventBus bus;

  /// `helix_auth_events_total{kind}`: refresh reuse and use of a revoked
  /// device or an ended session, for an operator watching for theft.
  final Counter? authEvents;

  Future<Session> issue(
    SqlSession db, {
    required String accountId,
    required String deviceId,
  }) async {
    final now = clock.now();
    final access = jwt.sign(
      AccessClaims(
        accountId: accountId,
        deviceId: deviceId,
        issuedAt: now,
        expiresAt: now.add(IdentityConfig.accessLifetime),
      ),
    );
    final refreshId = Uuid.v7(now: now);
    final secret = randomBytes(32);
    final refreshExpires = now.add(IdentityConfig.refreshLifetime);
    await credentials.insertRefresh(
      db,
      id: refreshId,
      deviceId: deviceId,
      secretHash: sha256Bytes(secret),
      expiresAt: refreshExpires,
    );
    return Session(
      accountId: accountId,
      deviceId: deviceId,
      accessToken: access,
      accessExpiresAt: now.add(IdentityConfig.accessLifetime),
      refreshToken: 'rt_$refreshId.${encodeBytes(secret)}',
      refreshExpiresAt: refreshExpires,
    );
  }

  /// Ends every session of [deviceId] (the device stays registered). After
  /// commit, [IdentityTopics.sessionsEnded] carries the cut-off to every
  /// node, which closes sockets opened with an older token (4001).
  Future<void> endSessions(
    Tx tx,
    IdentityStore identity,
    String deviceId,
  ) async {
    final cutOff = await identity.invalidateSessions(tx, deviceId);
    if (cutOff == null) return;
    tx.afterCommit(
      () => bus.publish(IdentityTopics.sessionsEnded, {
        'device': deviceId,
        'before': cutOff.millisecondsSinceEpoch,
      }),
    );
  }

  /// Rotates a refresh token. Presenting a token that was already used or
  /// revoked is treated as theft: every session of that device ends.
  Future<Session> refresh(Db db, IdentityStore identity, String token) async {
    final parsed = _parseRefresh(token);
    if (parsed == null) throw const ApiError(ErrorCode.unauthenticated);
    // A reuse must *commit* the session cut-off before reporting the error,
    // so the transaction returns the error instead of throwing it.
    final (session, error) = await db.tx<(Session?, ApiError?)>((tx) async {
      // The device first (as a sign-out does), then its refresh token.
      final owner = await credentials.refreshDevice(tx, parsed.id);
      if (owner != null) await identity.lockDevice(tx, owner);
      final row = await credentials.refreshForUpdate(tx, parsed.id);
      if (row == null ||
          !constantTimeEquals(
            row.bytes('secret_hash'),
            sha256Bytes(parsed.secret),
          )) {
        return (null, const ApiError(ErrorCode.unauthenticated));
      }
      final deviceId = row.string('device_id');
      if (!row.isNull('used_at') || !row.isNull('revoked_at')) {
        await endSessions(tx, identity, deviceId);
        // Used twice is the signal (a retry, or a stolen copy). A token that
        // was only revoked by a sign-out is counted but says nothing new.
        final reused = !row.isNull('used_at');
        authEvents?.inc({'kind': reused ? 'refresh_reuse' : 'revoked_refresh'});
        final stolen = reused ? await identity.deviceById(tx, deviceId) : null;
        if (stolen != null) {
          await identity.addEvent(
            tx,
            stolen.accountId,
            SecurityEventKind.sessionReuse,
            deviceId: deviceId,
            deviceName: stolen.name,
          );
        }
        return (
          null,
          const ApiError(
            ErrorCode.unauthenticated,
            message: 'refresh token reused',
          ),
        );
      }
      if (!row.time('expires_at').isAfter(clock.now())) {
        return (null, const ApiError(ErrorCode.tokenExpired));
      }
      final device = await identity.deviceById(tx, deviceId);
      if (device == null || !device.active) {
        return (null, const ApiError(ErrorCode.deviceRevoked));
      }
      await credentials.markRefreshUsed(tx, parsed.id);
      return (
        await issue(tx, accountId: device.accountId, deviceId: deviceId),
        null,
      );
    });
    if (error != null) throw error;
    return session!;
  }

  static ({String id, Uint8List secret})? _parseRefresh(String token) {
    if (!token.startsWith('rt_')) return null;
    final dot = token.indexOf('.');
    if (dot < 0) return null;
    final id = token.substring(3, dot);
    if (!Uuid.isValid(id)) return null;
    try {
      final secret = decodeBytes(token.substring(dot + 1));
      return secret.length == 32 ? (id: id, secret: secret) : null;
    } on Object {
      return null;
    }
  }
}

/// Verifies device access tokens for the HTTP layer.
final class IdentityAuthenticator implements Authenticator {
  IdentityAuthenticator({
    required this.db,
    required this.jwt,
    required this.store,
    required this.clock,
    this.authEvents,
  });

  final Counter? authEvents;
  final Db db;
  final JwtCodec jwt;
  final IdentityStore store;
  final Clock clock;

  @override
  Future<DevicePrincipal?> device(String bearerToken) async {
    final claims = jwt.verify(bearerToken, clock.now());
    if (claims == null) return null;
    final state = await store.authState(db, claims.deviceId);
    if (state == null) return null;
    if (!state.active) {
      authEvents?.inc({'kind': 'revoked_device'});
      return null;
    }
    if (claims.issuedAt.isBefore(state.tokensValidAfter)) {
      authEvents?.inc({'kind': 'ended_session'});
      return null;
    }
    await _touch(claims.deviceId);
    return DevicePrincipal(
      accountId: claims.accountId,
      deviceId: claims.deviceId,
      suspended: state.accountStatus == 'suspended',
    );
  }

  /// The day each device was last written as seen, on this node. The column
  /// is a date, so once today is recorded the statement would change nothing:
  /// it is skipped, and each node writes a device at most once a day
  /// (AUD-2-4). Cleared when the day turns, so it never outgrows one day's
  /// devices.
  final Map<String, DateTime> _seenToday = {};
  DateTime _seenDay = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  Future<void> _touch(String deviceId) async {
    final now = clock.now().toUtc();
    final day = DateTime.utc(now.year, now.month, now.day);
    if (day != _seenDay) {
      _seenToday.clear();
      _seenDay = day;
    }
    if (_seenToday.containsKey(deviceId)) return;
    await store.touchLastSeen(db, deviceId);
    _seenToday[deviceId] = day;
  }

  @override
  Future<AdminPrincipal?> admin(String bearerToken) async => null;

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) async =>
      null;
}
