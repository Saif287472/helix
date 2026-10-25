import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/image_metadata.dart';
import 'package:helix_remote/core/platform/media_sanitizer.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:helix_remote/core/platform/profile_image_source.dart';
import 'package:image/image.dart' as img;

/// What a file is, and what is left in it when it goes (B21).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('helix_kind_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the system's temp cleaner.
    }
  });

  /// A JPEG with a comment segment standing for the camera's metadata.
  Uint8List jpeg() {
    final plain = img.encodeJpg(img.Image(width: 8, height: 8), quality: 80);
    final comment = 'SECRET-GPS'.codeUnits;
    return Uint8List.fromList([
      ...plain.sublist(0, 2),
      0xFF, 0xFE, (comment.length + 2) >> 8, (comment.length + 2) & 0xFF,
      ...comment, //
      ...plain.sublist(2),
    ]);
  }

  Uint8List isoBox(String brand) => Uint8List.fromList([
    0, 0, 0, 24, ...'ftyp'.codeUnits, ...brand.codeUnits, //
    0, 0, 0, 0, ...brand.codeUnits, ...'mp41'.codeUnits,
  ]);

  group('a file is what its bytes say (AUD-14c-1)', () {
    PickedKind kindOf(String name, Uint8List head) =>
        describePickedFile(path: '/x/$name', size: 100, head: head).kind;

    test('a photo without a known name is still a photo', () {
      final j = jpeg();
      expect(kindOf('IMG_0001', j), PickedKind.image);
      expect(kindOf('photo.heif', isoBox('mif1')), PickedKind.image);
      expect(kindOf('photo.avif', isoBox('avif')), PickedKind.image);
      expect(kindOf('scan', isoBox('heic')), PickedKind.image);
      expect(
        kindOf('scan.tif', Uint8List.fromList([0x49, 0x49, 0x2A, 0, 1, 2])),
        PickedKind.image,
      );
      expect(
        kindOf(
          'IMG_0002',
          Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
        ),
        PickedKind.image,
      );
      expect(kindOf('x.bin', isoBox('isom')), PickedKind.video);
    });

    test('the name still decides when the bytes say nothing', () {
      final nothing = Uint8List.fromList(List.filled(32, 7));
      expect(kindOf('notes.txt', nothing), PickedKind.document);
      expect(kindOf('a.heif', nothing), PickedKind.image);
      expect(kindOf('song.mp3', nothing), PickedKind.audio);
      expect(
        describePickedFile(path: '/x/plain', size: 1).kind,
        PickedKind.document,
        reason: 'no head, no name: a document',
      );
    });

    test('a photo with no extension is cleaned before it is sent', () async {
      final src = File('${dir.path}/IMG_0001')..writeAsBytesSync(jpeg());
      final head = await readHead(src.path);
      final file = describePickedFile(
        path: src.path,
        size: src.lengthSync(),
        head: head,
      );
      expect(file.kind, PickedKind.image);
      final out = await FileMediaSanitizer(
        temp: MediaTemp(root: () async => dir),
      ).sanitize(file);
      expect(out.outcome, SanitizeOutcome.stripped);
      expect(
        String.fromCharCodes(File(out.file.path).readAsBytesSync()),
        isNot(contains('SECRET-GPS')),
      );
    });
  });

  group('a GIF keeps its frames and loses its words (AUD-14c-4)', () {
    // A one-frame 1x1 GIF with a Comment, an XMP packet and a NETSCAPE loop.
    List<int> sub(List<int> data) => [data.length, ...data, 0];
    Uint8List gif({bool trailer = true}) => Uint8List.fromList([
      ...'GIF89a'.codeUnits,
      1, 0, 1, 0, 0x80, 0, 0, // 1x1, a 2-colour global palette
      0, 0, 0, 255, 255, 255,
      0x21, 0xFE, ...sub('written by Someone, a camera model'.codeUnits),
      0x21, 0xFF, 11, ...'XMP DataXMP'.codeUnits,
      ...sub('<x:xmpmeta SECRET-GPS/>'.codeUnits),
      0x21, 0xFF, 11, ...'NETSCAPE2.0'.codeUnits, ...sub([1, 0, 0]),
      0x21, 0xF9, 4, 0, 10, 0, 0, 0,
      0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x44, 1, 0,
      if (trailer) 0x3B,
    ]);

    test('comments and XMP go, the loop and the picture stay', () {
      final stripped = ImageMetadata.stripGif(gif())!;
      final text = String.fromCharCodes(stripped);
      expect(text, isNot(contains('Someone')));
      expect(text, isNot(contains('SECRET-GPS')));
      expect(text, isNot(contains('XMP Data')));
      expect(text, contains('NETSCAPE2.0'));
      expect(stripped.last, 0x3B);
      expect(stripped.length, lessThan(gif().length));
      // And it is still a GIF a decoder reads, with its frame.
      expect(img.decodeGif(stripped), isNotNull);
      // Cleaning is idempotent: a clean GIF is returned as it is.
      expect(ImageMetadata.stripGif(stripped), stripped);
    });

    test('a truncated one is refused, not passed on', () {
      expect(ImageMetadata.stripGif(gif(trailer: false)), isNull);
      expect(
        ImageMetadata.stripGif(Uint8List.fromList('GIF89a'.codeUnits)),
        isNull,
      );
      expect(
        ImageMetadata.stripGif(Uint8List.sublistView(gif(), 0, 30)),
        isNull,
      );
    });

    test('the sanitizer returns it cleaned', () async {
      final src = File('${dir.path}/anim.gif')..writeAsBytesSync(gif());
      final out =
          await FileMediaSanitizer(
            temp: MediaTemp(root: () async => dir),
          ).sanitize(
            describePickedFile(
              path: src.path,
              size: src.lengthSync(),
              head: await readHead(src.path),
            ),
          );
      expect(out.outcome, SanitizeOutcome.stripped);
      expect(
        String.fromCharCodes(File(out.file.path).readAsBytesSync()),
        isNot(contains('Someone')),
      );
    });
  });

  testWidgets('a large photo is cropped to the square it should be '
      '(AUD-14c-2)', (tester) async {
    await tester.runAsync(() async {
      final big = Uint8List.fromList(
        img.encodePng(img.Image(width: 4000, height: 3000)),
      );
      final png = await DeviceProfileImageSource.cropToSquare(big);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (256, 256));
      frame.image.dispose();
      codec.dispose();
      await expectLater(
        DeviceProfileImageSource.cropToSquare(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ProfileImageException>()),
      );
    });
  });
}
