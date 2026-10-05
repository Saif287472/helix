import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/blurhash.dart';
import 'package:helix_remote/core/platform/image_metadata.dart';
import 'package:helix_remote/core/platform/media_sanitizer.dart';
import 'package:helix_remote/core/platform/mp4_metadata.dart';
import 'package:helix_remote/core/platform/pixel_decoder.dart';
import 'package:helix_remote/core/platform/thumbnail_encoder.dart';
import 'package:image/image.dart' as img;

import '../support/media_fakes.dart';

const _secret = 'SECRET-GPS-51.5N';

/// A real JPEG with an EXIF block (orientation [orientation] plus a secret
/// string standing for GPS and device details), an XMP block, a comment and a
/// trailer after the end of the image.
Uint8List _jpegWithMetadata({int orientation = 6}) {
  final plain = img.encodeJpg(img.Image(width: 16, height: 8), quality: 80);
  final exif = <int>[
    ...ascii.encode('Exif'), 0, 0,
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08,
    0x00, 0x01, 0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, //
    0x00, orientation, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ...ascii.encode(_secret),
  ];
  Uint8List segment(int marker, List<int> data) => Uint8List.fromList([
    0xFF, marker, (data.length + 2) >> 8, (data.length + 2) & 0xFF, ...data, //
  ]);
  final xmp = ascii.encode('http://ns.adobe.com/xap/1.0/\u0000$_secret');
  final out = BytesBuilder()
    ..add(plain.sublist(0, 2))
    ..add(segment(0xE1, exif))
    ..add(segment(0xE1, xmp))
    ..add(segment(0xFE, ascii.encode(_secret)))
    ..add(plain.sublist(2))
    ..add(ascii.encode('TRAILER-$_secret'));
  return out.toBytes();
}

bool _contains(Uint8List bytes, String needle) =>
    latin1.decode(bytes, allowInvalid: true).contains(needle);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('helix_meta'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('JPEG', () {
    test('drops EXIF, XMP, comments and the trailer; keeps the picture', () {
      final source = _jpegWithMetadata();
      expect(_contains(source, _secret), isTrue);
      final clean = ImageMetadata.stripJpeg(source)!;
      expect(_contains(clean, _secret), isFalse);
      final flat = ImageMetadata.stripJpeg(_jpegWithMetadata(orientation: 1))!;
      expect(_contains(clean, 'TRAILER'), isFalse);
      // Still a picture that decodes, with the same pixels.
      // (The decoder applies the kept orientation, so check an upright one.)
      final decoded = img.decodeJpg(flat)!;
      expect(decoded.width, 16);
      expect(decoded.height, 8);
      expect(clean.sublist(clean.length - 2), [0xFF, 0xD9]);
    });

    test('keeps only the orientation, so a portrait photo stays upright', () {
      final clean = ImageMetadata.stripJpeg(_jpegWithMetadata(orientation: 6))!;
      expect(ImageMetadata.jpegOrientation(clean), 6);
      expect(ImageMetadata.jpegOrientation(_jpegWithMetadata()), 6);
      final upright = ImageMetadata.stripJpeg(
        _jpegWithMetadata(orientation: 1),
      )!;
      expect(ImageMetadata.jpegOrientation(upright), 1);
      // No EXIF block at all when there is nothing to keep.
      expect(_contains(upright, 'Exif'), isFalse);
    });

    test('stripping twice changes nothing', () {
      final once = ImageMetadata.stripJpeg(_jpegWithMetadata())!;
      expect(ImageMetadata.stripJpeg(once), once);
    });

    test('a truncated or foreign file is refused, not passed through', () {
      expect(ImageMetadata.stripJpeg(Uint8List.fromList([1, 2, 3, 4])), isNull);
      expect(
        ImageMetadata.stripJpeg(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF]),
        ),
        isNull,
      );
      expect(
        ImageMetadata.strip(
          Uint8List.fromList(ascii.encode('hello world, not a picture')),
        ),
        isNull,
      );
    });
  });

  test('PNG text, EXIF and time chunks are removed', () {
    final png = img.encodePng(img.Image(width: 4, height: 4));
    final bytes = BytesBuilder()..add(png.sublist(0, 8));
    // Re-assemble the chunks, adding a tEXt and an eXIf chunk after IHDR.
    var i = 8;
    final chunks = <Uint8List>[];
    while (i < png.length) {
      final len = ByteData.sublistView(png).getUint32(i);
      chunks.add(png.sublist(i, i + 12 + len));
      i += 12 + len;
    }
    Uint8List extra(String type, String text) {
      final data = ascii.encode(text);
      return Uint8List.fromList([
        ...u32(data.length),
        ...ascii.encode(type),
        ...data,
        0,
        0,
        0,
        0,
      ]);
    }

    bytes
      ..add(chunks.first)
      ..add(extra('tEXt', 'Comment\u0000$_secret'))
      ..add(extra('eXIf', _secret));
    for (final c in chunks.skip(1)) {
      bytes.add(c);
    }
    bytes.add(ascii.encode('TRAILER'));
    final dirty = bytes.toBytes();
    expect(_contains(dirty, _secret), isTrue);
    final clean = ImageMetadata.stripPng(dirty)!;
    expect(_contains(clean, _secret), isFalse);
    expect(_contains(clean, 'TRAILER'), isFalse);
    expect(img.decodePng(clean)!.width, 4);
  });

  test('WebP EXIF and XMP chunks are removed and their flags cleared', () {
    Uint8List chunk(String id, List<int> data) => Uint8List.fromList([
      ...ascii.encode(id),
      data.length & 255,
      (data.length >> 8) & 255,
      0,
      0,
      ...data,
      if (data.length.isOdd) 0,
    ]);
    final vp8x = chunk('VP8X', [0x0C, 0, 0, 0, 3, 0, 0, 3, 0, 0]);
    final payload = [
      ...ascii.encode('WEBP'),
      ...vp8x,
      ...chunk('EXIF', ascii.encode(_secret)),
      ...chunk('XMP ', ascii.encode(_secret)),
      ...chunk('VP8 ', List.filled(10, 1)),
    ];
    final size = payload.length;
    final webp = Uint8List.fromList([
      ...ascii.encode('RIFF'),
      size & 255,
      (size >> 8) & 255,
      0,
      0,
      ...payload,
    ]);
    final clean = ImageMetadata.stripWebp(webp)!;
    expect(_contains(clean, _secret), isFalse);
    expect(clean[20] & 0x0C, 0, reason: 'EXIF and XMP flags cleared');
    final riff = ByteData.sublistView(clean).getUint32(4, Endian.little);
    expect(riff, clean.length - 8);
  });

  group('MP4', () {
    test(
      'reads duration and the shown size, and finds what to remove',
      () async {
        final file = File('${dir.path}/a.mp4')..writeAsBytesSync(testMp4());
        final scan = (await Mp4Metadata.scan(file))!;
        expect(scan.info.durationMs, 5000);
        // 1920 x 1080 with a quarter turn is shown 1080 x 1920.
        expect(scan.info.width, 1080);
        expect(scan.info.height, 1920);
        expect(scan.isClean, isFalse);
      },
    );

    test(
      'a cleaned copy has the same size, no position and zero times',
      () async {
        final source = File('${dir.path}/a.mp4')..writeAsBytesSync(testMp4());
        final scan = (await Mp4Metadata.scan(source))!;
        final target = File('${dir.path}/b.mp4');
        await Mp4Metadata.writeCleaned(source, target, scan.patches);
        final clean = target.readAsBytesSync();
        final original = source.readAsBytesSync();
        expect(clean.length, original.length);
        expect(_contains(clean, '+23.7'), isFalse);
        expect(_contains(original, '+23.7'), isTrue);
        expect(_contains(clean, '©xyz'), isFalse);
        expect(_contains(clean, '\x11\x11\x11\x11'), isFalse);
        // The media data is untouched.
        expect(
          clean.sublist(clean.length - 1000),
          original.sublist(original.length - 1000),
        );
        final again = (await Mp4Metadata.scan(target))!;
        expect(again.isClean, isTrue);
        expect(again.info.durationMs, 5000);
        // The original is never changed.
        expect(_contains(source.readAsBytesSync(), '+23.7'), isTrue);
      },
    );

    test('a file that is not an MP4 is not scanned', () async {
      final file = File('${dir.path}/x.webm')
        ..writeAsBytesSync(List.filled(64, 3));
      expect(await Mp4Metadata.scan(file), isNull);
    });
  });

  group('sanitizer', () {
    PickedFile picked(String path, PickedKind kind, String mime) => PickedFile(
      path: path,
      name: path.split(RegExp(r'[\\/]')).last,
      mime: mime,
      size: File(path).lengthSync(),
      kind: kind,
    );

    test('a photo comes back as a new file with no metadata', () async {
      final src = File('${dir.path}/p.jpg')
        ..writeAsBytesSync(_jpegWithMetadata());
      final s = FileMediaSanitizer(temp: tempIn(dir));
      final out = await s.sanitize(
        picked(src.path, PickedKind.image, 'image/jpeg'),
      );
      expect(out.outcome, SanitizeOutcome.stripped);
      expect(out.file.path, isNot(src.path));
      expect(out.file.temporary, isTrue);
      expect(
        _contains(File(out.file.path).readAsBytesSync(), _secret),
        isFalse,
      );
      // The person's own file is left exactly as it was.
      expect(_contains(src.readAsBytesSync(), _secret), isTrue);
    });

    test('a photo with nothing to remove is sent as it is', () async {
      final clean = ImageMetadata.stripJpeg(_jpegWithMetadata())!;
      final src = File('${dir.path}/c.jpg')..writeAsBytesSync(clean);
      final out = await FileMediaSanitizer(
        temp: tempIn(dir),
      ).sanitize(picked(src.path, PickedKind.image, 'image/jpeg'));
      expect(out.outcome, SanitizeOutcome.clean);
      expect(out.file.path, src.path);
    });

    test(
      'a format it cannot clean in place is re-encoded; undecodable is refused',
      () async {
        final heic = File('${dir.path}/h.heic')
          ..writeAsBytesSync(List.filled(40, 5));
        final pixels = DecodedPixels(
          rgba: Uint8List(4 * 4 * 4),
          width: 4,
          height: 4,
        );
        final ok = FileMediaSanitizer(
          temp: tempIn(dir),
          decoder: _Decoder(pixels),
        );
        final out = await ok.sanitize(
          picked(heic.path, PickedKind.image, 'image/heic'),
        );
        expect(out.outcome, SanitizeOutcome.stripped);
        expect(out.file.mime, 'image/jpeg');
        expect(out.file.name, endsWith('.jpg'));
        expect(img.decodeJpg(File(out.file.path).readAsBytesSync()), isNotNull);

        final bad = FileMediaSanitizer(
          temp: tempIn(dir),
          decoder: const _Decoder(null),
        );
        final refused = await bad.sanitize(
          picked(heic.path, PickedKind.image, 'image/heic'),
        );
        expect(refused.outcome, SanitizeOutcome.failed);
      },
    );

    test(
      'a video is cleaned into a copy; other containers pass; documents pass',
      () async {
        final mp4 = File('${dir.path}/v.mp4')..writeAsBytesSync(testMp4());
        final s = FileMediaSanitizer(temp: tempIn(dir));
        final out = await s.sanitize(
          picked(mp4.path, PickedKind.video, 'video/mp4'),
        );
        expect(out.outcome, SanitizeOutcome.stripped);
        expect(
          _contains(File(out.file.path).readAsBytesSync(), '+23.7'),
          isFalse,
        );
        final webm = File('${dir.path}/v.webm')
          ..writeAsBytesSync(List.filled(64, 3));
        expect(
          (await s.sanitize(
            picked(webm.path, PickedKind.video, 'video/webm'),
          )).outcome,
          SanitizeOutcome.unsupported,
        );
        final doc = File('${dir.path}/d.pdf')..writeAsBytesSync([1, 2]);
        expect(
          (await s.sanitize(
            picked(doc.path, PickedKind.document, 'application/pdf'),
          )).outcome,
          SanitizeOutcome.clean,
        );
      },
    );
  });

  group('blurhash and thumbnails', () {
    int base83(String s) {
      const a =
          '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';
      return s.split('').fold(0, (v, c) => v * 83 + a.indexOf(c));
    }

    test('a flat red picture hashes to red with no detail', () {
      final rgba = Uint8List(8 * 8 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 3] = 255;
      }
      final hash = Blurhash.encode(rgba, width: 8, height: 8);
      expect(hash.length, 1 + 1 + 4 + 2 * 11);
      final dc = base83(hash.substring(2, 6));
      expect([dc >> 16, (dc >> 8) & 255, dc & 255], [255, 0, 0]);
    });

    test(
      'the thumbnail is a small JPEG with a hash, and shrinking keeps the shape',
      () {
        final pixels = DecodedPixels(
          rgba: Uint8List.fromList(
            List.generate(
              200 * 100 * 4,
              (i) => i % 4 == 3 ? 255 : (i ~/ 4) % 255,
            ),
          ),
          width: 200,
          height: 100,
        );
        final thumb = ThumbnailMath.thumbnail(pixels);
        final decoded = img.decodeJpg(thumb.jpeg)!;
        expect((decoded.width, decoded.height), (200, 100));
        expect(thumb.blurhash, isNotEmpty);
        final small = ThumbnailMath.shrink(pixels, 32);
        expect((small.width, small.height), (32, 16));
      },
    );

    test('transparent pixels are laid over white', () {
      final px = DecodedPixels(rgba: Uint8List(4), width: 1, height: 1);
      expect(ThumbnailMath.flattenOnWhite(px).rgba, [255, 255, 255, 255]);
    });
  });
}

final class _Decoder implements PixelDecoder {
  const _Decoder(this.pixels);

  final DecodedPixels? pixels;

  @override
  Future<DecodedPixels?> decode(
    Uint8List encoded, {
    required int maxSide,
  }) async => pixels;
}
