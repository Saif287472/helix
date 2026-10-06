import 'dart:typed_data';

/// Removes the metadata a photo carries about where, when and with what it was
/// taken: EXIF (GPS position, time, camera make and model, the embedded
/// thumbnail), XMP, IPTC, comments and anything appended after the picture.
///
/// Pure Dart on bytes, so it runs the same on a phone and in a test, and in a
/// background isolate. The picture's pixels are never decoded or re-encoded: a
/// JPEG, PNG or WebP keeps its exact quality and loses only the side data. The
/// one thing a viewer needs from a JPEG's EXIF, its orientation, is written
/// back as a tiny EXIF block of its own (a single tag, no position, no time),
/// so a portrait photo does not turn on its side.
abstract final class ImageMetadata {
  /// [bytes] without metadata, or null when they are not a JPEG, PNG or WebP
  /// the stripper understands (a corrupt file is null as well: the caller
  /// must not send what it could not clean).
  static Uint8List? strip(Uint8List bytes) =>
      stripJpeg(bytes) ?? stripPng(bytes) ?? stripWebp(bytes);

  /// True when [bytes] start like a GIF. A GIF has no EXIF block, so it is
  /// sent as it is.
  static bool isGif(Uint8List bytes) =>
      bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38;

  // ------------------------------------------------------------------ JPEG

  /// The EXIF orientation (1-8) of a JPEG, or 1 when it has none.
  static int jpegOrientation(Uint8List b) {
    for (final segment in _jpegSegments(b)) {
      if (segment.marker == 0xE1 && _startsWith(b, segment.dataStart, _exif)) {
        return _exifOrientation(b, segment.dataStart + 6, segment.end);
      }
    }
    return 1;
  }

  static const _exif = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  static const _icc = [
    0x49, 0x43, 0x43, 0x5F, 0x50, 0x52, 0x4F, 0x46, 0x49, 0x4C, 0x45, 0x00, //
  ];
  static const _jfif = [0x4A, 0x46, 0x49, 0x46, 0x00];
  static const _adobe = [0x41, 0x64, 0x6F, 0x62, 0x65];

  /// Strips a JPEG: keeps the pixels and what decoding needs (tables, frame
  /// and scan headers, the colour profile, Adobe's colour transform, JFIF),
  /// drops every other segment and everything after the end of the image.
  /// Null when [b] is not a well-formed JPEG.
  static Uint8List? stripJpeg(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    final head = BytesBuilder(copy: false); // JFIF, then the orientation
    final body = BytesBuilder(copy: false);
    var orientation = 1;
    var sawImage = false;
    var i = 2;
    var ended = false;
    while (i + 1 < b.length && !ended) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD9) {
        body.add(const [0xFF, 0xD9]);
        ended = true;
        break;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        body.add(Uint8List.sublistView(b, i, i + 2));
        i += 2;
        continue;
      }
      if (i + 4 > b.length) return null;
      final length = (b[i + 2] << 8) | b[i + 3];
      final end = i + 2 + length;
      if (length < 2 || end > b.length) return null;
      final dataStart = i + 4;

      if (marker == 0xDA) {
        // A scan: its header, then entropy-coded bytes up to the next marker.
        sawImage = true;
        var j = end;
        while (j + 1 < b.length) {
          if (b[j] == 0xFF) {
            final m = b[j + 1];
            if (m == 0x00 || (m >= 0xD0 && m <= 0xD7)) {
              j += 2;
              continue;
            }
            if (m == 0xFF) {
              j++;
              continue;
            }
            break;
          }
          j++;
        }
        if (j + 1 >= b.length) j = b.length;
        body.add(Uint8List.sublistView(b, i, j));
        i = j;
        continue;
      }

      final isApp = marker >= 0xE0 && marker <= 0xEF;
      if (!isApp && marker != 0xFE) {
        body.add(Uint8List.sublistView(b, i, end));
      } else if (marker == 0xE0 && _startsWith(b, dataStart, _jfif)) {
        // JFIF without its embedded thumbnail (the first 14 data bytes are
        // the header; the thumbnail dimensions are the last two).
        if (length >= 16) {
          final header = Uint8List.fromList([
            0xFF, 0xE0, 0x00, 0x10, //
            ...b.sublist(dataStart, dataStart + 12),
            0, 0,
          ]);
          head.add(header);
        }
      } else if (marker == 0xE1 && _startsWith(b, dataStart, _exif)) {
        orientation = _exifOrientation(b, dataStart + 6, end);
      } else if (marker == 0xE2 && _startsWith(b, dataStart, _icc)) {
        body.add(Uint8List.sublistView(b, i, end));
      } else if (marker == 0xEE && _startsWith(b, dataStart, _adobe)) {
        body.add(Uint8List.sublistView(b, i, end));
      }
      // Everything else (EXIF, XMP, IPTC, MPF, comments, vendor blocks) is
      // dropped.
      i = end;
    }
    if (!sawImage) return null;
    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
    out.add(head.takeBytes());
    if (orientation > 1 && orientation <= 8) {
      out.add(_orientationOnlyExif(orientation));
    }
    out.add(body.takeBytes());
    return out.takeBytes();
  }

  static Iterable<({int marker, int dataStart, int end})> _jpegSegments(
    Uint8List b,
  ) sync* {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return;
    var i = 2;
    while (i + 3 < b.length) {
      if (b[i] != 0xFF) return;
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return;
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = (b[i + 2] << 8) | b[i + 3];
      final end = i + 2 + length;
      if (length < 2 || end > b.length) return;
      yield (marker: marker, dataStart: i + 4, end: end);
      i = end;
    }
  }

  /// A one-tag EXIF segment holding only the orientation.
  static Uint8List _orientationOnlyExif(int orientation) => Uint8List.fromList([
    0xFF, 0xE1, 0x00, 0x22, // APP1, length 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big-endian TIFF header
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, 1
    0x00, orientation, 0x00, 0x00, // value
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ]);

  /// The Orientation tag of the TIFF structure at [tiff] (just after
  /// "Exif\0\0"), bounded by [limit]; 1 when absent or unreadable.
  static int _exifOrientation(Uint8List b, int tiff, int limit) {
    if (tiff + 8 > limit || tiff + 8 > b.length) return 1;
    final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
    final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
    if (!little && !big) return 1;
    final d = ByteData.sublistView(b);
    final endian = little ? Endian.little : Endian.big;
    final ifd = tiff + d.getUint32(tiff + 4, endian);
    if (ifd < tiff || ifd + 2 > limit) return 1;
    final count = d.getUint16(ifd, endian);
    for (var n = 0; n < count; n++) {
      final entry = ifd + 2 + n * 12;
      if (entry + 12 > limit) return 1;
      if (d.getUint16(entry, endian) == 0x0112) {
        final value = d.getUint16(entry + 8, endian);
        return value >= 1 && value <= 8 ? value : 1;
      }
    }
    return 1;
  }

  // ------------------------------------------------------------------- PNG

  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// Chunks that carry text, EXIF, a time stamp or a signature.
  static const _pngDrop = {
    'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME', 'dSIG', //
  };

  /// Strips a PNG's text, EXIF and time chunks and anything after IEND.
  static Uint8List? stripPng(Uint8List b) {
    if (b.length < 20 || !_startsWith(b, 0, _pngSignature)) return null;
    final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
    final d = ByteData.sublistView(b);
    var i = 8;
    var sawEnd = false;
    while (i + 12 <= b.length) {
      final length = d.getUint32(i);
      final end = i + 12 + length;
      if (end > b.length) return null;
      final type = String.fromCharCodes(b, i + 4, i + 8);
      if (!_pngDrop.contains(type)) {
        out.add(Uint8List.sublistView(b, i, end));
      }
      i = end;
      if (type == 'IEND') {
        sawEnd = true;
        break;
      }
    }
    return sawEnd ? out.takeBytes() : null;
  }

  // ------------------------------------------------------------------ WebP

  /// Strips a WebP's EXIF and XMP chunks, and clears their flags.
  static Uint8List? stripWebp(Uint8List b) {
    if (b.length < 20 ||
        !_startsWith(b, 0, const [0x52, 0x49, 0x46, 0x46]) ||
        !_startsWith(b, 8, const [0x57, 0x45, 0x42, 0x50])) {
      return null;
    }
    final d = ByteData.sublistView(b);
    final body = BytesBuilder(copy: false);
    var i = 12;
    final riffEnd = (8 + d.getUint32(4, Endian.little)).clamp(12, b.length);
    while (i + 8 <= riffEnd) {
      final fourcc = String.fromCharCodes(b, i, i + 4);
      final size = d.getUint32(i + 4, Endian.little);
      final padded = size + (size & 1);
      final end = i + 8 + padded;
      if (end > riffEnd + 1) return null;
      final stop = end > b.length ? b.length : end;
      if (fourcc == 'EXIF' || fourcc == 'XMP ') {
        // dropped
      } else if (fourcc == 'VP8X' && size >= 10) {
        final chunk = Uint8List.fromList(b.sublist(i, stop));
        chunk[8] = chunk[8] & ~0x08 & ~0x04; // EXIF and XMP flags
        body.add(chunk);
      } else {
        body.add(Uint8List.sublistView(b, i, stop));
      }
      i = end;
    }
    final payload = body.takeBytes();
    final out = Uint8List(12 + payload.length);
    out.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]);
    ByteData.sublistView(out).setUint32(4, 4 + payload.length, Endian.little);
    out.setRange(8, 12, const [0x57, 0x45, 0x42, 0x50]);
    out.setRange(12, out.length, payload);
    return out;
  }

  static bool _startsWith(Uint8List b, int at, List<int> magic) {
    if (at < 0 || at + magic.length > b.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[at + i] != magic[i]) return false;
    }
    return true;
  }
}
