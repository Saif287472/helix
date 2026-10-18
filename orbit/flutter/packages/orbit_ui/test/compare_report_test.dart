import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/compare.dart';

/// The artefacts and the JSON the compare page reads.
///
/// The thing checked here that nothing else checks: a failed comparison
/// carries **no** score (the page must not be able to render a number where
/// nothing was compared). The whole pipeline, from a real render to the page,
/// is run by the preview app's shoot mode (`apps/orbit_preview/lib/shoot.dart`).
void main() {
  OrbitImage picture(int width, int height, {int seed = 0}) {
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final o = (y * width + x) * 4;
        pixels[o] = (x * 5 + y * 3 + seed) % 256;
        pixels[o + 1] = (x * 2 + seed) % 256;
        pixels[o + 2] = (y * 7 + seed) % 256;
        pixels[o + 3] = 255;
      }
    }
    return OrbitImage(width: width, height: height, pixels: pixels);
  }

  /// Writes the two halves of one comparison into [root], and returns the job.
  OrbitCompareJob stageJob(
    Directory root,
    OrbitShotSpec spec, {
    int seed = 0,
    int changedPixels = 0,
  }) {
    final dir = Directory('${root.path}/shots')..createSync(recursive: true);
    final prototype = File('${dir.path}/${spec.fileName}')
      ..writeAsBytesSync(
        encodeOrbitPng(
          picture(spec.device.width, spec.device.height, seed: seed),
        ),
      );

    // The same picture, with the first [changedPixels] pixels nudged.
    final other = picture(spec.device.width, spec.device.height, seed: seed);
    for (var p = 0; p < changedPixels; p++) {
      other.pixels[p * 4] = (other.pixels[p * 4] + 9) % 256;
    }
    final flutter = File('${dir.path}/flutter/${spec.fileName}')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(encodeOrbitPng(other));

    return OrbitCompareJob(
      spec: spec,
      htmlPath: prototype.path,
      flutterPath: flutter.path,
    );
  }

  group('the JSON shape', () {
    late Directory root;
    late OrbitCompareResult result;

    setUp(() {
      root = Directory.systemTemp.createTempSync('orbit_report_test');
      const spec = OrbitShotSpec(
        'group',
        device: OrbitDevice.phone,
        theme: 'orbit',
      );
      final job = stageJob(root, spec, changedPixels: 1);
      result = compareOrbitJob(job, outDir: '${root.path}/compare');
      writeOrbitResultsJson(
        <OrbitCompareResult>[result],
        path: '${root.path}/compare/results.json',
        device: OrbitDevice.phone,
        theme: 'orbit',
      );
    });

    tearDown(() => root.deleteSync(recursive: true));

    Map<String, Object?> readResults() =>
        jsonDecode(File('${root.path}/compare/results.json').readAsStringSync())
            as Map<String, Object?>;

    test('the row carries the key, the device, the theme, the score and both '
        'paths', () {
      final row = readResults()['results']! as List<Object?>;
      expect(row, hasLength(1));
      final entry = row.single! as Map<String, Object?>;

      expect(entry['key'], 'group');
      expect(entry['device'], 'phone');
      expect(entry['theme'], 'orbit');
      expect(entry['scroll'], 0);
      expect(entry['width'], 412);
      expect(entry['height'], 866);
      expect(entry['status'], 'compared');
      expect(entry['score'], isA<double>());
      expect(entry['html'], isA<String>());
      expect(entry['flutter'], isA<String>());
      expect(entry['diff'], isA<String>());
      expect(entry['overlay'], isA<String>());
      expect(entry['totalPixels'], 356792);
      expect(entry['differingPixels'], 1);
      // 1 pixel of 356,792 is 0.00028%; the JSON rounds to six places.
      expect(entry['score'], closeTo(100 / 356792, 5e-7));
    });

    test('every path in the JSON resolves from beside results.json', () {
      final entry =
          (readResults()['results']! as List<Object?>).single!
              as Map<String, Object?>;
      final base = Directory('${root.path}/compare');
      for (final field in <String>['html', 'flutter', 'diff', 'overlay']) {
        final path = entry[field]! as String;
        expect(
          path,
          isNot(contains(r'\')),
          reason: '$field must use forward slashes so a browser can load it',
        );
        expect(
          File('${base.path}${Platform.pathSeparator}$path').existsSync(),
          isTrue,
          reason: '$field points at $path, which is not there',
        );
      }
    });

    test('the top of the file says what the score means', () {
      final json = readResults();
      expect(json['tool'], 'compare_dart');
      expect(json['format'], 1);
      expect(json['device'], 'phone');
      expect(json['theme'], 'orbit');
      expect(json['size'], <int>[412, 866]);
      expect(json['overlayMix'], 0.5);
      expect(json['sort'], 'worst first');
      expect(json['scoreMeaning'], orbitScoreMeaning);
      expect((json['totals']! as Map<String, Object?>)['compared'], 1);
      expect((json['totals']! as Map<String, Object?>)['failed'], 0);
    });

    test('the heat map marks exactly the pixels that differ', () {
      final entry =
          (readResults()['results']! as List<Object?>).single!
              as Map<String, Object?>;
      final heat = decodeOrbitPng(
        File('${root.path}/compare/${entry['diff']}').readAsBytesSync(),
      );
      expect(heat.width, 412);
      expect(heat.height, 866);

      // The one changed pixel is somewhere in the 80x60 picture pasted into
      // the top left of a 412x866 frame. Every marked pixel is the yellow the
      // ramp starts at, and there is exactly one of them.
      final marks = <int>[];
      for (var i = 0; i < heat.pixelCount; i++) {
        final o = i * 4;
        // Background is a grey (r == g == b); a mark is not.
        if (heat.pixels[o] != heat.pixels[o + 1] ||
            heat.pixels[o + 1] != heat.pixels[o + 2]) {
          marks.add(i);
        }
      }
      expect(marks, hasLength(1));
      expect(heat.pixels[marks.single * 4], 255);
      expect(heat.pixels[marks.single * 4 + 2], 0);
      expect(
        heat.pixels[marks.single * 4 + 1],
        lessThan(255),
        reason: 'the ramp runs from yellow to red with the channel delta',
      );
    });

    test('the overlay is halfway between the two', () {
      final entry =
          (readResults()['results']! as List<Object?>).single!
              as Map<String, Object?>;
      final overlay = decodeOrbitPng(
        File('${root.path}/compare/${entry['overlay']}').readAsBytesSync(),
      );
      final a = decodeOrbitPng(
        File('${root.path}/compare/${entry['html']}').readAsBytesSync(),
      );
      final b = decodeOrbitPng(
        File('${root.path}/compare/${entry['flutter']}').readAsBytesSync(),
      );
      // A 50/50 blend is the rounded mean of the two, channel by channel,
      // and opaque.
      final expected = Uint8List(a.pixels.length);
      for (var i = 0; i < expected.length; i += 4) {
        for (var c = 0; c < 3; c++) {
          expected[i + c] = ((a.pixels[i + c] + b.pixels[i + c]) / 2).round();
        }
        expected[i + 3] = 255;
      }
      expect(overlay.pixels, orderedEquals(expected));
      // And the one changed pixel really moved, so the check above can fail.
      expect(overlay.pixels, isNot(orderedEquals(a.pixels)));
    });

    test('writing it twice produces the same bytes', () {
      final first = File(
        '${root.path}/compare/results.json',
      ).readAsStringSync();
      writeOrbitResultsJson(
        <OrbitCompareResult>[result],
        path: '${root.path}/compare/results.json',
        device: OrbitDevice.phone,
        theme: 'orbit',
      );
      final second = File(
        '${root.path}/compare/results.json',
      ).readAsStringSync();
      expect(
        second,
        first,
        reason:
            'no timestamps, no absolute paths, no map order: a rerun of '
            'the same batch must produce the same file',
      );
    });
  });

  group('worst first', () {
    test('the worst screen is the top row', () {
      final root = Directory.systemTemp.createTempSync('orbit_report_sort');
      addTearDown(() => root.deleteSync(recursive: true));

      final results = <OrbitCompareResult>[];
      // Fewer differing pixels first, then more, then none: the writer must
      // not preserve the order it was given.
      for (final (key, changed) in <(String, int)>[
        ('group', 0),
        ('chats', 40),
        ('settings', 4),
      ]) {
        final job = stageJob(
          root,
          OrbitShotSpec(key, device: OrbitDevice.phone, theme: 'orbit'),
          changedPixels: changed,
        );
        results.add(compareOrbitJob(job, outDir: '${root.path}/compare'));
      }

      final sorted = sortWorstFirst(results);
      expect(
        sorted.map((r) => r.spec.key),
        <String>['chats', 'settings', 'group'],
        reason: '40 changed pixels is the worst, then 4, then 0',
      );

      writeOrbitResultsJson(
        results,
        path: '${root.path}/compare/results.json',
        device: OrbitDevice.phone,
        theme: 'orbit',
      );
      final rows =
          (jsonDecode(
                    File(
                      '${root.path}/compare/results.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, Object?>)['results']!
              as List<Object?>;
      expect(rows.map((r) => (r! as Map<String, Object?>)['key']), <String>[
        'chats',
        'settings',
        'group',
      ]);
    });
  });

  group('a comparison that did not happen has no score', () {
    late Directory root;

    setUp(
      () => root = Directory.systemTemp.createTempSync('orbit_report_fail'),
    );
    tearDown(() => root.deleteSync(recursive: true));

    test('a missing Flutter render is thrown by default', () {
      final job = stageJob(
        root,
        const OrbitShotSpec('group', device: OrbitDevice.phone, theme: 'orbit'),
      );
      File(job.flutterPath).deleteSync();
      expect(
        () => compareOrbitJob(job, outDir: '${root.path}/compare'),
        throwsA(isA<OrbitCompareException>()),
      );
    });

    test('recorded instead, it has a reason and no score key at all', () {
      final job = stageJob(
        root,
        const OrbitShotSpec('group', device: OrbitDevice.phone, theme: 'orbit'),
      );
      File(job.flutterPath).deleteSync();

      final results = compareOrbitJobs(
        <OrbitCompareJob>[job],
        outDir: '${root.path}/compare',
        stopOnError: false,
      );
      expect(results.single.status, OrbitCompareStatus.failed);
      expect(results.single.score, isNull);
      expect(results.single.diff, isNull);

      writeOrbitResultsJson(
        results,
        path: '${root.path}/compare/results.json',
        device: OrbitDevice.phone,
        theme: 'orbit',
      );
      final row =
          (jsonDecode(
                    File(
                      '${root.path}/compare/results.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, Object?>)['results']!
              as List<Object?>;
      final entry = row.single! as Map<String, Object?>;
      expect(
        entry.containsKey('score'),
        isFalse,
        reason:
            'a missing key, not a null: the page must not be able to read '
            'a number where there was no comparison',
      );
      expect(entry['status'], 'failed');
      expect(entry['reason'], contains('no file at'));
    });

    test('a size mismatch is never resized away', () {
      final job = stageJob(
        root,
        const OrbitShotSpec('group', device: OrbitDevice.phone, theme: 'orbit'),
      );
      File(job.flutterPath).writeAsBytesSync(encodeOrbitPng(picture(80, 61)));
      expect(
        () => compareOrbitJob(job, outDir: '${root.path}/compare'),
        throwsA(
          isA<OrbitCompareException>()
              .having((e) => e.message, 'message', contains('412x866'))
              .having((e) => e.message, 'message', contains('80x61')),
        ),
      );
    });
  });

  group('the two manifests are paired by key, device, theme and offset', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('orbit_plan'));
    tearDown(() => root.deleteSync(recursive: true));

    void manifestOf(
      String tool,
      List<(String, int)> shots, {
      String device = 'phone',
    }) =>
        OrbitShotManifest(
          tool: tool,
          shots: [
            for (final (key, scroll) in shots)
              OrbitManifestShot(
                spec: OrbitShotSpec(
                  key,
                  device: OrbitDevice.byWireName(device),
                  theme: 'orbit',
                  scroll: scroll,
                ),
                file: orbitShotFileName(
                  key,
                  device: OrbitDevice.byWireName(device),
                  theme: 'orbit',
                  scroll: scroll,
                ),
                ok: true,
                reason: '',
                width: 412,
                height: 866,
                bytes: 1,
              ),
          ],
        ).write(
          '${root.path}/$tool.json',
          device: OrbitDevice.byWireName(device),
          theme: 'orbit',
        );

    test('a key on both sides becomes one job', () {
      manifestOf('shoot_html', <(String, int)>[('group', 0), ('chats', 0)]);
      manifestOf('shoot_flutter', <(String, int)>[('group', 0), ('chats', 0)]);
      final batch = planOrbitBatch(
        html: OrbitShotManifest.read('${root.path}/shoot_html.json'),
        flutter: OrbitShotManifest.read('${root.path}/shoot_flutter.json'),
        htmlDir: '${root.path}/shots',
        flutterDir: '${root.path}/shots/flutter',
      );
      expect(batch.jobs.map((j) => j.spec.key), <String>['chats', 'group']);
      expect(batch.missing, isEmpty);
    });

    test('the same key at two scroll offsets is two comparisons', () {
      manifestOf('shoot_html', <(String, int)>[('group', 0), ('group', 760)]);
      manifestOf('shoot_flutter', <(String, int)>[
        ('group', 0),
        ('group', 760),
      ]);
      final batch = planOrbitBatch(
        html: OrbitShotManifest.read('${root.path}/shoot_html.json'),
        flutter: OrbitShotManifest.read('${root.path}/shoot_flutter.json'),
        htmlDir: '${root.path}/shots',
        flutterDir: '${root.path}/shots/flutter',
      );
      expect(batch.jobs, hasLength(2));
      expect(
        batch.jobs.map((j) => j.spec.fileName),
        containsAll(<String>[
          'group.phone.orbit.png',
          'group.scroll760.phone.orbit.png',
        ]),
      );
    });

    test('a key on one side only is reported, not silently dropped', () {
      manifestOf('shoot_html', <(String, int)>[('group', 0), ('chats', 0)]);
      manifestOf('shoot_flutter', <(String, int)>[('group', 0), ('calls', 0)]);
      final batch = planOrbitBatch(
        html: OrbitShotManifest.read('${root.path}/shoot_html.json'),
        flutter: OrbitShotManifest.read('${root.path}/shoot_flutter.json'),
        htmlDir: '${root.path}/shots',
        flutterDir: '${root.path}/shots/flutter',
      );
      expect(batch.jobs.map((j) => j.spec.key), <String>['group']);
      expect(batch.missing.map((m) => '${m.spec.key}:${m.side}'), <String>[
        'calls:prototype',
        'chats:flutter',
      ]);
    });
  });

  group('the device table', () {
    test('the sizes are the ones shoot_html.py shoots at', () {
      expect(OrbitDevice.phone.width, 412);
      expect(OrbitDevice.phone.height, 866);
      expect(OrbitDevice.windowM.wireName, 'window-m');
      expect(OrbitDevice.windowM.width, 960);
      expect(OrbitDevice.windowM.height, 720);
      expect(OrbitDevice.windowL.wireName, 'window-l');
      expect(OrbitDevice.windowL.width, 1280);
      expect(OrbitDevice.windowL.height, 800);
    });

    test('file names round trip', () {
      for (final device in OrbitDevice.values) {
        for (final scroll in <int>[0, 760]) {
          final name = orbitShotFileName(
            'chat-rec',
            device: device,
            theme: 'night',
            scroll: scroll,
          );
          final parsed = orbitParseShotFileName(name);
          expect(parsed.key, 'chat-rec');
          expect(parsed.device, device);
          expect(parsed.theme, 'night');
          expect(parsed.scroll, scroll);
        }
      }
    });

    test('an unknown device is an error, not the phone', () {
      expect(
        () => OrbitDevice.byWireName('tablet'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => orbitParseShotFileName('group.tablet.orbit.png'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
