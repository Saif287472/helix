// lib/protocol/protocol_messages.dart

import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:helix_domain/core/constants.dart';

part 'frames/request_frames.dart';
part 'frames/chat_frames.dart';
part 'frames/file_transfer_frames.dart';
part 'frames/group_frames.dart';
part 'frames/call_frames.dart';
part 'frames/error_frames.dart';

// ---------------------------------------------------------------------------
// Message type constants
// ---------------------------------------------------------------------------

const int kTypeRequest = 0x01;
const int kTypeAccept = 0x02;
const int kTypeReject = 0x03;
const int kTypeCancel = 0x04;
const int kTypeIdentity = 0x05;
const int kTypeIdentityAck = 0x06;
const int kTypeCapability = 0x07;
const int kTypeChatMessage = 0x08;
const int kTypeChatAck = 0x09;
const int kTypeKeepalive = 0x0A;
const int kTypeClose = 0x0B;
const int kTypeProfileUpdate = 0x0C;
const int kTypeBusy = 0x0D;
const int kTypeVersionMismatch = 0x0E;
const int kTypeTypingIndicator = 0x10;
const int kTypeReadReceipt = 0x11;
const int kTypeReaction = 0x12;
const int kTypeFileTransfer = 0x13;
const int kTypeEditMessage = 0x14;
const int kTypeDeleteMessage = 0x15;
const int kTypeWipe = 0x16;
const int kTypeFileProbe =
    0x17; // Sender → Receiver: announce transfer with sha256
const int kTypeFileResume =
    0x18; // Receiver → Sender: reply with byte offset to resume from
const int kTypeFileComplete =
    0x19; // Sender → Receiver: all chunks sent, finalize
const int kTypeFileCancel = 0x1A; // Either peer: abort transfer, clean up .part
const int kTypeEphemeralMedia =
    0x1B; // RAM-only private media chunk (never written to disk)
const int kTypeGroupControl = 0x1C; // Group membership/admin/election event
const int kTypeGroupMessage = 0x1D; // Opaque sender-encrypted group payload
const int kTypeCallSignal = 0x1E; // WebRTC call signaling frame (Stage 6)

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class ProtocolException implements Exception {
  final String message;
  const ProtocolException(this.message);
  @override
  String toString() => 'ProtocolException: $message';
}

class FrameTooLargeException extends ProtocolException {
  final int size;
  FrameTooLargeException(this.size)
    : super('Frame size $size exceeds kMaxFrameBytes $kMaxFrameBytes');
}

// ---------------------------------------------------------------------------
// CBOR encode / decode helpers
//
// Strategy:
//   Encode: pass a Map<int, Object?> to CborValue(), then cbor.encode().
//   Decode: cbor.decode(bytes).toObject() → Map<Object?, Object?> with native
//           Dart types (int, String, bool, List<int> for bytes, List for arrays).
// ---------------------------------------------------------------------------

/// Encode a Dart map with integer keys as a CBOR byte string.
/// The CborValue() factory converts Map → CborMap, int → CborSmallInt, etc.
Uint8List _cborEncodeMap(Map<int, Object?> fields) {
  final encoded = cbor.encode(CborValue(fields));
  return Uint8List.fromList(encoded);
}

/// Decode CBOR bytes into a plain Dart Map with integer keys.
/// toObject(parseDateTime: false, parseUri: false) keeps timestamps as int,
/// bytes as `List<int>`, strings as String, and bools as bool.
Map<Object?, Object?> _cborDecodeMap(Uint8List bytes) {
  final cborVal = cbor.decode(bytes);
  final obj = cborVal.toObject(parseDateTime: false, parseUri: false);
  if (obj is! Map) {
    throw const ProtocolException('Frame payload is not a CBOR map');
  }
  return obj as Map<Object?, Object?>;
}

// Field extraction helpers — all throw ProtocolException on type mismatch.

int _requireInt(Map<Object?, Object?> m, int key, String field) {
  final v = m[key];
  if (v is int) return v;
  // BigInt can appear for large values.
  if (v is BigInt) return v.toInt();
  throw ProtocolException('Missing or invalid int field "$field" (key $key)');
}

int _optionalInt(
  Map<Object?, Object?> m,
  int key, {
  required int defaultValue,
}) {
  final v = m[key];
  if (v == null) return defaultValue;
  if (v is int) return v;
  if (v is BigInt) return v.toInt();
  throw ProtocolException('Invalid optional int field (key $key)');
}

String _requireString(Map<Object?, Object?> m, int key, String field) {
  final v = m[key];
  if (v is String) return v;
  throw ProtocolException(
    'Missing or invalid string field "$field" (key $key)',
  );
}

Uint8List _requireBytes(Map<Object?, Object?> m, int key, String field) {
  final v = m[key];
  if (v is Uint8List) return v;
  if (v is List<int>) return Uint8List.fromList(v);
  if (v is List) return Uint8List.fromList(v.cast<int>());
  throw ProtocolException('Missing or invalid bytes field "$field" (key $key)');
}

bool _requireBool(Map<Object?, Object?> m, int key, String field) {
  final v = m[key];
  if (v is bool) return v;
  throw ProtocolException('Missing or invalid bool field "$field" (key $key)');
}

List<String> _requireStringList(
  Map<Object?, Object?> m,
  int key,
  String field,
) {
  final v = m[key];
  if (v is List) return v.cast<String>();
  throw ProtocolException(
    'Missing or invalid string-list field "$field" (key $key)',
  );
}

// ---------------------------------------------------------------------------
// Base class
// ---------------------------------------------------------------------------

abstract class ProtocolFrame {
  int get type;

  /// Encode the frame payload as raw CBOR bytes (no length prefix).
  Uint8List encode();

  /// Decode a raw CBOR payload (already stripped of length prefix) into the
  /// appropriate concrete ProtocolFrame subtype.
  static ProtocolFrame decode(Uint8List bytes) {
    if (bytes.length > kMaxFrameBytes) {
      throw FrameTooLargeException(bytes.length);
    }
    final map = _cborDecodeMap(bytes);
    final msgType = map[0];
    if (msgType is! int) {
      throw const ProtocolException('Missing or invalid type field (key 0)');
    }
    switch (msgType) {
      case kTypeRequest:
        return RequestFrame._fromMap(map);
      case kTypeAccept:
        return AcceptFrame._fromMap(map);
      case kTypeReject:
        return RejectFrame._fromMap(map);
      case kTypeCancel:
        return CancelFrame._fromMap(map);
      case kTypeIdentity:
        return IdentityFrame._fromMap(map);
      case kTypeIdentityAck:
        return IdentityAckFrame._fromMap(map);
      case kTypeCapability:
        return CapabilityFrame._fromMap(map);
      case kTypeChatMessage:
        return ChatMessageFrame._fromMap(map);
      case kTypeChatAck:
        return ChatAckFrame._fromMap(map);
      case kTypeKeepalive:
        return KeepaliveFrame._fromMap(map);
      case kTypeClose:
        return CloseFrame._fromMap(map);
      case kTypeProfileUpdate:
        return ProfileUpdateFrame._fromMap(map);
      case kTypeBusy:
        return BusyFrame._fromMap(map);
      case kTypeVersionMismatch:
        return VersionMismatchFrame._fromMap(map);
      case kTypeTypingIndicator:
        return TypingIndicatorFrame._fromMap(map);
      case kTypeReadReceipt:
        return ReadReceiptFrame._fromMap(map);
      case kTypeReaction:
        return ReactionFrame._fromMap(map);
      case kTypeFileTransfer:
        return FileTransferFrame._fromMap(map);
      case kTypeEditMessage:
        return EditMessageFrame._fromMap(map);
      case kTypeDeleteMessage:
        return DeleteMessageFrame._fromMap(map);
      case kTypeWipe:
        return WipeFrame._fromMap(map);
      case kTypeFileProbe:
        return FileProbeFrame._fromMap(map);
      case kTypeFileResume:
        return FileResumeFrame._fromMap(map);
      case kTypeFileComplete:
        return FileCompleteFrame._fromMap(map);
      case kTypeFileCancel:
        return FileCancelFrame._fromMap(map);
      case kTypeEphemeralMedia:
        return EphemeralMediaFrame._fromMap(map);
      case kTypeGroupControl:
        return GroupControlFrame._fromMap(map);
      case kTypeGroupMessage:
        return GroupMessageFrame._fromMap(map);
      case kTypeCallSignal:
        return CallSignalFrame._fromMap(map);
      default:
        throw ProtocolException(
          'Unknown message type: 0x${msgType.toRadixString(16)}',
        );
    }
  }
}
