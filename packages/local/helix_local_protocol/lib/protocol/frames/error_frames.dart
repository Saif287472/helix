part of '../protocol_messages.dart';

// ---------------------------------------------------------------------------
// 0x0E VersionMismatchFrame
// ---------------------------------------------------------------------------

class VersionMismatchFrame extends ProtocolFrame {
  @override
  final int type = kTypeVersionMismatch;

  final int ourMajor;
  final int ourMinor;

  VersionMismatchFrame({required this.ourMajor, required this.ourMinor});

  factory VersionMismatchFrame._fromMap(Map<Object?, Object?> map) =>
      VersionMismatchFrame(
        ourMajor: _requireInt(map, 1, 'ourMajor'),
        ourMinor: _requireInt(map, 2, 'ourMinor'),
      );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeVersionMismatch, 1: ourMajor, 2: ourMinor});
}
