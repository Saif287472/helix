import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/data/credential_store.dart';
import 'package:helix_remote_server/src/modules/identity/data/identity_store.dart';
import 'package:helix_remote_server/src/modules/identity/domain/jwt.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:shelf/shelf.dart';

/// The only place sessions are minted (AGENTS.md security invariant;
/// ADR-026). Every sign-in path ends in [issue].
final class SessionIssuer {
  SessionIssuer({
    required this.jwt,
    required this.credentials,
    required this.clock,
  });

  final JwtCodec jwt;
  final CredentialStore credentials;
  final Clock clock;

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

  /// Rotates a refresh token. Presenting a token that was already used or
  /// revoked is treated as theft: every session of that device ends.
  Future<Session> refresh(Db db, IdentityStore identity, String token) async {
    final parsed = _parseRefresh(token);
    if (parsed == null) throw const ApiError(ErrorCode.unauthenticated);
    // A reuse must *commit* the session cut-off before reporting the error,
    // so the transaction returns the error instead of throwing it.
    final (session, error) = await db.tx<(Session?, ApiError?)>((tx) async {
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
        await identity.invalidateSessions(tx, deviceId);
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
  });

  final Db db;
  final JwtCodec jwt;
  final IdentityStore store;
  final Clock clock;

  @override
  Future<DevicePrincipal?> device(String bearerToken) async {
    final claims = jwt.verify(bearerToken, clock.now());
    if (claims == null) return null;
    final state = await store.authState(db, claims.deviceId);
    if (state == null || !state.active) return null;
    if (claims.issuedAt.isBefore(state.tokensValidAfter)) return null;
    await store.touchLastSeen(db, claims.deviceId);
    return DevicePrincipal(
      accountId: claims.accountId,
      deviceId: claims.deviceId,
      suspended: state.accountStatus == 'suspended',
    );
  }

  @override
  Future<AdminPrincipal?> admin(String bearerToken) async => null;

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) async =>
      null;
}
