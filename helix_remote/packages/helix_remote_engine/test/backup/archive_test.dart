import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/backup/archive.dart';
import 'package:test/test.dart';

/// The archive layout shared by the history backup, the full backup and the
/// transfer: frames of NDJSON, independent of each other.
void main() {
  Uint8List join(Iterable<ArchiveFrame> frames) {
    final out = BytesBuilder();
    for (final f in frames) {
      out.add(f.bytes);
    }
    return out.takeBytes();
  }

  List<Map<String, Object?>> read(List<int> bytes, {bool zip = true}) => [
    for (final frame in ArchiveReader.frames(bytes, gzip: zip ? gzip : null))
      for (final r in ArchiveReader.records(frame)) r.json,
  ];

  BackupFailure failureOf(void Function() action) {
    try {
      action();
    } on BackupException catch (e) {
      return e.failure;
    }
    fail('expected a BackupException');
  }

  test('records round trip, raw and gzip, across frames', () {
    for (final codec in [null, gzip]) {
      final writer = ArchiveWriter(gzip: codec, frameBytes: 300);
      final frames = <ArchiveFrame>[];
      for (var i = 0; i < 100; i++) {
        writer.add({
          't': 'msg',
          'id': 'm$i',
          'body': 'text ' * 10,
        }, message: true);
        frames.addAll(writer.takeFrames());
      }
      frames.addAll(writer.finish());
      expect(frames.length, greaterThan(5));
      expect(frames.fold<int>(0, (n, f) => n + f.messages), 100);
      final records = read(join(frames), zip: true);
      expect(
        [for (final r in records) r['id']],
        [for (var i = 0; i < 100; i++) 'm$i'],
      );
    }
  });

  test('gzip frames are smaller for text and are read back without the '
      'writer', () {
    final raw = ArchiveWriter();
    final packed = ArchiveWriter(gzip: gzip);
    for (var i = 0; i < 200; i++) {
      final record = {
        't': 'msg',
        'id': 'm$i',
        'body': 'hello hello hello ' * 5,
      };
      raw.add(record);
      packed.add(record);
    }
    final rawBytes = join(raw.finish());
    final packedBytes = join(packed.finish());
    expect(packedBytes.length, lessThan(rawBytes.length ~/ 3));
    expect(read(packedBytes), read(rawBytes));
  });

  test('a gzip archive cannot be read without a gzip codec', () {
    final writer = ArchiveWriter(gzip: gzip)
      ..add({'t': 'msg', 'body': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'});
    final bytes = join(writer.finish());
    expect(
      failureOf(() => read(bytes, zip: false)),
      BackupFailure.compressionUnavailable,
    );
  });

  test('a record too long to read back is dropped, not written', () {
    final writer = ArchiveWriter();
    expect(writer.add({'t': 'msg', 'body': 'x' * (2 * 1024 * 1024)}), isFalse);
    expect(writer.add({'t': 'msg', 'body': 'ok'}), isTrue);
    expect(read(join(writer.finish())), [
      {'t': 'msg', 'body': 'ok'},
    ]);
  });

  test('a gzip frame that inflates past the limit is dropped while it '
      'inflates', () {
    final payload = gzip.encode(Uint8List(32 * 1024 * 1024 + 1));
    expect(payload.length, lessThan(8 * 1024 * 1024), reason: 'a small bomb');
    final frame = Uint8List(5 + payload.length);
    ByteData.sublistView(frame).setUint32(0, 1 + payload.length);
    frame[4] = 1;
    frame.setRange(5, frame.length, payload);
    expect(failureOf(() => read(frame)), BackupFailure.corrupt);
    // A frame exactly at the limit still reads.
    final ok = gzip.encode(Uint8List(1024));
    final small = Uint8List(5 + ok.length);
    ByteData.sublistView(small).setUint32(0, 1 + ok.length);
    small[4] = 1;
    small.setRange(5, small.length, ok);
    expect(ArchiveReader.frames(small, gzip: gzip).single, hasLength(1024));
  });

  test('structural damage is corrupt, a codec from the future is newer', () {
    final writer = ArchiveWriter()..add({'t': 'header'});
    final good = join(writer.finish());

    // Truncated in the middle of a frame, and a bare length.
    expect(
      failureOf(() => read(good.sublist(0, good.length - 1))),
      BackupFailure.corrupt,
    );
    expect(failureOf(() => read([0, 0, 0])), BackupFailure.corrupt);
    // A length that claims more than the limit, and zero.
    expect(
      failureOf(() => read([0x7f, 0xff, 0xff, 0xff, 0])),
      BackupFailure.corrupt,
    );
    expect(failureOf(() => read([0, 0, 0, 0, 0])), BackupFailure.corrupt);
    // A frame that is not JSON.
    final junk = Uint8List.fromList([...utf8.encode('not json\n')]);
    final framed = Uint8List(5 + junk.length);
    ByteData.sublistView(framed).setUint32(0, 1 + junk.length);
    framed.setRange(5, framed.length, junk);
    expect(failureOf(() => read(framed)), BackupFailure.corrupt);
    // Gzip that is not gzip.
    final fakeZip = Uint8List.fromList([0, 0, 0, 4, 1, 1, 2, 3]);
    expect(failureOf(() => read(fakeZip)), BackupFailure.corrupt);
    // An unknown frame codec.
    final future = Uint8List.fromList(good)..[4] = 9;
    expect(failureOf(() => read(future)), BackupFailure.newerFormat);
  });

  test('an empty archive has no frames', () {
    expect(read(Uint8List(0)), isEmpty);
  });
}
