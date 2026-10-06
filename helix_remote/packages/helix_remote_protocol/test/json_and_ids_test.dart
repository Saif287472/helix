import 'dart:math';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('JsonReader', () {
    test('names the failing field, never the value', () {
      final json = JsonReader.decode(
        '{"a":{"list":[{"id":"x"},{"id":5}]},"secret":"hunter2"}',
      );
      expect(
        () => json.object('a').objects('list', (i) => i.string('id')),
        throwsA(
          isA<ProtocolFormatException>()
              .having((e) => e.path, 'path', 'a.list[1].id')
              .having((e) => e.message, 'message', isNot(contains('5'))),
        ),
      );
      expect(
        () => json.integer('secret'),
        throwsA(
          isA<ProtocolFormatException>().having(
            (e) => e.toString(),
            'text',
            isNot(contains('hunter2')),
          ),
        ),
      );
    });

    test(
      'missing and null fields are the same; unknown fields are ignored',
      () {
        final json = JsonReader.decode('{"a":null,"extra":1}');
        expect(json.has('a'), isFalse);
        expect(json.optString('a'), isNull);
        expect(() => json.string('a'), throwsA(isA<ProtocolFormatException>()));
      },
    );

    test('bytes are unpadded base64url and decode with or without padding', () {
      final value = [0xfb, 0xff, 0x01];
      expect(encodeBytes(value), '-_8B');
      expect(decodeBytes('-_8B'), value);
      expect(decodeBytes('AQ=='), [1]);
      expect(() => decodeBytes('!!'), throwsA(isA<ProtocolFormatException>()));
    });

    test('integral doubles are accepted as integers', () {
      expect(JsonReader.decode('{"n":3.0}').integer('n'), 3);
      expect(
        () => JsonReader.decode('{"n":3.5}').integer('n'),
        throwsA(isA<ProtocolFormatException>()),
      );
    });

    test('out-of-range numbers and times are format errors, never '
        'RangeError or UnsupportedError', () {
      JsonReader reader(String source) => JsonReader.decode(source);
      for (final source in [
        '{"ts":9223372036854775807}',
        '{"ts":-9223372036854775808}',
        '{"ts":8640000000000001}',
        '{"ts":253402300800000}',
        '{"ts":-1}',
        '{"ts":1e400}',
        '{"ts":1e19}',
        '{"ts":9007199254740992}',
      ]) {
        expect(
          () => reader(source).time('ts'),
          throwsA(isA<ProtocolFormatException>()),
          reason: source,
        );
        expect(
          () => reader(source).optTime('ts'),
          throwsA(isA<FormatException>()),
          reason: source,
        );
      }
      expect(reader('{"ts":0}').time('ts'), DateTime.utc(1970));
      expect(
        reader('{"ts":253402300799999}').time('ts'),
        DateTime.utc(9999, 12, 31, 23, 59, 59, 999),
      );
      for (final source in ['{"n":1e400}', '{"n":-1e400}', '{"n":1e300}']) {
        expect(
          () => reader(source).integer('n'),
          throwsA(isA<ProtocolFormatException>()),
          reason: source,
        );
      }
      expect(reader('{"n":9007199254740991}').integer('n'), maxWireInt);
      expect(
        () => reader('{"n":11}').intIn('n', 0, 10),
        throwsA(isA<ProtocolFormatException>()),
      );
      expect(reader('{"n":10}').intIn('n', 0, 10), 10);
    });

    test('unknown enum values fall back only when asked to', () {
      final json = JsonReader.decode('{"k":"from_the_future"}');
      expect(
        json.enumValue('k', EnvelopeKind.values, orElse: EnvelopeKind.unknown),
        EnvelopeKind.unknown,
      );
      expect(
        () => json.enumValue('k', EnvelopeKind.values),
        throwsA(isA<ProtocolFormatException>()),
      );
    });

    test('a non-object root is rejected', () {
      expect(
        () => JsonReader.decode('[1]'),
        throwsA(isA<ProtocolFormatException>()),
      );
      expect(
        () => JsonReader.decode('{'),
        throwsA(isA<ProtocolFormatException>()),
      );
    });
  });

  group('Uuid', () {
    test('v7 is canonical, version 7, RFC variant, and carries its time', () {
      final at = DateTime.utc(2026, 10, 1, 8, 30, 15, 123);
      final id = Uuid.v7(now: at, random: Random(7));
      expect(Uuid.isValid(id), isTrue);
      expect(Uuid.isV7(id), isTrue);
      expect(Uuid.timeOfV7(id), at);
    });

    test('v7 ids sort by creation millisecond', () {
      final ids = [
        for (var ms = 0; ms < 50; ms++)
          Uuid.v7(
            now: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: ms * 13)),
          ),
      ];
      expect([...ids]..sort(), ids);
    });

    test('rejects non-canonical forms', () {
      expect(Uuid.isValid('0192A4F0-0000-7000-8000-00000000000A'), isFalse);
      expect(Uuid.isValid('0192a4f000007000800000000000000a'), isFalse);
      expect(Uuid.isV7('0192a4f0-0000-4000-8000-00000000000a'), isFalse);
    });

    test('uuidBytes inverts format', () {
      final id = Uuid.v7();
      expect(Uuid.format(uuidBytes(id)), id);
    });
  });

  group('paging', () {
    test('clamps limits and drops empty cursors', () {
      expect(
        PageRequest.fromQuery({'limit': '100000'}).limit,
        PageRequest.maxLimit,
      );
      expect(PageRequest.fromQuery({'limit': '0'}).limit, 1);
      expect(
        PageRequest.fromQuery({'limit': 'x'}).limit,
        PageRequest.defaultLimit,
      );
      expect(PageRequest.fromQuery({'cursor': ''}).cursor, isNull);
      expect(const PageRequest(cursor: 'c', limit: 5).toQuery(), {
        'cursor': 'c',
        'limit': '5',
      });
    });
  });
}
