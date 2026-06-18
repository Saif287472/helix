import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';

/// Encode a frame with a 4-byte big-endian length prefix.
Uint8List encodeFrame(ProtocolFrame frame) {
  final payload = frame.encode();
  if (payload.length > kMaxFrameBytes) {
    throw FrameTooLargeException(payload.length);
  }
  final lenBuf = ByteData(kFrameLengthPrefixBytes);
  lenBuf.setUint32(0, payload.length, Endian.big);
  final out = BytesBuilder(copy: false);
  out.add(lenBuf.buffer.asUint8List());
  out.add(payload);
  return out.toBytes();
}

/// Write a length-prefixed frame to a socket or sink and flush.
Future<void> writeFrame(IOSink sink, ProtocolFrame frame) async {
  sink.add(encodeFrame(frame));
  await sink.flush();
}

/// Read exactly one length-prefixed frame from a raw byte stream.
///
/// Returns `null` on a clean EOF between frames.
Future<ProtocolFrame?> readFrame(Stream<Uint8List> byteStream) {
  return LengthPrefixedFrameReader(byteStream).readFrame();
}

/// Owns a single stream iterator and buffers bytes between sequential reads.
class LengthPrefixedFrameReader {
  LengthPrefixedFrameReader(Stream<Uint8List> stream)
    : _iter = StreamIterator<Uint8List>(stream);

  final StreamIterator<Uint8List> _iter;
  final _buffer = BytesBuilder(copy: false);
  bool _done = false;
  bool _cancelled = false;

  Future<void> cancel() async {
    _cancelled = true;
    await _iter.cancel();
  }

  Future<ProtocolFrame?> readFrame() async {
    final lenBytes = await _readExactly(kFrameLengthPrefixBytes);
    if (lenBytes == null) return null;

    final length = ByteData.sublistView(lenBytes).getUint32(0, Endian.big);
    if (length == 0) {
      throw const ProtocolException('Zero-length frame');
    }
    if (length > kMaxFrameBytes) {
      throw FrameTooLargeException(length);
    }

    final payload = await _readExactly(length);
    if (payload == null) {
      throw const ProtocolException('Unexpected EOF reading frame payload');
    }

    return ProtocolFrame.decode(payload);
  }

  Future<Uint8List?> _readExactly(int count) async {
    while (_buffer.length < count && !_done && !_cancelled) {
      if (!await _iter.moveNext()) {
        _done = true;
        break;
      }
      _buffer.add(_iter.current);
    }

    if (_buffer.length == 0 && (_done || _cancelled)) return null;
    if (_buffer.length < count) {
      throw const ProtocolException('Unexpected EOF mid-frame');
    }

    final all = _buffer.toBytes();
    _buffer.clear();
    if (all.length > count) {
      _buffer.add(Uint8List.sublistView(all, count));
    }
    return Uint8List.sublistView(all, 0, count);
  }
}
