/// A PNG, read or written, with no dependency on an image library.
///
/// `package:image` is in the pub cache but is **not** a declared dependency of
/// this package, so this file is the minimum needed instead. `dart:io`'s
/// zlib does the DEFLATE work (`ZLibDecoder`/`ZLibEncoder`); everything else -
/// chunk walking, CRC-32, the row filters and the palette/greyscale/alpha
/// expansion - is here, because a screenshot tool that cannot read a PNG it was
/// handed is worse than useless. If `package:image` is ever added to
/// `orbit_ui/pubspec.yaml`, this file can be deleted and replaced by
/// `img.decodePng` / `img.encodePng` without changing a single caller.
///
/// Everything here is deterministic: the same bytes in give the same bytes out.
library;

import 'dart:io';
import 'dart:typed_data';

const List<int> _signature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// Thrown for anything wrong with a PNG: not a PNG, a corrupt one, a
/// colour type or bit depth this file does not implement, a CRC that does not
/// match. The compare tool turns these into a failed comparison, never into a
/// score.
final class OrbitPngException implements Exception {
  OrbitPngException(this.message);

  final String message;

  @override
  String toString() => 'OrbitPngException: $message';
}

/// One image, always as 8-bit straight-alpha RGBA, top row first.
///
/// Every PNG this package writes and every PNG it compares is flattened to this
/// form, so a comparison never depends on how a file happened to be encoded.
final class OrbitImage {
  OrbitImage({
    required this.width,
    required this.height,
    required this.pixels,
  }) {
    final expected = width * height * 4;
    if (width <= 0 || height <= 0) {
      throw OrbitPngException(
        'an image is ${width}x$height; that is not an '
        'image',
      );
    }
    if (pixels.length != expected) {
      throw OrbitPngException(
        '${width}x$height needs $expected RGBA bytes, '
        'got ${pixels.length}',
      );
    }
  }

  /// Builds an image from a tightly packed RGB buffer (3 bytes per pixel),
  /// which is what an 8-bit truecolour PNG expands to.
  factory OrbitImage.fromRgb(int width, int height, Uint8List rgb) {
    final out = Uint8List(width * height * 4);
    final n = width * height;
    for (var i = 0; i < n; i++) {
      out[i * 4] = rgb[i * 3];
      out[i * 4 + 1] = rgb[i * 3 + 1];
      out[i * 4 + 2] = rgb[i * 3 + 2];
      out[i * 4 + 3] = 255;
    }
    return OrbitImage(width: width, height: height, pixels: out);
  }

  final int width;
  final int height;

  /// RGBA, four bytes per pixel, row major, straight (not premultiplied)
  /// alpha.
  final Uint8List pixels;

  int get pixelCount => width * height;

  /// The number of distinct opaque colours, used only to say whether a
  /// screenshot drew anything at all.
  int distinctColours() {
    final seen = <int>{};
    for (var i = 0; i < pixels.length; i += 4) {
      // A screenshot is opaque, so colour is the RGB triple. The alpha byte is
      // left out of the count so a uniform image with a stray alpha cannot
      // look busier than it is.
      seen.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
      if (seen.length > 4096) return seen.length;
    }
    return seen.length;
  }

  /// Copies of this image with the same size.
  OrbitImage blank() => OrbitImage(
    width: width,
    height: height,
    pixels: Uint8List(pixels.length),
  );
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/// Reads a PNG into an [OrbitImage], or throws [OrbitPngException].
///
/// Every failure is an error and never a warning: a file this cannot read
/// means the comparison does not happen.
///
/// Throws for: too short, wrong signature, a CRC that does not match, an
/// interlace method other than none, a colour type outside the five the spec
/// defines, and any bit depth whose sample size is not an integer number of
/// bytes per pixel boundary it can handle. Bit depths 1, 2, 4, 8 and 16 are
/// all read; 16-bit is reduced to its high byte, which is the PNG's own advice
/// for display.
OrbitImage decodeOrbitPng(Uint8List bytes, {String name = 'image'}) {
  if (bytes.length < _signature.length) {
    throw OrbitPngException(
      '$name: ${bytes.length} bytes is too short to be a PNG',
    );
  }
  for (var i = 0; i < _signature.length; i++) {
    if (bytes[i] != _signature[i]) {
      throw OrbitPngException('$name: not a PNG (bad signature byte $i)');
    }
  }

  var pos = _signature.length;
  int? width;
  int? height;
  int bitDepth = -1;
  int colourType = -1;
  int interlace = -1;
  Uint8List? palette;
  Uint8List? paletteAlpha;
  int? greyKey;
  int? redKey;
  int? greenKey;
  int? blueKey;
  final idat = BytesBuilder(copy: false);
  var sawHeader = false;
  var sawEnd = false;

  while (pos + 8 <= bytes.length) {
    final length = _uint32(bytes, pos);
    final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    final dataStart = pos + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) {
      throw OrbitPngException(
        '$name: chunk $type claims $length bytes and '
        'runs past the end of the file',
      );
    }
    final want = _crc32(bytes, pos + 4, dataEnd);
    final got = _uint32(bytes, dataEnd);
    if (want != got) {
      throw OrbitPngException(
        '$name: chunk $type has CRC '
        '${got.toRadixString(16)}, computed ${want.toRadixString(16)}; the '
        'file is truncated or edited',
      );
    }
    final data = bytes.sublist(dataStart, dataEnd);
    pos = dataEnd + 4;

    switch (type) {
      case 'IHDR':
        if (sawHeader) {
          throw OrbitPngException('$name: two IHDR chunks');
        }
        sawHeader = true;
        if (data.length < 13) {
          throw OrbitPngException('$name: IHDR is ${data.length} bytes');
        }
        width = _uint32(data, 0);
        height = _uint32(data, 4);
        bitDepth = data[8];
        colourType = data[9];
        final compression = data[10];
        final filterMethod = data[11];
        interlace = data[12];
        if (width == 0 || height == 0) {
          throw OrbitPngException('$name: declares ${width}x$height');
        }
        if (compression != 0) {
          throw OrbitPngException(
            '$name: compression method $compression is '
            'not 0 (deflate)',
          );
        }
        if (filterMethod != 0) {
          throw OrbitPngException(
            '$name: filter method $filterMethod is not 0',
          );
        }
        if (interlace != 0) {
          // Adam7 needs seven passes over the image. Nothing this tool writes
          // or reads produces it, and guessing would be exactly the kind of
          // silent difference this tool exists to prevent.
          throw OrbitPngException(
            '$name: is interlaced (Adam7); re-save it '
            'non-interlaced',
          );
        }
        _checkDepthAndType(name, bitDepth, colourType);
      case 'PLTE':
        palette = data;
      case 'tRNS':
        if (colourType == 3) {
          paletteAlpha = data;
        } else if (colourType == 0 && data.length >= 2) {
          greyKey = (data[0] << 8) | data[1];
        } else if (colourType == 2 && data.length >= 6) {
          redKey = (data[0] << 8) | data[1];
          greenKey = (data[2] << 8) | data[3];
          blueKey = (data[4] << 8) | data[5];
        }
      case 'IDAT':
        idat.add(data);
      case 'IEND':
        sawEnd = true;
      default:
        // A PNG may carry chunks this tool has never heard of (gAMA, tEXt,
        // pHYs). Skipping them is reading the format, not guessing.
        break;
    }
    if (sawEnd) break;
  }

  if (!sawHeader || width == null || height == null) {
    throw OrbitPngException('$name: no IHDR chunk');
  }
  if (!sawEnd) {
    throw OrbitPngException('$name: no IEND chunk; the file is truncated');
  }
  if (colourType == 3 && palette == null) {
    throw OrbitPngException('$name: an indexed image with no PLTE chunk');
  }

  final channels = _channels(colourType);
  final bitsPerPixel = channels * bitDepth;
  final stride = (width * bitsPerPixel + 7) >> 3;
  final bytesPerPixel = (bitsPerPixel + 7) >> 3;
  final expected = height * (stride + 1);

  final List<int> inflated;
  try {
    inflated = ZLibDecoder().convert(idat.takeBytes());
  } on Object catch (e) {
    throw OrbitPngException('$name: the image data does not inflate ($e)');
  }
  if (inflated.length < expected) {
    throw OrbitPngException(
      '$name: the image data is ${inflated.length} '
      'bytes, needs $expected for ${width}x$height at bit depth $bitDepth',
    );
  }
  if (inflated.length > expected) {
    throw OrbitPngException(
      '$name: the image data is ${inflated.length} '
      'bytes, needs exactly $expected for ${width}x$height at bit depth '
      '$bitDepth',
    );
  }

  final lines = Uint8List(height * stride);
  var at = 0;
  for (var y = 0; y < height; y++) {
    final filter = inflated[at++];
    final rowStart = y * stride;
    final prevStart = rowStart - stride;
    for (var x = 0; x < stride; x++) {
      final raw = inflated[at++];
      final left = x >= bytesPerPixel ? lines[rowStart + x - bytesPerPixel] : 0;
      final up = y > 0 ? lines[prevStart + x] : 0;
      final upLeft = (x >= bytesPerPixel && y > 0)
          ? lines[prevStart + x - bytesPerPixel]
          : 0;
      final int value = switch (filter) {
        0 => raw,
        1 => raw + left,
        2 => raw + up,
        3 => raw + ((left + up) >> 1),
        4 => raw + _paeth(left, up, upLeft),
        _ => throw OrbitPngException(
          '$name: row $y uses filter $filter, which the PNG spec does not '
          'define',
        ),
      };
      lines[rowStart + x] = value & 0xFF;
    }
  }

  // Copied out so the transparent-colour checks below do not depend on flow
  // analysis through a switch inside a loop.
  final gk = greyKey;
  final rk = redKey;
  final gkc = greenKey;
  final bk = blueKey;
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final rowStart = y * stride;
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      switch (colourType) {
        case 0:
          final g = _sample(lines, rowStart, x, bitDepth);
          out[o] = g;
          out[o + 1] = g;
          out[o + 2] = g;
          out[o + 3] = (gk != null && _keyMatches(g, bitDepth, gk)) ? 0 : 255;
        case 2:
          final base = _index(lines, rowStart, x, bitDepth, channels);
          final r = _channel(lines, base, 0, bitDepth);
          final g = _channel(lines, base, 1, bitDepth);
          final b = _channel(lines, base, 2, bitDepth);
          out[o] = r;
          out[o + 1] = g;
          out[o + 2] = b;
          out[o + 3] =
              (rk != null &&
                  gkc != null &&
                  bk != null &&
                  r == (rk >> 8) &&
                  g == (gkc >> 8) &&
                  b == (bk >> 8))
              ? 0
              : 255;
        case 3:
          final index = _sample(lines, rowStart, x, bitDepth);
          final p = palette!;
          if (index * 3 + 2 >= p.length) {
            throw OrbitPngException(
              '$name: pixel $index is outside a '
              '${p.length ~/ 3}-entry palette',
            );
          }
          out[o] = p[index * 3];
          out[o + 1] = p[index * 3 + 1];
          out[o + 2] = p[index * 3 + 2];
          out[o + 3] = (paletteAlpha != null && index < paletteAlpha.length)
              ? paletteAlpha[index]
              : 255;
        case 4:
          final base = _index(lines, rowStart, x, bitDepth, channels);
          final g = _channel(lines, base, 0, bitDepth);
          out[o] = g;
          out[o + 1] = g;
          out[o + 2] = g;
          out[o + 3] = _channel(lines, base, 1, bitDepth);
        default:
          final base = _index(lines, rowStart, x, bitDepth, channels);
          out[o] = _channel(lines, base, 0, bitDepth);
          out[o + 1] = _channel(lines, base, 1, bitDepth);
          out[o + 2] = _channel(lines, base, 2, bitDepth);
          out[o + 3] = _channel(lines, base, 3, bitDepth);
      }
    }
  }

  return OrbitImage(width: width, height: height, pixels: out);
}

void _checkDepthAndType(String name, int bitDepth, int colourType) {
  const depths = <int, List<int>>{
    0: <int>[1, 2, 4, 8, 16], // greyscale
    2: <int>[8, 16], // truecolour
    3: <int>[1, 2, 4, 8], // indexed
    4: <int>[8, 16], // greyscale + alpha
    6: <int>[8, 16], // truecolour + alpha
  };
  final allowed = depths[colourType];
  if (allowed == null) {
    throw OrbitPngException(
      '$name: colour type $colourType is not one the '
      'PNG spec defines',
    );
  }
  if (!allowed.contains(bitDepth)) {
    throw OrbitPngException(
      '$name: colour type $colourType cannot be bit '
      'depth $bitDepth (it allows ${allowed.join(', ')})',
    );
  }
}

int _channels(int colourType) => switch (colourType) {
  0 => 1,
  2 => 3,
  3 => 1,
  4 => 2,
  _ => 4,
};

/// The byte offset of sample [index] of the row, for 8- and 16-bit depths.
int _index(Uint8List lines, int rowStart, int x, int bitDepth, int channels) {
  if (bitDepth == 8) return rowStart + x * channels;
  return rowStart + x * channels * 2;
}

/// Channel [channel] of the pixel at [base], as its high byte.
///
/// The stride is 1 at a bit depth of 8 and 2 at 16, where the sample is two
/// bytes wide and the low byte is the half that display does not need.
int _channel(Uint8List lines, int base, int channel, int bitDepth) =>
    lines[base + channel * (bitDepth == 16 ? 2 : 1)];

/// The 8-bit value of sample [x], whatever the depth.
int _sample(Uint8List lines, int rowStart, int x, int bitDepth) {
  if (bitDepth == 8) return lines[rowStart + x];
  if (bitDepth == 16) return lines[rowStart + x * 2];
  final perByte = 8 ~/ bitDepth;
  final byte = lines[rowStart + (x ~/ perByte)];
  final shift = 8 - bitDepth * ((x % perByte) + 1);
  final mask = (1 << bitDepth) - 1;
  return (byte >> shift) & mask;
}

bool _keyMatches(int value, int bitDepth, int key) =>
    bitDepth == 16 ? value == ((key >> 8) & 0xFF) : value == key;

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

int _uint32(Uint8List bytes, int at) =>
    (bytes[at] << 24) |
    (bytes[at + 1] << 16) |
    (bytes[at + 2] << 8) |
    bytes[at + 3];

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

/// Writes [image] as an 8-bit RGBA PNG.
///
/// The output is byte-for-byte the same for the same input: every row is
/// filtered with the same fixed heuristic (the filter whose bytes sum to the
/// least, ties going to the lower filter number) and the DEFLATE level is
/// fixed. Nothing here reads the clock or a random source.
///
/// The channel mix is adaptive on purpose. Screenshots are mostly large flat
/// areas, and the difference between "None" everywhere and the right filter
/// per row is roughly a factor of three in bytes; that matters when a full run
/// writes three artefacts for every one of 236 screen states.
Uint8List encodeOrbitPng(OrbitImage image, {int level = 6}) {
  final out = BytesBuilder(copy: false);
  out.add(_signature);

  final ihdr = BytesBuilder(copy: false)
    ..add(_uint32Bytes(image.width))
    ..add(_uint32Bytes(image.height))
    ..add(<int>[8, 6, 0, 0, 0]);
  _addChunk(out, 'IHDR', ihdr.takeBytes());

  final w = image.width;
  final h = image.height;
  final stride = w * 4;
  final filtered = Uint8List(h * (stride + 1));

  // Filter working sets: one candidate row per filter type.
  final candidate = Uint8List(stride);
  final previous = Uint8List(stride);
  final current = Uint8List(stride);
  final best = Uint8List(stride);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < stride; x++) {
      current[x] = image.pixels[y * stride + x];
    }
    var bestFilter = 0;
    var bestScore = -1;
    for (var f = 0; f < 5; f++) {
      var score = 0;
      for (var x = 0; x < stride; x++) {
        final left = x >= 4 ? current[x - 4] : 0;
        final up = previous[x];
        final upLeft = x >= 4 ? previous[x - 4] : 0;
        final int v = switch (f) {
          0 => current[x],
          1 => current[x] - left,
          2 => current[x] - up,
          3 => current[x] - ((left + up) >> 1),
          _ => current[x] - _paeth(left, up, upLeft),
        };
        final byte = v & 0xFF;
        candidate[x] = byte;
        // Signed magnitude: a byte of 0xFF is -1 and compresses well, while
        // 0x01 is +1 and does not. This is the heuristic the PNG spec suggests.
        score += byte < 128 ? byte : 256 - byte;
      }
      if (bestScore < 0 || score < bestScore) {
        bestScore = score;
        bestFilter = f;
        best.setRange(0, stride, candidate);
      }
    }
    final at = y * (stride + 1);
    filtered[at] = bestFilter;
    filtered.setRange(at + 1, at + 1 + stride, best);
    previous.setRange(0, stride, current);
  }

  _addChunk(
    out,
    'IDAT',
    Uint8List.fromList(
      ZLibEncoder(level: level).convert(Uint8List.sublistView(filtered)),
    ),
  );
  _addChunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

Uint8List _uint32Bytes(int value) => Uint8List.fromList(<int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

void _addChunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out
    ..add(_uint32Bytes(data.length))
    ..add(typeBytes)
    ..add(data);
  final crc = _crc32(typeBytes, 0, typeBytes.length, seedFrom: data);
  out.add(_uint32Bytes(crc));
}

// ---------------------------------------------------------------------------
// CRC-32 (PNG's, polynomial 0xEDB88320 reflected)
// ---------------------------------------------------------------------------

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

/// The CRC-32 of `bytes[start, end)` followed by `tail`, which is how a chunk
/// is defined: the type and the data, but not the length.
int _crc32(Uint8List bytes, int start, int end, {Uint8List? seedFrom}) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < end; i++) {
    c = _crcTable[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  if (seedFrom != null) {
    for (var i = 0; i < seedFrom.length; i++) {
      c = _crcTable[(c ^ seedFrom[i]) & 0xFF] ^ (c >> 8);
    }
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
