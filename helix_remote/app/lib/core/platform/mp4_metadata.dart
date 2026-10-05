import 'dart:io';
import 'dart:typed_data';

/// What an MP4 / MOV / 3GP file says about its video: how long, how large
/// (as shown, after rotation) and the container's own metadata.
///
/// Reading the `moov` box is enough for both jobs, so a video of any size is
/// handled by reading its box headers and one small box, never the media.
final class Mp4Info {
  const Mp4Info({this.durationMs, this.width, this.height});

  final int? durationMs;

  /// The size the picture is shown at: rotated by the track's matrix, so a
  /// phone video recorded upright is taller than wide.
  final int? width;
  final int? height;
}

/// What [Mp4Metadata.scan] found that identifies the person or the moment.
final class Mp4Scan {
  const Mp4Scan({required this.info, required this.patches});

  final Mp4Info info;

  /// Byte ranges to turn into `free` boxes, and time stamps to zero. Empty
  /// when the file is already clean.
  final List<Mp4Patch> patches;

  bool get isClean => patches.isEmpty;
}

/// One in-place edit: overwrite [length] bytes at [offset] with [bytes]
/// (always the same length as what is replaced, so no offset in the file
/// moves).
final class Mp4Patch {
  const Mp4Patch(this.offset, this.bytes);

  final int offset;
  final Uint8List bytes;
}

/// Reads and cleans the box structure of an ISO base media file.
///
/// Cleaning is **in place and the same size**: a box that holds a position
/// (`udta` with `\xA9xyz` or `loci`), a free-form tag (`meta`, `uuid` for XMP)
/// becomes a `free` box of the same length with its contents zeroed, and the
/// creation and modification times in the movie, track and media headers are
/// zeroed. Nothing is re-encoded and the media data is not touched, so it is
/// fast whatever the size and cannot degrade the video.
abstract final class Mp4Metadata {
  /// Largest `moov` box read into memory. Real files are a few hundred
  /// kilobytes; anything larger is refused rather than loaded.
  static const maxMoovBytes = 64 * 1024 * 1024;

  /// Whether the first box of [head] looks like an ISO base media file.
  static bool looksLikeMp4(Uint8List head) {
    if (head.length < 12) return false;
    final type = String.fromCharCodes(head, 4, 8);
    return const {
      'ftyp',
      'moov',
      'mdat',
      'free',
      'skip',
      'wide',
    }.contains(type);
  }

  /// Reads the boxes of [file]. Null when it is not an MP4 family file or its
  /// `moov` cannot be found or is too large.
  static Future<Mp4Scan?> scan(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      await raf.setPosition(0);
      final head = await raf.read(16);
      if (!looksLikeMp4(Uint8List.fromList(head))) return null;
      final patches = <Mp4Patch>[];
      Mp4Info? info;
      var at = 0;
      while (at + 8 <= length) {
        await raf.setPosition(at);
        final header = Uint8List.fromList(await raf.read(16));
        if (header.length < 8) break;
        final d = ByteData.sublistView(header);
        var size = d.getUint32(0);
        final type = String.fromCharCodes(header, 4, 8);
        var headerSize = 8;
        if (size == 1) {
          if (header.length < 16) break;
          size = d.getUint64(8);
          headerSize = 16;
        } else if (size == 0) {
          size = length - at;
        }
        if (size < headerSize || at + size > length) return null;
        if (type == 'moov') {
          if (size > maxMoovBytes) return null;
          await raf.setPosition(at);
          final moov = Uint8List.fromList(await raf.read(size));
          final result = _scanMoov(moov, headerSize);
          info = result.info;
          for (final patch in result.patches) {
            patches.add(Mp4Patch(at + patch.offset, patch.bytes));
          }
        } else if (type == 'meta' || type == 'uuid') {
          patches.add(Mp4Patch(at + 4, _freeBox(size - 4)));
        }
        at += size;
      }
      if (info == null) return null;
      return Mp4Scan(info: info, patches: patches);
    } finally {
      await raf.close();
    }
  }

  /// Writes [source] to [target] with [patches] applied: the same bytes
  /// everywhere except the patched ranges. A copy, never an edit in place: the
  /// file may be the person's own, and Dart has no way to overwrite part of a
  /// file without truncating it or appending (an append-mode write ignores
  /// the position on Android).
  static Future<void> writeCleaned(
    File source,
    File target,
    List<Mp4Patch> patches,
  ) async {
    final sorted = [...patches]..sort((a, b) => a.offset.compareTo(b.offset));
    final sink = target.openWrite();
    try {
      var position = 0;
      var next = 0;
      await for (final chunk in source.openRead()) {
        var from = 0;
        while (from < chunk.length) {
          // A patch can start before this chunk ends and run past it.
          final patch = next < sorted.length ? sorted[next] : null;
          final absolute = position + from;
          if (patch != null && absolute >= patch.offset) {
            final inside = absolute - patch.offset;
            final take = (patch.bytes.length - inside).clamp(
              0,
              chunk.length - from,
            );
            sink.add(patch.bytes.sublist(inside, inside + take));
            from += take;
            if (inside + take >= patch.bytes.length) next++;
          } else {
            final stop = patch == null
                ? chunk.length
                : (patch.offset - position).clamp(from, chunk.length);
            sink.add(chunk.sublist(from, stop));
            from = stop;
          }
        }
        position += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// [Mp4Info] of the `moov` box bytes [moov] (with its [headerSize]), and the
  /// patches (offsets relative to the box start).
  static ({Mp4Info info, List<Mp4Patch> patches}) _scanMoov(
    Uint8List moov,
    int headerSize,
  ) {
    final patches = <Mp4Patch>[];
    int? durationMs;
    int? width;
    int? height;
    void zeroTimes(int dataStart, int end) {
      // version(1) flags(3) creation modification (4 or 8 bytes each).
      final version = moov[dataStart];
      final span = version == 1 ? 16 : 8;
      if (dataStart + 4 + span > end) return;
      final times = moov.sublist(dataStart + 4, dataStart + 4 + span);
      if (times.any((b) => b != 0)) {
        patches.add(Mp4Patch(dataStart + 4, Uint8List(span)));
      }
    }

    void walk(int from, int to, String path) {
      var at = from;
      while (at + 8 <= to) {
        final d = ByteData.sublistView(moov);
        var size = d.getUint32(at);
        final type = String.fromCharCodes(moov, at + 4, at + 8);
        var header = 8;
        if (size == 1) {
          if (at + 16 > to) return;
          size = d.getUint64(at + 8);
          header = 16;
        } else if (size == 0) {
          size = to - at;
        }
        if (size < header || at + size > to) return;
        final dataStart = at + header;
        final end = at + size;
        switch ((path, type)) {
          case ('moov', 'udta') || ('moov', 'meta') || ('moov', 'uuid'):
            patches.add(Mp4Patch(at + 4, _freeBox(size - 4)));
          case ('moov', 'mvhd'):
            zeroTimes(dataStart, end);
            final version = moov[dataStart];
            final scaleAt = dataStart + (version == 1 ? 20 : 12);
            if (scaleAt + (version == 1 ? 12 : 8) <= end) {
              final scale = d.getUint32(scaleAt);
              final duration = version == 1
                  ? d.getUint64(scaleAt + 4)
                  : d.getUint32(scaleAt + 4);
              if (scale > 0) durationMs = (duration * 1000 / scale).round();
            }
          case ('moov', 'trak'):
            walk(dataStart, end, 'trak');
          case ('trak', 'tkhd'):
            zeroTimes(dataStart, end);
            final shown = _trackSize(moov, dataStart, end);
            if (shown != null && width == null) (width, height) = shown;
          case ('trak', 'mdia'):
            walk(dataStart, end, 'mdia');
          case ('mdia', 'mdhd'):
            zeroTimes(dataStart, end);
          case ('trak', 'meta') || ('trak', 'udta'):
            patches.add(Mp4Patch(at + 4, _freeBox(size - 4)));
          default:
            break;
        }
        at = end;
      }
    }

    walk(headerSize, moov.length, 'moov');
    return (
      info: Mp4Info(durationMs: durationMs, width: width, height: height),
      patches: patches,
    );
  }

  /// The display size from a `tkhd` box's matrix and 16.16 width and height,
  /// or null for a track that is not a picture (audio tracks are 0 x 0).
  static (int, int)? _trackSize(Uint8List moov, int dataStart, int end) {
    final d = ByteData.sublistView(moov);
    final version = moov[dataStart];
    // Header fields up to the duration (24 bytes, 36 in version 1), then
    // reserved(8), layer, group, volume, reserved(2) = 16 bytes, then the
    // matrix (9 x 4 bytes), then 16.16 width and height.
    final matrix = dataStart + (version == 1 ? 36 : 24) + 16;
    final sizeAt = matrix + 36;
    if (sizeAt + 8 > end) return null;
    final w = d.getUint32(sizeAt) >> 16;
    final h = d.getUint32(sizeAt + 4) >> 16;
    if (w == 0 || h == 0) return null;
    // a, b / c, d of the matrix (16.16 fixed point): a quarter turn has a and
    // d zero and b, c non-zero.
    final a = d.getInt32(matrix);
    final b = d.getInt32(matrix + 4);
    final turned = a == 0 && b != 0;
    return turned ? (h, w) : (w, h);
  }

  /// The bytes that turn a box into a `free` box with a zeroed body: [length]
  /// counts from the box's type field on, so the size field stays as it was.
  static Uint8List _freeBox(int length) {
    final out = Uint8List(length);
    out.setRange(0, 4, const [0x66, 0x72, 0x65, 0x65]); // "free"
    return out;
  }
}
