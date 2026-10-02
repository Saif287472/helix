import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What an archive is for. The kind is in the header and the reader checks it,
/// so a transfer cannot be fed to the history-backup restore (or the other way
/// round) and a history backup can never smuggle in the full backup's secrets.
enum ArchiveKind implements WireEnum {
  /// The automatic backup, keyed from the account identity key. No secrets.
  history('history'),

  /// Inside the full backup envelope: the only kind that may carry the
  /// account identity key.
  full('full'),

  /// Device-to-device transfer over the media relay. May carry the profile
  /// key (the other device is this account's own) but never the identity key.
  transfer('transfer');

  const ArchiveKind(this.wire);

  @override
  final String wire;
}

/// One frame of an archive and how many messages it holds.
final class ArchiveFrame {
  const ArchiveFrame(this.bytes, this.messages);

  final Uint8List bytes;
  final int messages;
}

/// The archive layout shared by the history backup, the full backup and the
/// device-to-device transfer (the db docs: "both share one format").
///
/// ```
/// archive := frame*
/// frame   := u32(n) ‖ u8(codec) ‖ payload[n - 1]
/// codec   := 0 raw | 1 gzip
/// payload := NDJSON: one JSON record per line
/// ```
///
/// Frames hold whole records and are independent of each other, so an archive
/// is written and read a frame at a time (bounded memory for any history),
/// cut into transfer segments at frame boundaries, and trimmed to a size
/// budget by dropping whole frames. The first record of the first frame is the
/// `header`; everything is encrypted as a whole by the caller (history backup,
/// backup envelope) or per segment (transfer).
abstract final class ArchiveFormat {
  /// The archive version this engine writes; a header naming a higher one is
  /// refused as `newerFormat`.
  static const version = 1;

  static const codecRaw = 0;
  static const codecGzip = 1;

  /// A frame past either limit is corrupt, not merely big.
  static const maxFrameStored = 8 * 1024 * 1024;
  static const maxFrameExpanded = 32 * 1024 * 1024;

  /// A record longer than this is dropped by the writer (and refused by the
  /// reader), so one pathological message cannot sink a backup.
  static const maxRecordBytes = 1024 * 1024;
}

/// Builds frames from records. [gzip] is the host's gzip codec (`dart:io`'s
/// `gzip` fits; the engine itself has no `dart:io`); without it frames are
/// stored raw.
final class ArchiveWriter {
  ArchiveWriter({this.gzip, this.frameBytes = 256 * 1024});

  final Codec<List<int>, List<int>>? gzip;

  /// A frame is closed once its records pass this many raw bytes.
  final int frameBytes;

  final BytesBuilder _page = BytesBuilder(copy: false);
  int _pageMessages = 0;
  final List<ArchiveFrame> _done = [];

  /// Appends [record]. Returns false (and writes nothing) when it is too
  /// long to read back.
  bool add(JsonMap record, {bool message = false}) {
    final line = utf8.encode(jsonEncode(record));
    if (line.length > ArchiveFormat.maxRecordBytes) return false;
    _page
      ..add(line)
      ..addByte(0x0a);
    if (message) _pageMessages++;
    if (_page.length >= frameBytes) _seal();
    return true;
  }

  /// The frames completed so far (and forgets them).
  List<ArchiveFrame> takeFrames() {
    final out = List.of(_done);
    _done.clear();
    return out;
  }

  /// Closes the frame being built and returns everything not yet taken.
  List<ArchiveFrame> finish() {
    if (_page.length > 0) _seal();
    return takeFrames();
  }

  void _seal() {
    final raw = _page.takeBytes();
    var codec = ArchiveFormat.codecRaw;
    var payload = raw;
    final z = gzip;
    if (z != null) {
      final packed = Uint8List.fromList(z.encode(raw));
      if (packed.length < raw.length) {
        codec = ArchiveFormat.codecGzip;
        payload = packed;
      }
    }
    final out = Uint8List(5 + payload.length);
    final view = ByteData.sublistView(out);
    view.setUint32(0, 1 + payload.length);
    out[4] = codec;
    out.setRange(5, out.length, payload);
    _done.add(ArchiveFrame(out, _pageMessages));
    _pageMessages = 0;
  }
}

/// Reads frames and records back. Every structural problem is a
/// [BackupException] with `corrupt` (or `compressionUnavailable`): the bytes
/// were authenticated by whoever opened them, so damage means a bug or a
/// truncated copy, never an attacker's input to be "repaired".
abstract final class ArchiveReader {
  /// Splits [bytes] into frames and yields each frame's NDJSON text.
  static Iterable<Uint8List> frames(
    List<int> bytes, {
    Codec<List<int>, List<int>>? gzip,
  }) sync* {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);
    var at = 0;
    while (at < data.length) {
      if (data.length - at < 5) {
        throw const BackupException(BackupFailure.corrupt, 'truncated frame');
      }
      final n = view.getUint32(at);
      if (n < 1 || n > ArchiveFormat.maxFrameStored) {
        throw const BackupException(BackupFailure.corrupt, 'frame length');
      }
      if (data.length - at - 4 < n) {
        throw const BackupException(BackupFailure.corrupt, 'truncated frame');
      }
      final codec = data[at + 4];
      final payload = Uint8List.sublistView(data, at + 5, at + 4 + n);
      at += 4 + n;
      yield _expand(codec, payload, gzip);
    }
  }

  static Uint8List _expand(
    int codec,
    Uint8List payload,
    Codec<List<int>, List<int>>? gzip,
  ) {
    switch (codec) {
      case ArchiveFormat.codecRaw:
        if (payload.length > ArchiveFormat.maxFrameExpanded) {
          throw const BackupException(BackupFailure.corrupt, 'frame size');
        }
        return payload;
      case ArchiveFormat.codecGzip:
        if (gzip == null) {
          throw const BackupException(
            BackupFailure.compressionUnavailable,
            'the backup is gzip-compressed and no codec was given',
          );
        }
        final Uint8List expanded;
        try {
          expanded = Uint8List.fromList(gzip.decode(payload));
        } on Object {
          throw const BackupException(BackupFailure.corrupt, 'gzip frame');
        }
        if (expanded.length > ArchiveFormat.maxFrameExpanded) {
          throw const BackupException(BackupFailure.corrupt, 'frame size');
        }
        return expanded;
      default:
        throw const BackupException(
          BackupFailure.newerFormat,
          'unknown frame codec',
        );
    }
  }

  /// The records of one frame's text.
  static Iterable<JsonReader> records(Uint8List frame) sync* {
    var start = 0;
    while (start < frame.length) {
      var end = frame.indexOf(0x0a, start);
      if (end < 0) end = frame.length;
      if (end - start > ArchiveFormat.maxRecordBytes) {
        throw const BackupException(BackupFailure.corrupt, 'record length');
      }
      if (end > start) {
        try {
          yield JsonReader.decode(
            utf8.decode(Uint8List.sublistView(frame, start, end)),
          );
        } on FormatException {
          throw const BackupException(BackupFailure.corrupt, 'record');
        }
      }
      start = end + 1;
    }
  }
}
