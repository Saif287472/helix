/// HTTP header names used by the v2 contract.
abstract final class HelixHeaders {
  /// `Bearer <access token>` for device requests and admin requests.
  static const authorization = 'authorization';

  /// Client-chosen key that makes a mutating request safe to retry. The
  /// server stores the result for 24 hours and replays it for the same key
  /// from the same principal; a different body under a reused key is
  /// `idempotency_conflict`.
  static const idempotencyKey = 'idempotency-key';

  /// Correlation id. Clients may send one; the server always returns one and
  /// includes it in its logs (never alongside secrets).
  static const requestId = 'x-request-id';

  /// `<platform>/<app version>`, e.g. `android/2.0.0`. Used for compatibility
  /// gating and support, never for authorization.
  static const client = 'x-helix-client';

  /// Seconds to wait, on `rate_limited` and `maintenance` responses.
  static const retryAfter = 'retry-after';

  /// Server-to-server request signature (federation module).
  static const s2sServer = 'x-helix-s2s-server';
  static const s2sTimestamp = 'x-helix-s2s-timestamp';
  static const s2sSignature = 'x-helix-s2s-signature';
}

/// The WebSocket subprotocol for realtime v1 with JSON frames. A future
/// binary codec is a new subprotocol name, negotiated alongside this one.
const realtimeSubprotocolJson = 'helix.v1+json';

/// Prefix of every v2 REST path.
const apiPrefix = '/v1';
