part of '../protocol_messages.dart';

// ---------------------------------------------------------------------------
// 0x01 RequestFrame
// ---------------------------------------------------------------------------

class RequestFrame extends ProtocolFrame {
  @override
  final int type = kTypeRequest;

  final String requestId;
  final String displayName;
  final String deviceSuffix;
  final String sessionId;
  final String staticKeyFingerprint;
  final int protocolMajor;
  final int protocolMinor;
  final int port;
  final int expiresAt; // unix ms

  RequestFrame({
    required this.requestId,
    required this.displayName,
    required this.deviceSuffix,
    required this.sessionId,
    required this.staticKeyFingerprint,
    required this.protocolMajor,
    required this.protocolMinor,
    required this.port,
    required this.expiresAt,
  });

  factory RequestFrame._fromMap(Map<Object?, Object?> map) => RequestFrame(
    requestId: _requireString(map, 1, 'requestId'),
    displayName: _requireString(map, 2, 'displayName'),
    deviceSuffix: _requireString(map, 3, 'deviceSuffix'),
    sessionId: _requireString(map, 4, 'sessionId'),
    staticKeyFingerprint: _requireString(map, 5, 'staticKeyFingerprint'),
    protocolMajor: _requireInt(map, 6, 'protocolMajor'),
    protocolMinor: _requireInt(map, 7, 'protocolMinor'),
    port: _requireInt(map, 8, 'port'),
    expiresAt: _requireInt(map, 9, 'expiresAt'),
  );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeRequest,
    1: requestId,
    2: displayName,
    3: deviceSuffix,
    4: sessionId,
    5: staticKeyFingerprint,
    6: protocolMajor,
    7: protocolMinor,
    8: port,
    9: expiresAt,
  });
}

// ---------------------------------------------------------------------------
// 0x02 AcceptFrame
// ---------------------------------------------------------------------------

class AcceptFrame extends ProtocolFrame {
  @override
  final int type = kTypeAccept;

  final String requestId;
  final int connectPort;

  AcceptFrame({required this.requestId, this.connectPort = 0});

  factory AcceptFrame._fromMap(Map<Object?, Object?> map) => AcceptFrame(
    requestId: _requireString(map, 1, 'requestId'),
    connectPort: _optionalInt(map, 2, defaultValue: 0),
  );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeAccept,
    1: requestId,
    if (connectPort > 0) 2: connectPort,
  });
}

// ---------------------------------------------------------------------------
// 0x03 RejectFrame
// ---------------------------------------------------------------------------

class RejectFrame extends ProtocolFrame {
  @override
  final int type = kTypeReject;

  final String requestId;

  /// Generic rejection reason — must not contain sensitive information.
  final String reason;

  RejectFrame({required this.requestId, required this.reason});

  factory RejectFrame._fromMap(Map<Object?, Object?> map) => RejectFrame(
    requestId: _requireString(map, 1, 'requestId'),
    reason: _requireString(map, 2, 'reason'),
  );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeReject, 1: requestId, 2: reason});
}

// ---------------------------------------------------------------------------
// 0x04 CancelFrame
// ---------------------------------------------------------------------------

class CancelFrame extends ProtocolFrame {
  @override
  final int type = kTypeCancel;

  final String requestId;

  CancelFrame({required this.requestId});

  factory CancelFrame._fromMap(Map<Object?, Object?> map) =>
      CancelFrame(requestId: _requireString(map, 1, 'requestId'));

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeCancel, 1: requestId});
}

// ---------------------------------------------------------------------------
// 0x05 IdentityFrame
// ---------------------------------------------------------------------------

class IdentityFrame extends ProtocolFrame {
  @override
  final int type = kTypeIdentity;

  /// DER-encoded RSA-2048 SubjectPublicKeyInfo bytes of the static identity.
  final Uint8List staticPublicKeyDer;

  /// RSA-SHA-256 signature over:
  ///   bytes("Helix-identity-v1") + ASCII bytes of [sessionId]
  final Uint8List signature;

  /// The session ID this frame is bound to.
  final String sessionId;

  IdentityFrame({
    required this.staticPublicKeyDer,
    required this.signature,
    required this.sessionId,
  });

  factory IdentityFrame._fromMap(Map<Object?, Object?> map) => IdentityFrame(
    staticPublicKeyDer: _requireBytes(map, 1, 'staticPublicKeyDer'),
    signature: _requireBytes(map, 2, 'signature'),
    sessionId: _requireString(map, 3, 'sessionId'),
  );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeIdentity,
    1: staticPublicKeyDer,
    2: signature,
    3: sessionId,
  });
}

// ---------------------------------------------------------------------------
// 0x06 IdentityAckFrame
// ---------------------------------------------------------------------------

class IdentityAckFrame extends ProtocolFrame {
  @override
  final int type = kTypeIdentityAck;

  final bool ok;
  final String sessionId;

  IdentityAckFrame({required this.ok, required this.sessionId});

  factory IdentityAckFrame._fromMap(Map<Object?, Object?> map) =>
      IdentityAckFrame(
        ok: _requireBool(map, 1, 'ok'),
        sessionId: _requireString(map, 2, 'sessionId'),
      );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeIdentityAck, 1: ok, 2: sessionId});
}

// ---------------------------------------------------------------------------
// 0x07 CapabilityFrame
// ---------------------------------------------------------------------------

class CapabilityFrame extends ProtocolFrame {
  @override
  final int type = kTypeCapability;

  final int major;
  final int minor;
  final List<String> features;

  /// Bitmask of negotiated capability flags (see [kCapFileTransfer] etc.).
  final int capabilities;

  CapabilityFrame({
    required this.major,
    required this.minor,
    required this.features,
    this.capabilities = 0,
  });

  factory CapabilityFrame._fromMap(Map<Object?, Object?> map) =>
      CapabilityFrame(
        major: _requireInt(map, 1, 'major'),
        minor: _requireInt(map, 2, 'minor'),
        features: _requireStringList(map, 3, 'features'),
        capabilities: _requireInt(map, 4, 'capabilities'),
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeCapability,
    1: major,
    2: minor,
    3: features,
    4: capabilities,
  });
}
